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

    @ExceptionHandler(com.doubledimple.ociserver.service.permissions.OciPermissionDeniedException.class)
    @ResponseBody
    public org.springframework.http.ResponseEntity<com.doubledimple.ocicommon.param.ApiResponse> handleOciPermissionDenied(
            com.doubledimple.ociserver.service.permissions.OciPermissionDeniedException e) {
        return org.springframework.http.ResponseEntity.status(403)
                .body(com.doubledimple.ocicommon.param.ApiResponse.error(e.getMessage()));
    }

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
                response.getWriter().write("{\"success\":false,\"code\":403,\"message\":\"IP 已被封禁，请联系管理员解封\"}");
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
