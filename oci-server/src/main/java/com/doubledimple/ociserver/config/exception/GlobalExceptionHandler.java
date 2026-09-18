package com.doubledimple.ociserver.config.exception;

import cn.dev33.satoken.exception.NotLoginException;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.http.HttpEntity;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerMapping;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(IpBannedException.class)
    public void handleIpBannedException(IpBannedException e, HttpServletRequest request,
                                        HttpServletResponse response) throws IOException {
        response.setHeader("Cache-Control", "no-store");
        String path = request.getServletPath();
        String accept = request.getHeader("Accept");
        boolean isApi = path != null && (path.startsWith("/api/") || path.startsWith("/m/api/"));
        Object handler = request.getAttribute(HandlerMapping.BEST_MATCHING_HANDLER_ATTRIBUTE);
        if (handler instanceof HandlerMethod) {
            HandlerMethod method = (HandlerMethod) handler;
            isApi = isApi || method.hasMethodAnnotation(ResponseBody.class)
                    || AnnotatedElementUtils.hasAnnotation(method.getBeanType(), ResponseBody.class)
                    || HttpEntity.class.isAssignableFrom(method.getReturnType().getParameterType());
        }
        boolean isAjax = "XMLHttpRequest".equals(request.getHeader("X-Requested-With"))
                || (accept != null && accept.contains("application/json"));
        if (isApi || isAjax) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json;charset=UTF-8");
            if (!"HEAD".equalsIgnoreCase(request.getMethod())) {
                response.getWriter().write("{\"code\":403,\"message\":\"访问被拒绝\"}");
            }
        } else {
            response.sendRedirect(request.getContextPath() + "/forbidden");
        }
    }

    @ExceptionHandler(NotLoginException.class)
    public void handleNotLoginException(NotLoginException e, HttpServletRequest request,
                                        javax.servlet.http.HttpServletResponse response) throws Exception {
        String xRequestedWith = request.getHeader("X-Requested-With");
        String accept = request.getHeader("Accept");
        boolean isAjax = "XMLHttpRequest".equals(xRequestedWith)
                || (accept != null && accept.contains("application/json"));
        if (isAjax) {
            response.setStatus(401);
            response.setContentType("application/json;charset=utf-8");
            response.getWriter().write("{\"code\":401,\"message\":\"未登录或登录已过期\"}");
        } else {
            response.sendRedirect("/login");
        }
    }
}
