package com.doubledimple.ociserver.config.annotations;

import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.reflect.MethodSignature;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.lang.reflect.Method;

import static com.doubledimple.ocicommon.utils.IpUtils.getClientIpAddress;

@Slf4j
@Aspect
@Component
public class IpBanAspect {

    @Resource
    private HttpServletRequest request;


    @Resource
    private BanRecordRepository banRecordRepository;

    @Around("@within(com.doubledimple.ociserver.config.annotations.CheckIpBan) || @annotation(com.doubledimple.ociserver.config.annotations.CheckIpBan)")
    public Object checkIpBan(ProceedingJoinPoint joinPoint) throws Throwable {
        String clientIp = getClientIp(request);

        if (clientIp == null) {
            log.warn("无法获取客户端IP，请求被拒绝。");
            throw new IpBannedException("无法识别IP来源，拒绝访问。");
        }

        BanRecord record = banRecordRepository.findTopByIpAddress(clientIp);
        if (record != null && record.getStatus() == 1) {
            MethodSignature signature = (MethodSignature) joinPoint.getSignature();
            Method method = signature.getMethod();
            CheckIpBan annotation = method.getAnnotation(CheckIpBan.class);
            if (annotation == null) {
                annotation = joinPoint.getTarget().getClass().getAnnotation(CheckIpBan.class);
            }

            String message = annotation != null ? annotation.message() : "您的IP已被封禁";
            log.warn("封禁IP：IP={}", clientIp);
            throw new IpBannedException(message);
        }

        return joinPoint.proceed();
    }

    private String getClientIp(HttpServletRequest request) {
        return getClientIpAddress(request);
    }
}
