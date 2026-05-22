package com.doubledimple.ociserver.third.openApi.annotation;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * API Token验证注解
 * 用于标记需要Token验证的接口方法
 */
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
public @interface RequireApiToken {

    /**
     * 是否允许Swagger访问
     * true: 需要验证Token的allowSwaggerAccess权限
     * false: 只验证Token有效性，不检查Swagger权限
     */
    boolean requireSwaggerAccess() default false;

    /**
     * 错误消息
     */
    String message() default "API Token验证失败";
}
