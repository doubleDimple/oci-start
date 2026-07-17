package com.doubledimple.ociserver.config;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.ociserver.utils.SocksProxyUtils;
import com.oracle.bmc.http.ClientConfigurator;
import com.oracle.bmc.http.client.jersey.JerseyClientProperty;
import lombok.extern.slf4j.Slf4j;
import org.glassfish.jersey.client.ClientProperties;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.function.Supplier;

/**
 * 按父租户绑定 SOCKS/HTTP 代理到当前线程 {@link ProxyContext}。
 * <p>
 * 供两类场景使用：
 * <ul>
 *   <li>静态工具 {@code utils.oracle.*}：在 {@code OciUtils.getProvider(tenant)} 时自动绑定</li>
 *   <li>定时任务：循环租户时每个租户调用一次，会先 clear 再 set，避免串代理</li>
 *   <li>{@code @UseSocksProxy} 切面复用本类逻辑</li>
 * </ul>
 * 创建 OCI Client 时需 {@code .clientConfigurator(ProxyContext.get())}。
 */
@Slf4j
@Component
public class TenantProxyBinder {

    private static final int STATUS_AVAILABLE = 1;

    private static volatile TenantProxyBinder INSTANCE;

    @Resource
    private VpnProxyRecordRepository vpnProxyRecordRepository;

    @Resource
    private TenantRepository tenantRepository;

    @PostConstruct
    public void init() {
        INSTANCE = this;
    }

    @PreDestroy
    public void destroy() {
        if (INSTANCE == this) {
            INSTANCE = null;
        }
    }

    /**
     * 按租户实体绑定代理（null 则只清上下文并尝试全局代理）。
     */
    public static void applyForTenant(Tenant tenant) {
        TenantProxyBinder binder = INSTANCE;
        if (binder == null) {
            return;
        }
        if (tenant == null) {
            binder.applyForTenantId(null);
            return;
        }
        binder.applyForTenantId(tenant.getId());
    }

    /**
     * 按租户主键绑定；会归一到父租户。null 表示仅全局池。
     */
    public static void applyForTenantId(Long tenantPk) {
        TenantProxyBinder binder = INSTANCE;
        if (binder == null) {
            return;
        }
        binder.doApply(tenantPk);
    }

    public static void clear() {
        ProxyContext.clear();
    }

    /**
     * 在绑定租户代理的作用域内执行，结束后清理（定时任务推荐）。
     */
    public static void runWithTenant(Tenant tenant, Runnable action) {
        try {
            applyForTenant(tenant);
            action.run();
        } finally {
            clear();
        }
    }

    public static <T> T callWithTenant(Tenant tenant, Supplier<T> action) {
        try {
            applyForTenant(tenant);
            return action.get();
        } finally {
            clear();
        }
    }

    private void doApply(Long tenantPk) {
        // 先清，避免定时任务上一个租户的代理泄漏到下一个
        ProxyContext.clear();

        Long parentTenantId = resolveParentTenantId(tenantPk);
        VpnProxyRecord proxyConfig = selectProxy(parentTenantId);
        if (proxyConfig == null) {
            log.debug("无可用代理，直连 parentTenantId={}", parentTenantId);
            return;
        }
        if (proxyConfig.getAvailableStatus() == null || proxyConfig.getAvailableStatus() != STATUS_AVAILABLE) {
            log.debug("代理已禁用，直连 {}:{}", proxyConfig.getProxyHost(), proxyConfig.getProxyPort());
            return;
        }
        try {
            if (!SocksProxyUtils.isProxyAvailable(proxyConfig)) {
                log.warn("代理探测不可用，跳过 {}:{}", proxyConfig.getProxyHost(), proxyConfig.getProxyPort());
                return;
            }
            applyProxy(proxyConfig);
            log.debug("已绑定代理 {}:{} [{}] parentTenantId={}",
                    proxyConfig.getProxyHost(),
                    proxyConfig.getProxyPort(),
                    proxyConfig.getProxyType(),
                    parentTenantId);
        } catch (Exception e) {
            log.warn("绑定代理失败 parentTenantId={}: {}", parentTenantId, e.getMessage());
            ProxyContext.clear();
        }
    }

    private VpnProxyRecord selectProxy(Long parentTenantId) {
        if (parentTenantId != null) {
            VpnProxyRecord bound = vpnProxyRecordRepository.findAvailableByTenantId(parentTenantId, STATUS_AVAILABLE);
            if (bound != null) {
                return bound;
            }
        }
        return vpnProxyRecordRepository.findRandomAvailableGlobal(STATUS_AVAILABLE);
    }

    private Long resolveParentTenantId(Long tenantPk) {
        if (tenantPk == null) {
            return null;
        }
        try {
            Tenant tenant = tenantRepository.findById(tenantPk).orElse(null);
            if (tenant == null) {
                return tenantPk;
            }
            Long parenId = tenant.getParenId();
            if (parenId == null || parenId == 0L) {
                return tenant.getId();
            }
            return parenId;
        } catch (Exception e) {
            log.debug("解析父租户失败 tenantPk={}: {}", tenantPk, e.getMessage());
            return tenantPk;
        }
    }

    private void applyProxy(VpnProxyRecord proxyConfig) throws URISyntaxException {
        String host = proxyConfig.getProxyHost();
        int port = proxyConfig.getProxyPort();
        String proxyUsername = proxyConfig.getProxyUsername();
        String proxyPassword = proxyConfig.getProxyPassword();
        String proxyType = proxyConfig.getProxyType().toLowerCase();
        URI proxyUri = new URI(proxyType, null, host, port, null, null, null);
        String url = proxyUri.toString();
        ClientConfigurator proxyConfigurator = clientBuilder -> {
            clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_URI), url);
            if (proxyUsername != null && proxyPassword != null) {
                clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_USERNAME), proxyUsername);
                clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_PASSWORD), proxyPassword);
            }
        };
        ProxyContext.set(proxyConfigurator);
    }
}
