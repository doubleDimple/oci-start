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
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.function.Supplier;

/**
 * 按「账号树」绑定 SOCKS/HTTP 代理到当前线程 {@link ProxyContext}。
 * <p>
 * <b>绑定策略（只绑父租户即可）</b>：
 * <ul>
 *   <li>配置时：{@code vpn_proxy_record.tenant_id} 只存父租户主键</li>
 *   <li>运行时：无论传入父/子租户 id，都沿 {@code parenId} 向上解析，再查父租户代理</li>
 *   <li>子租户自动继承父账号代理，无需给每个区域复制一条绑定</li>
 * </ul>
 */
@Slf4j
@Component
public class TenantProxyBinder {

    private static final int STATUS_AVAILABLE = 1;
    private static final String KEY_GLOBAL = "GLOBAL";
    /** 防止异常数据形成环 */
    private static final int MAX_PARENT_WALK = 8;

    /**
     * 当前线程已 apply 过的 key，避免同一次请求内重复探测。
     */
    private static final ThreadLocal<String> APPLIED_KEY = new ThreadLocal<>();

    @Resource
    private VpnProxyRecordRepository vpnProxyRecordRepository;

    @Resource
    private TenantRepository tenantRepository;

    private static TenantProxyBinder resolve() {
        ApplicationContext ctx = SpringAppContext.get();
        if (ctx == null) {
            return null;
        }
        try {
            return ctx.getBean(TenantProxyBinder.class);
        } catch (Exception e) {
            log.warn("获取 TenantProxyBinder Bean 失败: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 按租户实体绑定。子租户会沿 parenId 继承父租户代理。
     */
    public static void applyForTenant(Tenant tenant) {
        TenantProxyBinder binder = resolve();
        if (binder == null) {
            log.warn("TenantProxyBinder 未就绪，跳过代理绑定（SpringAppContext 未 set 或 Bean 不存在）");
            return;
        }
        if (tenant == null) {
            binder.doApply(null);
            return;
        }
        // 实体上已有 parenId 时，可少一次「是否为子」的误判（仍会再走完整向上解析）
        binder.doApply(tenant.getId());
    }

    /**
     * 按租户主键绑定。子区域 id 会解析到父账号再取代理。
     */
    public static void applyForTenantId(Long tenantPk) {
        TenantProxyBinder binder = resolve();
        if (binder == null) {
            log.warn("TenantProxyBinder 未就绪，跳过代理绑定 tenantPk={}", tenantPk);
            return;
        }
        binder.doApply(tenantPk);
    }

    public static void clear() {
        ProxyContext.clear();
        APPLIED_KEY.remove();
    }

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

    void doApply(Long tenantPk) {
        // 绑定查找用：沿树向上找「专属代理」；去重 key 用根父租户
        Long rootParentId = resolveRootParentId(tenantPk);
        String key = rootParentId == null ? KEY_GLOBAL : String.valueOf(rootParentId);

        if (key.equals(APPLIED_KEY.get())) {
            log.debug("代理已绑定过 rootParentId={}，跳过重复 apply", rootParentId);
            return;
        }

        ProxyContext.clear();

        VpnProxyRecord proxyConfig = selectProxyAlongHierarchy(tenantPk);
        if (proxyConfig == null) {
            log.debug("无可用代理，直连 tenantPk={} rootParentId={}", tenantPk, rootParentId);
            APPLIED_KEY.set(key);
            return;
        }

        boolean force = isForceProxy(proxyConfig);

        // ── 强制代理：发起 OCI 请求前必须实时探测；失败直接报错，绝不直连、不发 OCI ──
        if (force) {
            boolean ok;
            try {
                ok = SocksProxyUtils.isProxyAvailable(proxyConfig);
            } catch (Exception e) {
                ProxyContext.clear();
                APPLIED_KEY.remove();
                markUnavailableQuietly(proxyConfig);
                throw forceProxyDenied(proxyConfig, "连通探测异常: " + e.getMessage());
            }
            if (!ok) {
                ProxyContext.clear();
                APPLIED_KEY.remove();
                markUnavailableQuietly(proxyConfig);
                throw forceProxyDenied(proxyConfig, "连通探测失败，已阻止向 OCI 发起请求");
            }
            try {
                applyProxy(proxyConfig);
            } catch (Exception e) {
                ProxyContext.clear();
                APPLIED_KEY.remove();
                throw forceProxyDenied(proxyConfig, "代理绑定失败: " + e.getMessage());
            }
            APPLIED_KEY.set(key);
            log.info("强制代理已绑定 {}:{} [{}] tenantPk={} rootParentId={}",
                    proxyConfig.getProxyHost(),
                    proxyConfig.getProxyPort(),
                    proxyConfig.getProxyType(),
                    tenantPk,
                    rootParentId);
            return;
        }

        // ── 非强制：探测失败可降级直连 ──
        if (proxyConfig.getAvailableStatus() == null || proxyConfig.getAvailableStatus() != STATUS_AVAILABLE) {
            log.debug("代理已禁用，直连 {}:{}", proxyConfig.getProxyHost(), proxyConfig.getProxyPort());
            APPLIED_KEY.set(key);
            return;
        }
        try {
            if (!SocksProxyUtils.isProxyAvailable(proxyConfig)) {
                log.warn("代理探测不可用，跳过 {}:{}", proxyConfig.getProxyHost(), proxyConfig.getProxyPort());
                APPLIED_KEY.set(key);
                return;
            }
            applyProxy(proxyConfig);
            APPLIED_KEY.set(key);
            log.info("已绑定代理 {}:{} [{}] force=false tenantPk={} rootParentId={} bindTenantId={}",
                    proxyConfig.getProxyHost(),
                    proxyConfig.getProxyPort(),
                    proxyConfig.getProxyType(),
                    tenantPk,
                    rootParentId,
                    proxyConfig.getTenantId());
        } catch (Exception e) {
            log.warn("绑定代理失败 tenantPk={}: {}", tenantPk, e.getMessage());
            ProxyContext.clear();
            APPLIED_KEY.remove();
        }
    }

    /**
     * 强制探测失败时，尽量把 availableStatus 落库为 0（失败不影响主流程抛错）。
     */
    private void markUnavailableQuietly(VpnProxyRecord proxyConfig) {
        if (proxyConfig == null || proxyConfig.getId() == null) {
            return;
        }
        try {
            if (proxyConfig.getAvailableStatus() != null && proxyConfig.getAvailableStatus() == 0) {
                return;
            }
            proxyConfig.setAvailableStatus(0);
            vpnProxyRecordRepository.save(proxyConfig);
        } catch (Exception e) {
            log.debug("回写代理不可用状态失败 id={}: {}", proxyConfig.getId(), e.getMessage());
        }
    }

    /**
     * 从当前租户 id 开始，沿 parenId 向上查找专属代理；都没有再走全局池。
     * 这样：只配置父租户绑定，所有子区域自动继承。
     * <p>
     * 强制代理即使当前不可用也要返回，以便上层拒绝请求；非强制不可用则继续向上/全局查找。
     */
    private VpnProxyRecord selectProxyAlongHierarchy(Long tenantPk) {
        Long current = tenantPk;
        int guard = 0;
        while (current != null && guard < MAX_PARENT_WALK) {
            guard++;
            VpnProxyRecord bound = vpnProxyRecordRepository.findTopByTenantId(current);
            if (bound != null) {
                if (isForceProxy(bound) || isAvailable(bound)) {
                    if (guard > 1) {
                        log.debug("子租户 {} 继承祖先 {} 的专属代理 force={}",
                                tenantPk, current, isForceProxy(bound));
                    }
                    return bound;
                }
                // 非强制且不可用：继续向上找
            }
            Tenant t = tenantRepository.findById(current).orElse(null);
            if (t == null) {
                break;
            }
            Long parenId = t.getParenId();
            if (parenId == null || parenId == 0L || parenId.equals(current)) {
                break;
            }
            current = parenId;
        }
        // 全局强制代理优先（即使不可用也要返回以触发拒绝）
        VpnProxyRecord forceGlobal = vpnProxyRecordRepository.findForceGlobal();
        if (forceGlobal != null) {
            return forceGlobal;
        }
        return vpnProxyRecordRepository.findRandomAvailableGlobal(STATUS_AVAILABLE);
    }

    private static boolean isForceProxy(VpnProxyRecord proxy) {
        return proxy != null && proxy.getForceProxy() != null && proxy.getForceProxy() == 1;
    }

    private static boolean isAvailable(VpnProxyRecord proxy) {
        return proxy != null && proxy.getAvailableStatus() != null
                && proxy.getAvailableStatus() == STATUS_AVAILABLE;
    }

    private static IllegalStateException forceProxyDenied(VpnProxyRecord proxy, String reason) {
        String host = proxy != null ? proxy.getProxyHost() : "?";
        Integer port = proxy != null ? proxy.getProxyPort() : null;
        String msg = "强制代理模式下拒绝请求: " + host + ":" + port + " — " + reason;
        log.error(msg);
        return new IllegalStateException(msg);
    }

    /**
     * 解析账号树根（parenId 为空或 0 的节点），用于去重 key。
     */
    private Long resolveRootParentId(Long tenantPk) {
        if (tenantPk == null) {
            return null;
        }
        Long current = tenantPk;
        int guard = 0;
        try {
            while (current != null && guard < MAX_PARENT_WALK) {
                guard++;
                Tenant t = tenantRepository.findById(current).orElse(null);
                if (t == null) {
                    return current;
                }
                Long parenId = t.getParenId();
                if (parenId == null || parenId == 0L || parenId.equals(current)) {
                    return t.getId();
                }
                current = parenId;
            }
            return current;
        } catch (Exception e) {
            log.debug("解析根父租户失败 tenantPk={}: {}", tenantPk, e.getMessage());
            return tenantPk;
        }
    }

    private void applyProxy(VpnProxyRecord proxyConfig) throws URISyntaxException {
        String host = proxyConfig.getProxyHost();
        int port = proxyConfig.getProxyPort();
        String proxyUsername = proxyConfig.getProxyUsername();
        String proxyPassword = proxyConfig.getProxyPassword();
        String proxyType = proxyConfig.getProxyType() == null
                ? "http"
                : proxyConfig.getProxyType().toLowerCase();
        URI proxyUri = new URI(proxyType, null, host, port, null, null, null);
        String url = proxyUri.toString();
        ClientConfigurator proxyConfigurator = clientBuilder -> {
            clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_URI), url);
            if (proxyUsername != null && proxyPassword != null
                    && !proxyUsername.isEmpty() && !proxyPassword.isEmpty()) {
                clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_USERNAME), proxyUsername);
                clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_PASSWORD), proxyPassword);
            }
        };
        ProxyContext.set(proxyConfigurator);
    }
}
