package com.doubledimple.ociserver.config.context;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.pojo.request.RequestContext;

/**
 * @version 1.0.0
 * @ClassName TenantContextHolder
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-02 15:56
 */
public class RequestContextHolder {

    private static final ThreadLocal<RequestContext> HOLDER = new ThreadLocal<>();

    public static void set(RequestContext context) {
        HOLDER.set(context);
    }

    public static RequestContext get() {
        return HOLDER.get();
    }

    public static void clear() {
        HOLDER.remove();
    }
}
