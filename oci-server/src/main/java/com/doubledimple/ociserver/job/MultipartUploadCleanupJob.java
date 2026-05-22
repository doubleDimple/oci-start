package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.MultipartUploadCleanupTask;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * 分片上传孤儿清理 Quartz Job
 * 每天凌晨 2 点执行，清理超过 24 小时未完成的分片上传
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class MultipartUploadCleanupJob implements Job {

    private final MultipartUploadCleanupTask cleanupTask;

    @Autowired
    public MultipartUploadCleanupJob(MultipartUploadCleanupTask cleanupTask) {
        this.cleanupTask = cleanupTask;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        try {
            log.info("开始执行分片上传清理任务...");
            cleanupTask.cleanStaleUploads();
        } catch (Exception e) {
            log.error("分片上传清理任务执行失败: {}", e.getMessage(), e);
        }
    }
}
