package com.doubledimple.ociai.utils;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.generativeaiinference.GenerativeAiInferenceClient;
import com.oracle.bmc.http.ClientConfigurator;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.annotation.PreDestroy;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * OCI AI客户端管理器
 * 管理GenerativeAiInferenceClient的生命周期，实现客户端复用和自动清理
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Slf4j
@Component
public class OciAiClientManager {

    // 存储每个租户的AI客户端
    private final Map<String, ClientWrapper> clientCache = new ConcurrentHashMap<>();

    // 定时清理任务执行器
    private final ScheduledExecutorService cleanupExecutor = Executors.newSingleThreadScheduledExecutor();

    // 客户端空闲超时时间（毫秒）
    private static final long CLIENT_IDLE_TIMEOUT = 10 * 60 * 1000; // 10分钟

    // 清理任务执行间隔（秒）
    private static final long CLEANUP_INTERVAL = 60; // 1分钟

    /** server 注入：创建 client 时传入代理配置 */
    private TenantProxyApplier tenantProxyApplier;

    public OciAiClientManager() {
        startCleanupTask();
    }

    @Autowired(required = false)
    public void setTenantProxyApplier(TenantProxyApplier tenantProxyApplier) {
        this.tenantProxyApplier = tenantProxyApplier;
        if (tenantProxyApplier != null) {
            log.info("OciAiClientManager 已接入 TenantProxyApplier（server 代理）");
        }
    }

    /**
     * 获取或创建AI客户端上下文（包含客户端和compartmentId）
     */
    public ClientContext getClientContext(Tenant tenant) {
        String tenantKey = generateTenantKey(tenant);

        ClientWrapper wrapper = clientCache.compute(tenantKey, (key, existing) -> {
            if (existing == null || existing.isExpired()) {
                if (existing != null) {
                    closeClientSafely(existing.client);
                }
                return createNewClient(tenant);
            } else {
                existing.updateLastUsedTime();
                return existing;
            }
        });

        return new ClientContext(wrapper.client, wrapper.compartmentId);
    }

    /**
     * 获取或创建AI客户端（仅返回客户端，向后兼容）
     */
    public GenerativeAiInferenceClient getClient(Tenant tenant) {
        return getClientContext(tenant).getClient();
    }

    /**
     * 由 server 侧 applier 绑定代理，供推理 client / 管理 client 共用。
     */
    public ClientConfigurator resolveProxy(Tenant tenant) {
        return tenantProxyApplier != null ? tenantProxyApplier.apply(tenant) : null;
    }

    /**
     * 构建认证 Provider（不含代理；代理经 {@link #resolveProxy} 单独传入 builder）。
     */
    public static SimpleAuthenticationDetailsProvider buildAuthProvider(Tenant tenant) {
        return SimpleAuthenticationDetailsProvider.builder()
                .userId(tenant.getTenantId())
                .fingerprint(tenant.getFingerprint())
                .tenantId(tenant.getTenancy())
                .privateKeySupplier(() -> {
                    try {
                        return new FileInputStream(tenant.getKeyFile());
                    } catch (FileNotFoundException e) {
                        e.printStackTrace();
                        return null;
                    }
                })
                .region(Region.fromRegionId(RegionEnum.getRegionCode(tenant.getRegion())))
                .build();
    }

    private ClientWrapper createNewClient(Tenant tenant) {
        try {
            // server 注入的 applier：先绑代理，再把 configurator 穿进 OCI client
            ClientConfigurator proxy = resolveProxy(tenant);
            SimpleAuthenticationDetailsProvider provider = buildAuthProvider(tenant);
            GenerativeAiInferenceClient client = GenerativeAiInferenceClient.builder()
                    .clientConfigurator(proxy)
                    .build(provider);

            String compartmentId = provider.getTenantId();

            log.info("创建新的AI客户端 - 租户: {}, compartmentId: {}, proxy={}",
                    tenant.getTenantId(), compartmentId, proxy != null);
            return new ClientWrapper(client, compartmentId);
        } catch (Exception e) {
            log.error("创建AI客户端失败 - 租户: {}", tenant.getTenantId(), e);
            throw new RuntimeException("创建AI客户端失败", e);
        }
    }

    private String generateTenantKey(Tenant tenant) {
        return String.format("%s_%s_%s",
                tenant.getTenantId(),
                tenant.getUserName(),
                tenant.getRegion());
    }

    private void startCleanupTask() {
        cleanupExecutor.scheduleWithFixedDelay(() -> {
            try {
                cleanupExpiredClients();
            } catch (Exception e) {
                log.error("清理过期客户端时出错", e);
            }
        }, CLEANUP_INTERVAL, CLEANUP_INTERVAL, TimeUnit.SECONDS);
    }

    private void cleanupExpiredClients() {
        int cleanedCount = 0;

        for (Map.Entry<String, ClientWrapper> entry : clientCache.entrySet()) {
            ClientWrapper wrapper = entry.getValue();
            if (wrapper.isExpired()) {
                String key = entry.getKey();
                clientCache.remove(key);
                closeClientSafely(wrapper.client);
                cleanedCount++;
                log.debug("清理过期AI客户端: {}", key);
            }
        }

        if (cleanedCount > 0) {
            log.info("清理了 {} 个过期的AI客户端，当前缓存大小: {}",
                    cleanedCount, clientCache.size());
        }
    }

    private void closeClientSafely(GenerativeAiInferenceClient client) {
        if (client != null) {
            try {
                client.close();
            } catch (Exception e) {
                log.error("关闭AI客户端时出错", e);
            }
        }
    }

    public void removeClient(Tenant tenant) {
        String tenantKey = generateTenantKey(tenant);
        ClientWrapper wrapper = clientCache.remove(tenantKey);
        if (wrapper != null) {
            closeClientSafely(wrapper.client);
            log.info("手动移除AI客户端 - 租户: {}", tenant.getTenantId());
        }
    }

    public int getCachedClientCount() {
        return clientCache.size();
    }

    @PreDestroy
    public void destroy() {
        log.debug("开始销毁AI客户端管理器...");

        cleanupExecutor.shutdown();
        try {
            if (!cleanupExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                cleanupExecutor.shutdownNow();
            }
        } catch (InterruptedException e) {
            cleanupExecutor.shutdownNow();
            Thread.currentThread().interrupt();
        }

        for (ClientWrapper wrapper : clientCache.values()) {
            closeClientSafely(wrapper.client);
        }
        clientCache.clear();

        log.debug("AI客户端管理器销毁完成");
    }

    private static class ClientWrapper {
        private final GenerativeAiInferenceClient client;
        private final String compartmentId;
        private volatile long lastUsedTime;

        public ClientWrapper(GenerativeAiInferenceClient client, String compartmentId) {
            this.client = client;
            this.compartmentId = compartmentId;
            this.lastUsedTime = System.currentTimeMillis();
        }

        public void updateLastUsedTime() {
            this.lastUsedTime = System.currentTimeMillis();
        }

        public boolean isExpired() {
            return System.currentTimeMillis() - lastUsedTime > CLIENT_IDLE_TIMEOUT;
        }
    }

    public static class ClientContext {
        private final GenerativeAiInferenceClient client;
        private final String compartmentId;

        public ClientContext(GenerativeAiInferenceClient client, String compartmentId) {
            this.client = client;
            this.compartmentId = compartmentId;
        }

        public GenerativeAiInferenceClient getClient() {
            return client;
        }

        public String getCompartmentId() {
            return compartmentId;
        }
    }
}
