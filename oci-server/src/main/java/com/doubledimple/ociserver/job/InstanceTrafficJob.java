package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.InstanceTrafficTask;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.util.UUID;

/**
 * 实例流量统计任务Job
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class InstanceTrafficJob implements Job {

    @Resource
    private InstanceTrafficTask instanceTrafficTask;


    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        log.debug("开始执行流量统计任务.....");
        try {
            instanceTrafficTask.updateInstanceTraffic();
        } catch (Exception e) {
            log.error("执行流量统计任务失败，原因: {}", e.getMessage(), e);
            throw new JobExecutionException(e);
        }finally {
            MDC.clear();
        }
    }
}
