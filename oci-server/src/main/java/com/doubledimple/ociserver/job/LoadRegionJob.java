package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.LoadRegionTask;
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
 * 区域加载任务Job
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class LoadRegionJob implements Job {

    @Resource
    private LoadRegionTask loadRegionTask;

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        log.info("开始执行区域加载任务.....");
        try {
            //loadRegionTask.loadRegion();
        } catch (Exception e) {
            log.error("执行区域加载任务失败，原因: {}", e.getMessage(), e);
            throw new JobExecutionException(e);
        }finally {
            MDC.clear();
        }
    }
}
