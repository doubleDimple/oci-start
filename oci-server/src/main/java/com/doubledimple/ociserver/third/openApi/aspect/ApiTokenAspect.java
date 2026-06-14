package com.doubledimple.ociserver.third.openApi.aspect;

import com.doubledimple.ociserver.third.openApi.annotation.RequireApiToken;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@Aspect
@Component
@Slf4j
public class ApiTokenAspect {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private ObjectMapper objectMapper;

    @Around("@annotation(requireApiToken)")
    public Object validateApiToken(ProceedingJoinPoint joinPoint, RequireApiToken requireApiToken) throws Throwable {

        ServletRequestAttributes attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        if (attributes == null) {
            return createErrorResponse("无法获取请求上下文", 500);
        }

        HttpServletRequest request = attributes.getRequest();
        HttpServletResponse response = attributes.getResponse();

        try {
            // 提取Token
            String token = extractToken(request);

            if (token == null || token.trim().isEmpty()) {
                log.warn("API调用缺少Token: {}", request.getRequestURI());
                return handleTokenError(response, "缺少API Token", 401);
            }

            // 验证Token
            if (!systemConfigService.validateApiToken(token)) {
                log.warn("无效的API Token访问: IP={}, URI={}", getClientIp(request), request.getRequestURI());
                return handleTokenError(response, "API Token无效或已过期", 401);
            }

            // 如果需要验证Swagger访问权限
            if (requireApiToken.requireSwaggerAccess()) {
                // 这里可以添加额外的Swagger权限检查逻辑
                ApiTokenConfig apiTokenConfig = systemConfigService.getApiTokenConfig();
                if (!apiTokenConfig.isAllowSwaggerAccess()) {
                     return handleTokenError(response, "没有Swagger访问权限", 403);
                 }
            }

            // Token验证通过，记录访问日志
            logApiAccess(request, token);

            // 继续执行原方法
            return joinPoint.proceed();

        } catch (Exception e) {
            log.error("Token验证过程中发生异常", e);
            return handleTokenError(response, "Token验证服务异常", 500);
        }
    }

    /**
     * 处理Token错误
     */
    private Object handleTokenError(HttpServletResponse response, String message, int status) {
        try {
            Map<String, Object> errorResponse = createErrorResponse(message, status);

            response.setStatus(status);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write(objectMapper.writeValueAsString(errorResponse));
            response.getWriter().flush();

            return null; // 直接返回，不执行原方法
        } catch (Exception e) {
            log.error("写入错误响应失败", e);
            return createErrorResponse("服务异常", 500);
        }
    }

    /**
     * 从请求中提取Token
     * curl --location 'localhost:9856/oci-start/open-api/v1/chat' \
     * --header 'Authorization: Bearer oci-start_api_..........' \
     * --header 'Content-Type: application/json' \
     * --header 'Content-Type: application/json' \
     * --data '{
     *     "userId": "123456789",
     *     "message" : "你好"
     * }'
     */
    private String extractToken(HttpServletRequest request) {
        // 1. Authorization Header
        String authHeader = request.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }

        return null;
    }

    /**
     * 记录API访问日志
     */
    private void logApiAccess(HttpServletRequest request, String token) {
        String clientIp = getClientIp(request);
        String userAgent = request.getHeader("User-Agent");
        String uri = request.getRequestURI();
        String method = request.getMethod();

        log.info("API访问成功: method={}, uri={}, ip={}, userAgent={}, tokenPrefix={}",
                method, uri, clientIp, userAgent,
                token.length() > 10 ? token.substring(0, 10) + "..." : token);
    }

    /**
     * 获取客户端IP
     */
    private String getClientIp(HttpServletRequest request) {
        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
            return xForwardedFor.split(",")[0].trim();
        }

        String xRealIp = request.getHeader("X-Real-IP");
        if (xRealIp != null && !xRealIp.isEmpty()) {
            return xRealIp;
        }

        return request.getRemoteAddr();
    }

    /**
     * 创建错误响应
     */
    private Map<String, Object> createErrorResponse(String message, int code) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        response.put("code", code);
        response.put("message", message);
        response.put("timestamp", LocalDateTime.now());
        return response;
    }
}
