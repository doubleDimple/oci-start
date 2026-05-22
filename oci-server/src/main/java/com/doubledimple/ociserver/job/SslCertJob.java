package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.DynamicDailyTask;
import com.doubledimple.ociserver.service.nginx.SslCertificateService;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * 证书续期
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class SslCertJob implements Job {

    private final SslCertificateService sslCertificateService;

    @Autowired
    public SslCertJob(SslCertificateService sslCertificateService) {
        this.sslCertificateService = sslCertificateService;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        try {
            log.debug("开始执行证书续期");
            sslCertificateService.processAutoRenewal();
        } catch (Exception e) {
            log.error("执行证书续期失败，原因: {}", e.getMessage(), e);
        } finally {
            MDC.clear();
        }
    }
}
