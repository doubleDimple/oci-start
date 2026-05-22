package com.doubledimple.ociserver.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.DefaultRedirectStrategy;
import org.springframework.security.web.RedirectStrategy;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.security.web.authentication.SavedRequestAwareAuthenticationSuccessHandler;
import org.springframework.security.web.savedrequest.HttpSessionRequestCache;
import org.springframework.security.web.savedrequest.RequestCache;
import org.springframework.security.web.savedrequest.SavedRequest;
import org.springframework.util.StringUtils;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * 登录成功后，根据 User-Agent 跳转到对应端首页。
 * 若存在 saved request（用户访问受保护页面被重定向到登录页），优先跳回原页面。
 */
@Slf4j
public class MobileAwareAuthenticationSuccessHandler implements AuthenticationSuccessHandler {

    private RedirectStrategy redirectStrategy = new DefaultRedirectStrategy();

    @Override
    public void onAuthenticationSuccess(HttpServletRequest request, HttpServletResponse response,
                                        Authentication authentication) throws IOException, ServletException {

        // 1. 判断设备
        boolean isMobile = isMobile(request);
        String targetUrl = isMobile ? "/m/tenants" : "/index";
        String userAgent = request.getHeader("User-Agent");
        if (isMobile) {
            log.info("login device is mobile,User-Agent: [{}]",userAgent);
        }else {
            log.info("login device is pc,User-Agent: [{}]",userAgent);
        }

        String xRequestedWith = request.getHeader("X-Requested-With");
        String accept = request.getHeader("Accept");
        boolean isAjax = "XMLHttpRequest".equals(xRequestedWith) || (accept != null && accept.contains("application/json"));

        if (isAjax) {
            response.setContentType("application/json;charset=utf-8");
            response.getWriter().write("{\"success\":true, \"redirectUrl\":\"" + targetUrl + "\"}");
        } else {
            redirectStrategy.sendRedirect(request, response, targetUrl);
        }
    }

    private boolean isMobile(HttpServletRequest request) {
        String ua = request.getHeader("User-Agent");
        if (ua == null) return false;
        ua = ua.toLowerCase();
        return ua.contains("mobile") || ua.contains("android") || ua.contains("iphone")
                || ua.contains("ipad") || ua.contains("windows phone");
    }
}
