package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.VersionCheckTask;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * 抢机调度器Job
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class VersionCheckJob implements Job {

    private final VersionCheckTask versionCheckTask;

    @Autowired
    public VersionCheckJob(VersionCheckTask versionCheckTask) {
        this.versionCheckTask = versionCheckTask;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        try {
            // 这里需要调用内存任务调度器的主要循环方法
            // 注意：需要修改InMemoryTaskScheduler，将主循环逻辑提取为单独方法
            //log.info("开始执行版本检查........");
            //versionCheckTask.checkVersion();
        } catch (Exception e) {
            log.error("执行内存任务调度循环失败，原因: {}", e.getMessage(), e);
        }
    }
}
