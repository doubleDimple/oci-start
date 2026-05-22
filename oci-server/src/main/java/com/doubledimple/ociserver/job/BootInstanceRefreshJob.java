package com.doubledimple.ociserver.job;

import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.ociserver.config.task.DynamicDailyTask;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.UUID;

/**
 * 抢机调度器Job
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class BootInstanceRefreshJob implements Job {

    private final BootInstanceRepository bootInstanceRepository;

    @Autowired
    public BootInstanceRefreshJob(BootInstanceRepository bootInstanceRepository) {
        this.bootInstanceRepository = bootInstanceRepository;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        try {
            log.debug("Start executing the check live....");
            bootInstanceRepository.resetAllDailyCounts(LocalDate.now());
        } catch (Exception e) {
            log.error("执行账号检测是啊比，原因: {}", e.getMessage(), e);
        } finally {
            MDC.clear();
        }
    }
}
