package com.doubledimple.ociserver.config;

import org.springframework.context.ApplicationContext;
import org.springframework.context.ApplicationContextAware;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;

/**
 * 全局 Spring 上下文：启动时由 main 显式 set，并实现 Aware 双保险。
 * 供静态工具（OciUtils 等）取 Bean，避免 static INSTANCE 时序问题。
 */
@Component
public class SpringAppContext implements ApplicationContextAware {

    private static volatile ApplicationContext CONTEXT;

    /**
     * 应用启动后立即调用（main 里 SpringApplication.run 返回后）。
     */
    public static void set(ApplicationContext context) {
        if (context != null) {
            CONTEXT = context;
        }
    }

    @Nullable
    public static ApplicationContext get() {
        return CONTEXT;
    }

    public static boolean isReady() {
        return CONTEXT != null;
    }

    public static <T> T getBean(Class<T> type) {
        ApplicationContext ctx = CONTEXT;
        if (ctx == null) {
            throw new IllegalStateException("Spring ApplicationContext 尚未就绪");
        }
        return ctx.getBean(type);
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) {
        set(applicationContext);
    }
}
