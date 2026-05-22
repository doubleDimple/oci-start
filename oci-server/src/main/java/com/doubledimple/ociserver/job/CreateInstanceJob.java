package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.CreateInstanceTaskV2;
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
public class CreateInstanceJob implements Job {

    private final CreateInstanceTaskV2 createInstanceTask;

    @Autowired
    public CreateInstanceJob(CreateInstanceTaskV2 createInstanceTask) {
        this.createInstanceTask = createInstanceTask;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        try {
            log.debug("Start executing the instance.....");
            createInstanceTask.checkAndExecuteTasksOnce();
        } catch (Exception e) {
            log.error("执行内存任务调度循环失败，原因: {}", e.getMessage(), e);
        } finally {
            MDC.clear();
        }
    }
}
