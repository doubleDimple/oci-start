package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.DynamicDailyTask;
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
public class CheckLiveJob implements Job {

    private final DynamicDailyTask dynamicDailyTask;

    @Autowired
    public CheckLiveJob(DynamicDailyTask dynamicDailyTask) {
        this.dynamicDailyTask = dynamicDailyTask;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        try {
            log.debug("Start executing the check live....");
            dynamicDailyTask.checkAndExecuteTask();
        } catch (Exception e) {
            log.error("执行账号检测是啊比，原因: {}", e.getMessage(), e);
        } finally {
            MDC.clear();
        }
    }
}
