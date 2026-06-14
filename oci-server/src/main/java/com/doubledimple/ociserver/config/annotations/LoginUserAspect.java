package com.doubledimple.ociserver.config.annotations;

import cn.dev33.satoken.stp.StpUtil;
import com.doubledimple.ociserver.config.context.UserContext;
import org.aspectj.lang.annotation.After;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Before;
import org.aspectj.lang.annotation.Pointcut;
import org.springframework.stereotype.Component;

@Aspect
@Component
public class LoginUserAspect {

    @Pointcut("@annotation(com.doubledimple.ociserver.config.annotations.CheckLoginUser) || " +
            "@within(com.doubledimple.ociserver.config.annotations.CheckLoginUser)")
    public void loginCheckPointcut() {
    }

    @Before("loginCheckPointcut()")
    public void doBefore() {
        try {
            if (StpUtil.isLogin()) {
                UserContext.setUsername(StpUtil.getLoginIdAsString());
            }
        } catch (Exception ignored) {
        }
    }

    @After("loginCheckPointcut()")
    public void doAfter() {
        UserContext.clear();
    }
}
