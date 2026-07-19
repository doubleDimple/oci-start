package com.doubledimple.ociserver.config;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.utils.TenantProxyApplier;
import com.oracle.bmc.http.ClientConfigurator;
import org.springframework.stereotype.Component;

/**
 * 把 server 侧代理（TenantProxyBinder + ProxyContext）直接注入给 oci-ai。
 */
@Component
public class OciAiTenantProxyApplier implements TenantProxyApplier {

    @Override
    public ClientConfigurator apply(Tenant tenant) {
        TenantProxyBinder.applyForTenant(tenant);
        return ProxyContext.get();
    }
}
