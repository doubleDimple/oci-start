package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.PingConnTimeTask;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * VPS Ping 探测Job
 * 派发到异步线程池执行，不阻塞 Quartz 线程；上一轮未结束则跳过本轮。
 */
@Component
@DisallowConcurrentExecution
public class PingConnTimeJob implements Job {

    private final PingConnTimeTask pingConnTimeTask;
    private final AsyncJobRunner asyncJobRunner;

    @Autowired
    public PingConnTimeJob(PingConnTimeTask pingConnTimeTask, AsyncJobRunner asyncJobRunner) {
        this.pingConnTimeTask = pingConnTimeTask;
        this.asyncJobRunner = asyncJobRunner;
    }

    @Override
    public void execute(JobExecutionContext context) {
        asyncJobRunner.runOnce("ping-conn-time", pingConnTimeTask::pingConnTime);
    }
}
