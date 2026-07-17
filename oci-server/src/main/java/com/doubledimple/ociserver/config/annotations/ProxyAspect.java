package com.doubledimple.ociserver.config.annotations;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.config.context.RequestContextHolder;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.request.AuditLogRequest;
import com.doubledimple.ociserver.pojo.request.RequestContext;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.stereotype.Component;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;

/**
 * {@link UseSocksProxy} 切面：解析方法上的租户参数后交给 {@link TenantProxyBinder}。
 * 静态工具路径不依赖本切面，见 {@code OciUtils.getProvider} 内自动绑定。
 */
@Slf4j
@Aspect
@Component
public class ProxyAspect {

    @Around("@annotation(useSocksProxy)")
    public Object around(ProceedingJoinPoint joinPoint, UseSocksProxy useSocksProxy) throws Throwable {
        Long tenantPk = extractTenantPrimaryKey(joinPoint);
        try {
            TenantProxyBinder.applyForTenantId(tenantPk);
            return joinPoint.proceed();
        } finally {
            TenantProxyBinder.clear();
            log.debug("代理配置已清理");
        }
    }

    private Long extractTenantPrimaryKey(ProceedingJoinPoint joinPoint) {
        RequestContext ctx = RequestContextHolder.get();
        if (ctx != null && ctx.getTenant() != null && ctx.getTenant().getId() != null) {
            return ctx.getTenant().getId();
        }

        Object[] args = joinPoint.getArgs();
        if (args == null || args.length == 0) {
            return null;
        }

        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        Parameter[] parameters = method.getParameters();
        String[] paramNames = signature.getParameterNames();

        for (int i = 0; i < args.length; i++) {
            Object arg = args[i];
            if (arg == null) {
                continue;
            }
            if (arg instanceof Tenant) {
                return ((Tenant) arg).getId();
            }
            if (arg instanceof User) {
                long id = ((User) arg).getId();
                return id > 0 ? id : null;
            }
            if (arg instanceof AuditLogRequest) {
                return parseLong(((AuditLogRequest) arg).getTenantId());
            }
            String name = paramNames != null && i < paramNames.length ? paramNames[i] : null;
            if (name == null && parameters != null && i < parameters.length) {
                name = parameters[i].getName();
            }
            if (name != null && ("tenantId".equalsIgnoreCase(name) || "id".equalsIgnoreCase(name))) {
                Long parsed = toLong(arg);
                if (parsed != null) {
                    return parsed;
                }
            }
        }

        if (args.length == 1) {
            Long only = toLong(args[0]);
            if (only != null) {
                String methodName = method.getName().toLowerCase();
                if (methodName.contains("tenant") || methodName.contains("account") || methodName.contains("audit")) {
                    return only;
                }
            }
        }
        return null;
    }

    private static Long toLong(Object arg) {
        if (arg instanceof Long) {
            return (Long) arg;
        }
        if (arg instanceof Integer) {
            return ((Integer) arg).longValue();
        }
        if (arg instanceof String) {
            return parseLong((String) arg);
        }
        return null;
    }

    private static Long parseLong(String s) {
        if (s == null || s.trim().isEmpty()) {
            return null;
        }
        try {
            return Long.valueOf(s.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
