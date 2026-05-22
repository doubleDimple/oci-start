package com.doubledimple.ociserver.utils.oracle.ai;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.generativeaiinference.GenerativeAiInferenceClient;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import javax.annotation.PreDestroy;
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
/*@Slf4j
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

    public OciAiClientManager() {
        // 启动定时清理任务
        startCleanupTask();
    }

    *//**
     * 获取或创建AI客户端上下文（包含客户端和compartmentId）
     *
     * @param tenant 租户信息
     * @return 客户端上下文
     *//*
    public ClientContext getClientContext(Tenant tenant) {
        String tenantKey = generateTenantKey(tenant);

        ClientWrapper wrapper = clientCache.compute(tenantKey, (key, existing) -> {
            if (existing == null || existing.isExpired()) {
                // 创建新客户端
                if (existing != null) {
                    // 关闭旧客户端
                    closeClientSafely(existing.client);
                }
                return createNewClient(tenant);
            } else {
                // 更新最后使用时间
                existing.updateLastUsedTime();
                return existing;
            }
        });

        return new ClientContext(wrapper.client, wrapper.compartmentId);
    }

    *//**
     * 获取或创建AI客户端（仅返回客户端，向后兼容）
     *
     * @param tenant 租户信息
     * @return AI客户端
     *//*
    public GenerativeAiInferenceClient getClient(Tenant tenant) {
        return getClientContext(tenant).getClient();
    }

    *//**
     * 创建新的客户端包装器
     *//*
    private ClientWrapper createNewClient(Tenant tenant) {
        try {
            SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
            GenerativeAiInferenceClient client = GenerativeAiInferenceClient.builder()
                    .build(provider);

            // 从provider获取compartmentId（通常是tenantId）
            String compartmentId = provider.getTenantId();

            log.info("创建新的AI客户端 - 租户: {}, compartmentId: {}",
                    tenant.getTenantId(), compartmentId);
            return new ClientWrapper(client, compartmentId);
        } catch (Exception e) {
            log.error("创建AI客户端失败 - 租户: {}", tenant.getTenantId(), e);
            throw new RuntimeException("创建AI客户端失败", e);
        }
    }

    *//**
     * 生成租户缓存键
     *//*
    private String generateTenantKey(Tenant tenant) {
        return String.format("%s_%s_%s",
                tenant.getTenantId(),
                tenant.getUserName(),
                tenant.getRegion());
    }

    *//**
     * 启动定时清理任务
     *//*
    private void startCleanupTask() {
        cleanupExecutor.scheduleWithFixedDelay(() -> {
            try {
                cleanupExpiredClients();
            } catch (Exception e) {
                log.error("清理过期客户端时出错", e);
            }
        }, CLEANUP_INTERVAL, CLEANUP_INTERVAL, TimeUnit.SECONDS);
    }

    *//**
     * 清理过期的客户端
     *//*
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

    *//**
     * 安全关闭客户端
     *//*
    private void closeClientSafely(GenerativeAiInferenceClient client) {
        if (client != null) {
            try {
                client.close();
            } catch (Exception e) {
                log.error("关闭AI客户端时出错", e);
            }
        }
    }

    *//**
     * 手动移除特定租户的客户端
     *//*
    public void removeClient(Tenant tenant) {
        String tenantKey = generateTenantKey(tenant);
        ClientWrapper wrapper = clientCache.remove(tenantKey);
        if (wrapper != null) {
            closeClientSafely(wrapper.client);
            log.info("手动移除AI客户端 - 租户: {}", tenant.getTenantId());
        }
    }

    *//**
     * 获取当前缓存的客户端数量
     *//*
    public int getCachedClientCount() {
        return clientCache.size();
    }

    *//**
     * 清理所有客户端
     *//*
    @PreDestroy
    public void destroy() {
        log.debug("开始销毁AI客户端管理器...");

        // 停止清理任务
        cleanupExecutor.shutdown();
        try {
            if (!cleanupExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                cleanupExecutor.shutdownNow();
            }
        } catch (InterruptedException e) {
            cleanupExecutor.shutdownNow();
            Thread.currentThread().interrupt();
        }

        // 关闭所有客户端
        for (ClientWrapper wrapper : clientCache.values()) {
            closeClientSafely(wrapper.client);
        }
        clientCache.clear();

        log.debug("AI客户端管理器销毁完成");
    }

    *//**
     * 客户端包装器
     *//*
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

    *//**
     * 客户端上下文，包含客户端和相关配置信息
     *//*
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
}*/
