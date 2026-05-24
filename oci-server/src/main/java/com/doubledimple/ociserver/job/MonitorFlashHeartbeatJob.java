package com.doubledimple.ociserver.job;

import com.doubledimple.ocimonitor.service.MonitorCoreService;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * 探针心跳刷库Job
 * 派发到异步线程池执行，不阻塞 Quartz 线程；上一轮未结束则跳过本轮。
 */
@Component
@DisallowConcurrentExecution
public class MonitorFlashHeartbeatJob implements Job {

    private final MonitorCoreService monitorCoreService;
    private final AsyncJobRunner asyncJobRunner;

    @Autowired
    public MonitorFlashHeartbeatJob(MonitorCoreService monitorCoreService, AsyncJobRunner asyncJobRunner) {
        this.monitorCoreService = monitorCoreService;
        this.asyncJobRunner = asyncJobRunner;
    }

    @Override
    public void execute(JobExecutionContext context) {
        asyncJobRunner.runOnce("monitor-heartbeat", monitorCoreService::flushHeartbeatToDB);
    }
}
