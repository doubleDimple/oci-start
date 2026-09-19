package com.doubledimple.ociserver.config.annotations;

import cn.dev33.satoken.stp.StpUtil;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.config.context.UserContext;
import com.doubledimple.ociserver.service.AuditLogService;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Pointcut;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.core.annotation.AnnotationUtils;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.validation.BindingResult;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpSession;
import java.lang.reflect.Method;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.regex.Pattern;

/**
 * 访问与操作审计日志切面
 *
 * @author doubleDimple
 */
@Aspect
@Component
@Slf4j
public class AuditLogAspect {

    private static final Pattern SENSITIVE_KEY_PATTERN = Pattern.compile(
            "(?i)(password|passwd|pwd|secret|token|apikey|privatekey|credential|authorization)"
    );

    @Resource
    private AuditLogService auditLogService;

    @Resource(name = "taskExecutor")
    private ThreadPoolExecutor taskExecutor;

    @Pointcut("@annotation(com.doubledimple.ociserver.config.annotations.AuditLog) || " +
            "@within(com.doubledimple.ociserver.config.annotations.AuditLog) || " +
            "within(com.doubledimple.ociserver.controller.BaseController+)")
    public void auditLogPointcut() {
    }

    @Around("auditLogPointcut()")
    public Object doAround(ProceedingJoinPoint joinPoint) throws Throwable {
        ServletRequestAttributes attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        if (attributes == null) {
            return joinPoint.proceed();
        }

        HttpServletRequest request = attributes.getRequest();
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();

        // 获取 @AuditLog 注解（方法级优先于类级）
        AuditLog auditLogAnnotation = AnnotationUtils.findAnnotation(method, AuditLog.class);
        if (auditLogAnnotation == null) {
            auditLogAnnotation = AnnotationUtils.findAnnotation(joinPoint.getTarget().getClass(), AuditLog.class);
        }

        // 若明确标记 ignore，则不进行审计拦截
        if (auditLogAnnotation != null && auditLogAnnotation.ignore()) {
            return joinPoint.proceed();
        }

        String requestUri = request.getRequestURI();
        // 避免查询审计日志本身时引发死循环记录
        if (requestUri != null && requestUri.startsWith("/api/audit-logs") && "GET".equalsIgnoreCase(request.getMethod())) {
            return joinPoint.proceed();
        }

        long startTime = System.currentTimeMillis();
        Object result = null;
        Throwable error = null;

        try {
            result = joinPoint.proceed();
            return result;
        } catch (Throwable t) {
            error = t;
            throw t;
        } finally {
            long costTime = System.currentTimeMillis() - startTime;
            handleAuditRecord(joinPoint, auditLogAnnotation, request, result, error, costTime);
        }
    }

