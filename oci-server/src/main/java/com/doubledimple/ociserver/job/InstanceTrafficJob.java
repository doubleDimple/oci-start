package com.doubledimple.ociserver.job;

import com.doubledimple.ociserver.config.event.InstanceTrafficCheckEvent;
import lombok.extern.slf4j.Slf4j;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

/**
 * 实例流量统计任务Job
 * 只负责发布事件后立即返回，真正的统计在异步监听器里执行，
 * 避免长耗时占用 Quartz 工作线程导致触发被挡掉 / misfire（小机器上尤为明显）。
 */
@Slf4j
@Component
public class InstanceTrafficJob implements Job {

    @Resource
    private ApplicationEventPublisher eventPublisher;

    @Override
    public void execute(JobExecutionContext context) {
        log.debug("触发流量统计任务，发布异步事件...");
        eventPublisher.publishEvent(new InstanceTrafficCheckEvent(this));
    }
}
