package com.doubledimple.ociserver.config;

import com.oracle.bmc.http.ClientConfigurator;

/**
 * @version 1.0.0
 * @ClassName ProxyContext
 * @Description TODO
 * @Author 代理上下文
 * @Date 2025-11-01 12:47
 */
public class ProxyContext {
    private static final ThreadLocal<ClientConfigurator> CONTEXT = new ThreadLocal<>();

    public static void set(ClientConfigurator configurator) {
        CONTEXT.set(configurator);
    }

    public static ClientConfigurator get() {
        return CONTEXT.get();
    }

    public static void clear() {
        CONTEXT.remove();
    }
}