    private void handleAuditRecord(ProceedingJoinPoint joinPoint, AuditLog annotation,
                                  HttpServletRequest request, Object result, Throwable error, long costTime) {
        try {
            MethodSignature signature = (MethodSignature) joinPoint.getSignature();
            String uri = request.getRequestURI();

            // 1. 操作人提取
            String username = UserContext.getUsername();
            if (!StringUtils.hasText(username)) {
                try {
                    if (StpUtil.isLogin()) {
                        username = StpUtil.getLoginIdAsString();
                    }
                } catch (Exception ignored) {
                }
            }
            if (!StringUtils.hasText(username) || "anonymous".equalsIgnoreCase(username)) {
                String reqUsername = request.getParameter("username");
                if (StringUtils.hasText(reqUsername)) {
                    username = reqUsername;
                }
            }
            if (!StringUtils.hasText(username)) {
                username = "anonymous";
            }

            // 2. 标题 / 模块描述
            String title = "";
            AuditLog methodAnnotation = AnnotationUtils.findAnnotation(signature.getMethod(), AuditLog.class);
            AuditLog classAnnotation = AnnotationUtils.findAnnotation(joinPoint.getTarget().getClass(), AuditLog.class);

            String classTitle = (classAnnotation != null && StringUtils.hasText(classAnnotation.title())) ? classAnnotation.title() : "";
            String methodTitle = (methodAnnotation != null && StringUtils.hasText(methodAnnotation.title())) ? methodAnnotation.title() : "";

            if (!StringUtils.hasText(methodTitle)) {
                try {
                    io.swagger.v3.oas.annotations.Operation op = AnnotationUtils.findAnnotation(signature.getMethod(), io.swagger.v3.oas.annotations.Operation.class);
                    if (op != null && StringUtils.hasText(op.summary())) {
                        methodTitle = op.summary();
                    }
                } catch (Throwable ignored) {
                }
            }

            if (StringUtils.hasText(classTitle) && StringUtils.hasText(methodTitle)) {
                title = classTitle + " - " + methodTitle;
            } else if (StringUtils.hasText(classTitle)) {
                title = classTitle;
            } else if (StringUtils.hasText(methodTitle)) {
                title = methodTitle;
            } else {
                title = uri;
            }

            // 3. 请求信息提取
            String httpMethod = request.getMethod();
            String actionMethod = joinPoint.getTarget().getClass().getSimpleName() + "." + signature.getName();
            String clientIp = IpUtils.getClientIpAddress(request);
            String userAgent = request.getHeader("User-Agent");
            if (userAgent != null && userAgent.length() > 500) {
                userAgent = userAgent.substring(0, 497) + "...";
            }

            // 4. IP 归属地判定 (内网/外网)
            String location = resolveIpLocation(clientIp);

            // 5. 请求参数提取与脱敏
            String params = "";
            boolean saveParams = annotation == null || annotation.saveParams();
            if (saveParams) {
                params = extractSafeParams(request, joinPoint);
            }

            // 6. 状态判定
            int status = (error == null) ? 1 : 0;
            String errorMsg = null;
            if (error != null) {
                errorMsg = error.getMessage();
                if (!StringUtils.hasText(errorMsg)) {
                    errorMsg = error.getClass().getSimpleName();
                }
                if (errorMsg.length() > 1000) {
                    errorMsg = errorMsg.substring(0, 997) + "...";
                }
            }

            // 7. 构建 AuditLog 实体
            com.doubledimple.dao.entity.AuditLog auditLog = new com.doubledimple.dao.entity.AuditLog();
            auditLog.setUsername(username);
            auditLog.setTitle(title);
            auditLog.setMethod(httpMethod);
            auditLog.setRequestUri(uri);
            auditLog.setActionMethod(actionMethod);
            auditLog.setIp(clientIp);
            auditLog.setLocation(location);
            auditLog.setParams(params);
            auditLog.setResponseStatus(error == null ? 200 : 500);
            auditLog.setStatus(status);
            auditLog.setErrorMsg(errorMsg);
            auditLog.setCostTime(costTime);
            auditLog.setUserAgent(userAgent);
            auditLog.setCreateTime(LocalDateTime.now());

            // 8. 异步写入数据库，不阻碍主线程业务
            if (taskExecutor != null) {
                taskExecutor.execute(() -> auditLogService.saveAuditLog(auditLog));
            } else {
                auditLogService.saveAuditLog(auditLog);
            }
        } catch (Exception e) {
            log.warn("构建审计日志异常: {}", e.getMessage());
        }
    }

    private String resolveIpLocation(String ip) {
        if (!StringUtils.hasText(ip) || "unknown".equalsIgnoreCase(ip)) {
            return "未知";
        }
        if ("127.0.0.1".equals(ip) || "0:0:0:0:0:0:0:1".equals(ip) || ip.startsWith("192.168.") || ip.startsWith("10.") || ip.startsWith("172.")) {
            return "本地局域网 / 内网";
        }
        return "公网访问";
    }

    private String extractSafeParams(HttpServletRequest request, ProceedingJoinPoint joinPoint) {
        try {
            Map<String, Object> paramMap = new LinkedHashMap<>();

            // URL query 参数
            String queryString = request.getQueryString();
            if (StringUtils.hasText(queryString)) {
                paramMap.put("_query", queryString);
            }

            // 方法入参提取
            Object[] args = joinPoint.getArgs();
            MethodSignature signature = (MethodSignature) joinPoint.getSignature();
            String[] paramNames = signature.getParameterNames();

            if (args != null && paramNames != null) {
                for (int i = 0; i < args.length; i++) {
                    Object arg = args[i];
                    if (arg == null) continue;
                    if (arg instanceof ServletRequest || arg instanceof ServletResponse ||
                            arg instanceof HttpSession || arg instanceof MultipartFile ||
                            arg instanceof BindingResult) {
                        continue;
                    }
                    String paramName = (i < paramNames.length) ? paramNames[i] : ("arg" + i);
                    if (SENSITIVE_KEY_PATTERN.matcher(paramName).find()) {
                        paramMap.put(paramName, "******");
                    } else {
                        paramMap.put(paramName, arg);
                    }
                }
            }

            if (paramMap.isEmpty()) {
                return "";
            }

            String json = JSON.toJSONString(paramMap);
            if (json.length() > 2000) {
                json = json.substring(0, 1997) + "...";
            }
            return json;
        } catch (Exception e) {
            return "";
        }
    }
}
