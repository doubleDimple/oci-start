package com.doubledimple.ociserver.job;

import com.doubledimple.ocimonitor.service.MonitorCoreService;
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
 * 抢机调度器Job
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class CheckOfflineInstanceJob implements Job {

    private final MonitorCoreService monitorCoreService;

    @Autowired
    public CheckOfflineInstanceJob(MonitorCoreService monitorCoreService) {
        this.monitorCoreService = monitorCoreService;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        try {
            log.debug("Start executing monitor check offLine....");
            monitorCoreService.checkOfflineInstances();
        } catch (Exception e) {
            log.error("Start executing monitor check offLine error: {}", e.getMessage(), e);
        } finally {
            MDC.clear();
        }
    }
}
