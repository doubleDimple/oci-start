package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;

/**
 * @version 1.0.0
 * @ClassName RequestContext
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-02 16:02
 */
public class RequestContext {

    private Tenant tenant;

    private SimpleAuthenticationDetailsProvider provider;

    public Tenant getTenant() {
        return tenant;
    }

    public void setTenant(Tenant tenant) {
        this.tenant = tenant;
    }

    public SimpleAuthenticationDetailsProvider getProvider() {
        return provider;
    }

    public void setProvider(SimpleAuthenticationDetailsProvider provider) {
        this.provider = provider;
    }
}
