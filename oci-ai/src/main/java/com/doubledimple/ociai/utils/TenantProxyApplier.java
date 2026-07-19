package com.doubledimple.ociai.utils;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.http.ClientConfigurator;

/**
 * 由 oci-server 注入实现：绑定租户代理并返回 OCI {@link ClientConfigurator}。
 * 未注入时 AI 客户端直连。
 */
@FunctionalInterface
public interface TenantProxyApplier {

    /**
     * 按租户绑定代理，返回当前线程上的 ClientConfigurator；无代理时返回 null。
     */
    ClientConfigurator apply(Tenant tenant);
}
