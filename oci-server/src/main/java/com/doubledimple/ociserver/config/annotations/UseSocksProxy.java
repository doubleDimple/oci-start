package com.doubledimple.ociserver.config.annotations;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface UseSocksProxy {

    /**
     * 代理标识（可选，比如从数据库根据 key 获取）
     */
    String value() default "";
}
