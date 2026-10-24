package com.doubledimple.ociserver.config.interceptor;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.config.context.RequestContextHolder;
import com.doubledimple.ociserver.pojo.request.RequestContext;
import com.doubledimple.ociserver.service.TenantService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.util.UrlPathHelper;

import javax.annotation.Resource;
import javax.servlet.DispatcherType;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

@Component
@Slf4j
public class RequestContextInterceptor implements HandlerInterceptor {

    // Import forms use tenantId for a cloud identity (OCI user OCID / GCP email), not a database ID.
    private static final Set<String> IMPORT_PATHS = new HashSet<>(Arrays.asList(
            "/tenants/save", "/tenants/restricted/save"));
    private static final UrlPathHelper PATH_HELPER = new UrlPathHelper();
    @Resource
    private TenantService tenantService;

    private static final String TENANT_HEADER = "X-Tenant-Id";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws IOException {
        if (DispatcherType.ASYNC.equals(request.getDispatcherType())) {
            return true;
        }

        // This interceptor's afterCompletion is not called if preHandle rejects/throws.
        // Start with clean thread-local state before every ordinary/error dispatch.
        clearContext();
        if (DispatcherType.ERROR.equals(request.getDispatcherType())) {
            // Error dispatches may retain the original multipart parameters.
            return true;
        }

        String path = PATH_HELPER.getPathWithinApplication(request);
        while (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        String method = request.getMethod();
        if ("POST".equalsIgnoreCase(method) && IMPORT_PATHS.contains(path)) {
            // Only skip tenant-context lookup; the normal login checks still apply.
            return true;
        }

        log.debug("当前请求接口: {}  请求方法: {}", path, method);

        String tenantIdStr = request.getHeader(TENANT_HEADER);

        if (tenantIdStr == null || tenantIdStr.trim().isEmpty()) {
            tenantIdStr = request.getParameter("tenantId");
        }

        if (tenantIdStr == null || tenantIdStr.trim().isEmpty()) {
            return true;
        }

        Long tenantId;
        try {
            tenantId = Long.valueOf(tenantIdStr.trim());
        } catch (NumberFormatException e) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.setHeader("Cache-Control", "no-store");
            response.setContentType("application/json;charset=UTF-8");
            if (!"HEAD".equalsIgnoreCase(method)) {
                response.getWriter().write("{\"success\":false,\"code\":400,\"message\":\"租户 ID 无效，请重新选择租户\"}");
            }
            return false;
        }
        Tenant tenant = tenantService.getById(tenantId);

        RequestContext context = new RequestContext();
        context.setTenant(tenant);

        RequestContextHolder.set(context);

        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        clearContext();
    }

    private static void clearContext() {
        RequestContextHolder.clear();
        // 释放线程池线程上的代理 ThreadLocal，避免串请求
        TenantProxyBinder.clear();
    }
}
