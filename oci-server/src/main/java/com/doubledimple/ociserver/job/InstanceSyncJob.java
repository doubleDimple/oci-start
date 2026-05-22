package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.service.TenantService;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

/**
 * 实例同步任务Job
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class InstanceSyncJob implements Job {

    @Resource
    private TenantService tenantService;

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        /*log.info("开始执行实例批量同步任务.....");
        try {
            tenantService.globalSyncOci();
            log.info("执行实例批量同步任务 SUCCESS");
        } catch (Exception e) {
            log.error("执行实例批量同步任务失败，原因: {}", e.getMessage(), e);
            throw new JobExecutionException(e);
        }*/
    }
}
