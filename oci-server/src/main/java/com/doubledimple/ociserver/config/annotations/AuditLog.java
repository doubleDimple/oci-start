package com.doubledimple.ociserver.config.annotations;

import org.springframework.core.annotation.AliasFor;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 访问与操作审计日志注解
 *
 * 可标记于 Controller 类或具体方法上，记录接口调用、请求参数、耗时及状态
 *
 * @author doubleDimple
 */
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
public @interface AuditLog {

    /**
     * 操作说明或模块名称
     */
    @AliasFor("title")
    String value() default "";

    /**
     * 操作说明或模块名称
     */
    @AliasFor("value")
    String title() default "";

    /**
     * 是否记录请求参数 (敏感字段如密码将自动脱敏)
     */
    boolean saveParams() default true;

    /**
     * 是否记录响应结果
     */
    boolean saveResponse() default false;

    /**
     * 是否忽略此方法或类的审计记录
     */
    boolean ignore() default false;
}
