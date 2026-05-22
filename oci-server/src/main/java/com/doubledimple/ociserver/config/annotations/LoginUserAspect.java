package com.doubledimple.ociserver.config.annotations;

import com.doubledimple.ociserver.config.context.UserContext;
import org.aspectj.lang.annotation.After;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Before;
import org.aspectj.lang.annotation.Pointcut;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * @version 1.0.0
 * @ClassName LoginUserAspect
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-21 16:54
 */
@Aspect
@Component
public class LoginUserAspect {

    /**
     * 定义切点：
     * 1. @annotation: 匹配方法上有该注解
     * 2. @within: 匹配类上有该注解的所有方法
     */
    @Pointcut("@annotation(com.doubledimple.ociserver.config.annotations.CheckLoginUser) || " +
            "@within(com.doubledimple.ociserver.config.annotations.CheckLoginUser)")
    public void loginCheckPointcut() {
    }

    @Before("loginCheckPointcut()")
    public void doBefore() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null || !authentication.isAuthenticated()) {
            throw new IllegalStateException("用户未登录，请先登录");
        }

        String username = authentication.getName();
        UserContext.setUsername(username);
    }

    @After("loginCheckPointcut()")
    public void doAfter() {
        UserContext.clear();
    }
}
