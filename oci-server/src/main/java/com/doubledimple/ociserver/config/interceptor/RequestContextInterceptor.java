package com.doubledimple.ociserver.config.interceptor;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.config.context.RequestContextHolder;
import com.doubledimple.ociserver.pojo.request.RequestContext;
import com.doubledimple.ociserver.service.TenantService;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.annotation.Resource;
import javax.servlet.DispatcherType;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import java.util.ArrayList;
import java.util.List;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

@Component
@Slf4j
public class RequestContextInterceptor implements HandlerInterceptor {

    private static final List<String> IGNORE_PATHS = new ArrayList<>();
    static {
        IGNORE_PATHS.add("/tenants/save");
    }
    @Resource
    private TenantService tenantService;

    private static final String TENANT_HEADER = "X-Tenant-Id";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {

        String path = request.getRequestURI();
        String method = request.getMethod();
        if (IGNORE_PATHS.contains(path)){
            return true;
        }

        if (DispatcherType.ASYNC.equals(request.getDispatcherType())) {
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

        Tenant tenant = tenantService.getById(Long.valueOf(tenantIdStr));

        RequestContext context = new RequestContext();
        context.setTenant(tenant);

        /*if (tenant.getCloudType() == CloudTypeEnum.ORACLE_CLOUD.getType()) {
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            context.setProvider(provider);
        }*/

        RequestContextHolder.set(context);

        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        RequestContextHolder.clear();
        // 释放线程池线程上的代理 ThreadLocal，避免串请求
        TenantProxyBinder.clear();
    }
}
