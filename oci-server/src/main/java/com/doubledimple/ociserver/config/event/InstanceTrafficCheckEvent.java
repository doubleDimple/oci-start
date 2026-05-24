package com.doubledimple.ociserver.config.event;

import org.springframework.context.ApplicationEvent;

/**
 * 流量统计触发事件
 * 由 Quartz 的 InstanceTrafficJob 发布，真正的重活由异步监听器处理，
 * 避免长耗时任务占用 Quartz 工作线程导致触发被挡掉 / misfire。
 */
public class InstanceTrafficCheckEvent extends ApplicationEvent {
    public InstanceTrafficCheckEvent(Object source) {
        super(source);
    }
}
