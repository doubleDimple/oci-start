package com.doubledimple.ociserver.job;

import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 短间隔 Quartz 任务的异步执行器。
 * Quartz 工作线程只需调用 {@link #runOnce} 即可立即返回（方法是 @Async），真正的工作放到
 * 专用线程池 jobExecutor 上执行，因此绝不会阻塞 Quartz 调度线程。
 * 同时按任务名做单飞守卫：上一轮还没结束时，本轮直接跳过，避免在小机器上多轮堆积。
 */
@Slf4j
@Component
public class AsyncJobRunner {

    private final Map<String, AtomicBoolean> locks = new ConcurrentHashMap<>();

    @Async("jobExecutor")
    public void runOnce(String name, Runnable task) {
        AtomicBoolean lock = locks.computeIfAbsent(name, k -> new AtomicBoolean(false));
        if (!lock.compareAndSet(false, true)) {
            log.warn("[{}] 上一轮尚未结束，跳过本轮", name);
            return;
        }
        MDC.put("traceId", UUID.randomUUID().toString().replace("-", ""));
        long start = System.currentTimeMillis();
        try {
            task.run();
        } catch (Exception e) {
            log.error("[{}] 执行失败: {}", name, e.getMessage(), e);
        } finally {
            lock.set(false);
            log.debug("[{}] 本轮结束，耗时 {} ms", name, System.currentTimeMillis() - start);
            MDC.clear();
        }
    }
}
