package com.doubledimple.ociserver.config.annotations;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 检查请求 IP 是否被封禁
 * 可加在类或方法上
 */
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface CheckIpBan {
    /**
     * 自定义错误提示（可选）
     */
    String message() default "您的IP已被封禁，无法访问此接口。";
}
