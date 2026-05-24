package com.doubledimple.ociserver.config.event;

import com.doubledimple.ociserver.config.task.InstanceTrafficTask;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 流量统计异步监听器
 * 在专用线程池 trafficExecutor 上执行，并用 running 标志保证同一时刻只有一轮在跑：
 * 上一轮还没结束时，本轮直接跳过（小机器上单轮耗时长属正常），避免重活并行把内存压垮。
 */
@Component
@Slf4j
public class InstanceTrafficCheckEventListener {

    @Resource
    private InstanceTrafficTask instanceTrafficTask;

    private final AtomicBoolean running = new AtomicBoolean(false);

    @Async("trafficExecutor")
    @EventListener
    public void handle(InstanceTrafficCheckEvent event) {
        if (!running.compareAndSet(false, true)) {
            log.warn("[流量预警] 上一轮尚未结束，跳过本轮触发");
            return;
        }
        String traceId = UUID.randomUUID().toString().replace("-", "");
        MDC.put("traceId", traceId);
        long start = System.currentTimeMillis();
        try {
            instanceTrafficTask.updateInstanceTraffic();
        } catch (Exception e) {
            log.error("执行流量统计任务失败，原因: {}", e.getMessage(), e);
        } finally {
            running.set(false);
            log.debug("[流量预警] 本轮结束，耗时 {} ms", System.currentTimeMillis() - start);
            MDC.clear();
        }
    }
}
