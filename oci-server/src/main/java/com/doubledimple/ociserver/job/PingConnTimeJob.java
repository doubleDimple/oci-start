package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.task.DynamicDailyTask;
import com.doubledimple.ociserver.config.task.PingConnTimeTask;
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
public class PingConnTimeJob implements Job {

    private final PingConnTimeTask pingConnTimeTask;

    @Autowired
    public PingConnTimeJob(PingConnTimeTask pingConnTimeTask) {
        this.pingConnTimeTask = pingConnTimeTask;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        try {
            log.debug("开始执行ping测试");
            pingConnTimeTask.pingConnTime();
        } catch (Exception e) {
            log.error("执行ping 测试失败: {}", e.getMessage(), e);
        }finally {
            MDC.clear();
        }
    }
}
