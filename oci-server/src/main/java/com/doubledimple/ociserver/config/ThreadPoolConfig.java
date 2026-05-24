package com.doubledimple.ociserver.config;

import com.google.common.util.concurrent.ThreadFactoryBuilder;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import javax.validation.constraints.Max;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.Callable;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Future;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.RejectedExecutionHandler;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;

/**
 * @version 1.0.0
 * @ClassName 线程池配置
 */
@Configuration
@Slf4j
public class ThreadPoolConfig {

    /**
     * 支持 MDC 的 ThreadPoolExecutor 包装类
     */
    private static class MdcThreadPoolExecutor extends ThreadPoolExecutor {

        public MdcThreadPoolExecutor(int corePoolSize, int maximumPoolSize, long keepAliveTime,
                                     TimeUnit unit, BlockingQueue<Runnable> workQueue,
                                     ThreadFactory threadFactory, RejectedExecutionHandler handler) {
            super(corePoolSize, maximumPoolSize, keepAliveTime, unit, workQueue, threadFactory, handler);
        }

        @Override
        public void execute(Runnable command) {
            super.execute(wrap(command));
        }

        @Override
        public Future<?> submit(Runnable task) {
            return super.submit(wrap(task));
        }

        @Override
        public <T> Future<T> submit(Callable<T> task) {
            return super.submit(wrapCallable(task));
        }

        @Override
        public <T> Future<T> submit(Runnable task, T result) {
            return super.submit(wrap(task), result);
        }

        // 包装 Runnable
        private Runnable wrap(Runnable runnable) {
            Map<String, String> contextMap = MDC.getCopyOfContextMap();
            return () -> {
                try {
                    if (contextMap != null) {
                        MDC.setContextMap(contextMap);
                    }
                    runnable.run();
                } finally {
                    MDC.clear();
                }
            };
        }

        // 包装 Callable
        private <T> Callable<T> wrapCallable(Callable<T> callable) {
            Map<String, String> contextMap = MDC.getCopyOfContextMap();
            return () -> {
                try {
                    if (contextMap != null) {
                        MDC.setContextMap(contextMap);
                    }
                    return callable.call();
                } finally {
                    MDC.clear();
                }
            };
        }
    }

    /**
     * 通用任务线程池
     */
    @Bean
    @Primary
    public ThreadPoolExecutor taskExecutor() {
        int cpuCores = Runtime.getRuntime().availableProcessors();
        int corePoolSize = cpuCores * 2;
        int maxPoolSize = corePoolSize * 2;
        int queueCapacity = 500;

        log.debug("通用线程池配置 - CPU核心数:{}, 核心线程数:{}, 最大线程数:{}, 队列容量:{}",
                cpuCores, corePoolSize, maxPoolSize, queueCapacity);

        return new MdcThreadPoolExecutor(
                corePoolSize,
                maxPoolSize,
                60L,
                TimeUnit.SECONDS,
                new LinkedBlockingQueue<>(queueCapacity),
                new ThreadFactoryBuilder()
                        .setNameFormat("task-pool-%d")
                        .setDaemon(true)
                        .build(),
                new ThreadPoolExecutor.CallerRunsPolicy()
        );
    }

    /**
     * 专用于抢机任务的线程池
     */
    @Bean(name = "instanceTaskExecutor")
    public ThreadPoolExecutor instanceTaskExecutor() {
        int cpuCores = Runtime.getRuntime().availableProcessors();
        int corePoolSize = cpuCores * 2;
        int maxPoolSize = corePoolSize * 2;
        int queueCapacity = 500;

        RejectedExecutionHandler handler = (r, executor) -> {
            log.warn("抢机任务线程池已满，当前活动线程: {}, 队列大小: {}, 任务将在调用线程中执行",
                    executor.getActiveCount(),
                    executor.getQueue().size());
            new ThreadPoolExecutor.CallerRunsPolicy().rejectedExecution(r, executor);
        };

        log.debug("抢机任务线程池配置 - 核心线程数:{}, 最大线程数:{}, 队列容量:{}",
                corePoolSize, maxPoolSize, queueCapacity);

        return new MdcThreadPoolExecutor(
                corePoolSize,
                maxPoolSize,
                60L,
                TimeUnit.SECONDS,
                new LinkedBlockingQueue<>(queueCapacity),
                new ThreadFactoryBuilder()
                        .setNameFormat("instance-task-%d")
                        .setDaemon(true)
                        .build(),
                handler
        );
    }

    /**
     * 短间隔定时任务的异步执行线程池（配合 AsyncJobRunner）。
     * 单飞由 AsyncJobRunner 的守卫保证；这里用 DiscardPolicy，线程占满时直接丢弃本次触发，
     * 绝不回灌到 Quartz 调度线程（不要用 CallerRunsPolicy）。
     */
    @Bean(name = "jobExecutor")
    public ThreadPoolTaskExecutor jobExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(3);
        executor.setMaxPoolSize(3);
        executor.setQueueCapacity(2);
        executor.setThreadNamePrefix("job-async-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.DiscardPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(false);
        executor.initialize();
        return executor;
    }

    /**
     * AI聊天专用线程池
     */
    @Bean(name = "aiChatExecutor")
    public ThreadPoolExecutor aiChatExecutor() {
        int corePoolSize = 4;
        int maxPoolSize = 12;
        int queueCapacity = 50;

        RejectedExecutionHandler handler = (r, executor) -> {
            log.warn("AI聊天线程池已满，当前活动线程: {}, 队列大小: {}, 请求将被延迟处理",
                    executor.getActiveCount(),
                    executor.getQueue().size());

            try {
                Thread.sleep(100);
                if (!executor.getQueue().offer(r)) {
                    new ThreadPoolExecutor.CallerRunsPolicy().rejectedExecution(r, executor);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                new ThreadPoolExecutor.CallerRunsPolicy().rejectedExecution(r, executor);
            }
        };

        log.info("AI聊天线程池配置 - 核心线程数:{}, 最大线程数:{}, 队列容量:{}",
                corePoolSize, maxPoolSize, queueCapacity);

        ThreadPoolExecutor executor = new MdcThreadPoolExecutor(
                corePoolSize,
                maxPoolSize,
                300L,
                TimeUnit.SECONDS,
                new LinkedBlockingQueue<>(queueCapacity),
                new ThreadFactoryBuilder()
                        .setNameFormat("ai-chat-%d")
                        .setDaemon(true)
                        .build(),
                handler
        );

        executor.allowCoreThreadTimeOut(true);
        return executor;
    }

    /**
     * 延时任务线程池
     */
    @Bean("delayedTaskExecutor")
    public ScheduledThreadPoolExecutor delayedTaskExecutor() {
        int corePoolSize = Math.max(4, Runtime.getRuntime().availableProcessors());

        RejectedExecutionHandler handler = (r, executor) -> {
            log.warn("延时任务线程池已满，当前活动线程: {}, 队列大小: {}, 任务被拒绝",
                    executor.getActiveCount(),
                    executor.getQueue().size());
            log.warn("延时任务线程池无法接受新任务: {}", r.toString());
        };

        log.debug("延时任务线程池配置 - 核心线程数: {}", corePoolSize);

        // ScheduledThreadPoolExecutor 也需要包装
        ScheduledThreadPoolExecutor executor = new ScheduledThreadPoolExecutor(
                corePoolSize,
                new ThreadFactoryBuilder()
                        .setNameFormat("delayed-task-%d")
                        .setDaemon(true)
                        .build(),
                handler
        ) {
            @Override
            public void execute(Runnable command) {
                super.execute(wrapRunnable(command));
            }

            @Override
            public Future<?> submit(Runnable task) {
                return super.submit(wrapRunnable(task));
            }

            @Override
            public <T> Future<T> submit(Callable<T> task) {
                return super.submit(wrapCallable(task));
            }

            @Override
            public ScheduledFuture<?> schedule(Runnable command, long delay, TimeUnit unit) {
                return super.schedule(wrapRunnable(command), delay, unit);
            }

            @Override
            public <V> ScheduledFuture<V> schedule(Callable<V> callable, long delay, TimeUnit unit) {
                return super.schedule(wrapCallable(callable), delay, unit);
            }

            @Override
            public ScheduledFuture<?> scheduleAtFixedRate(Runnable command, long initialDelay, long period, TimeUnit unit) {
                return super.scheduleAtFixedRate(wrapRunnable(command), initialDelay, period, unit);
            }

            @Override
            public ScheduledFuture<?> scheduleWithFixedDelay(Runnable command, long initialDelay, long delay, TimeUnit unit) {
                return super.scheduleWithFixedDelay(wrapRunnable(command), initialDelay, delay, unit);
            }

            private Runnable wrapRunnable(Runnable runnable) {
                Map<String, String> contextMap = MDC.getCopyOfContextMap();
                return () -> {
                    try {
                        if (contextMap != null) {
                            MDC.setContextMap(contextMap);
                        }
                        runnable.run();
                    } finally {
                        MDC.clear();
                    }
                };
            }

            private <T> Callable<T> wrapCallable(Callable<T> callable) {
                Map<String, String> contextMap = MDC.getCopyOfContextMap();
                return () -> {
                    try {
                        if (contextMap != null) {
                            MDC.setContextMap(contextMap);
                        }
                        return callable.call();
                    } finally {
                        MDC.clear();
                    }
                };
            }
        };

        executor.setKeepAliveTime(120L, TimeUnit.SECONDS);
        executor.allowCoreThreadTimeOut(false);
        executor.setRemoveOnCancelPolicy(true);
        executor.setContinueExistingPeriodicTasksAfterShutdownPolicy(false);
        executor.setExecuteExistingDelayedTasksAfterShutdownPolicy(false);

        return executor;
    }

    /**
     * 监控所有线程池状态
     */
    public void monitorAllThreadPools(ThreadPoolExecutor taskExecutor,
                                      ThreadPoolExecutor instanceTaskExecutor,
                                      ThreadPoolExecutor aiChatExecutor,
                                      ScheduledThreadPoolExecutor delayedTaskExecutor) {
        logPoolStatus("通用线程池", taskExecutor);
        logPoolStatus("抢机任务线程池", instanceTaskExecutor);
        logPoolStatus("AI聊天线程池", aiChatExecutor);
        logScheduledPoolStatus("延时任务线程池", delayedTaskExecutor);
    }

    private void logPoolStatus(String poolName, ThreadPoolExecutor executor) {
        log.info("{} 状态 - 活动线程数: {}/{}, 完成任务数: {}, 任务总数: {}, 队列中等待的任务数: {}",
                poolName,
                executor.getActiveCount(),
                executor.getMaximumPoolSize(),
                executor.getCompletedTaskCount(),
                executor.getTaskCount(),
                executor.getQueue().size());
    }

    private void logScheduledPoolStatus(String poolName, ScheduledThreadPoolExecutor executor) {
        log.info("{} 状态 - 活动线程数: {}/{}, 完成任务数: {}, 任务总数: {}, 队列中等待的任务数: {}",
                poolName,
                executor.getActiveCount(),
                executor.getCorePoolSize(),
                executor.getCompletedTaskCount(),
                executor.getTaskCount(),
                executor.getQueue().size());
    }

    @Bean(name = "eventExecutor")
    public ThreadPoolTaskExecutor eventExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(8);
        executor.setQueueCapacity(200);
        executor.setThreadNamePrefix("event-pool-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.initialize();
        return executor;
    }

    /**
     * 流量统计专用线程池：单线程、几乎不排队、忙时直接丢弃。
     * 保证长耗时的流量任务既不和其它事件抢线程，也不会因触发堆积而多轮并行。
     */
    @Bean(name = "trafficExecutor")
    public ThreadPoolTaskExecutor trafficExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(1);
        executor.setMaxPoolSize(1);
        executor.setQueueCapacity(1);
        executor.setThreadNamePrefix("traffic-pool-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.DiscardPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(false);
        executor.initialize();
        return executor;
    }

    @Bean(name = "ociApiExecutor")
    public ThreadPoolExecutor ociApiExecutor() {
        int cpu = Runtime.getRuntime().availableProcessors();
        return new MdcThreadPoolExecutor(
                Math.max(2, cpu * 4),
                Math.max(8, cpu * 8),
                60L, TimeUnit.SECONDS,
                new LinkedBlockingQueue<>(200),
                new ThreadFactoryBuilder().setNameFormat("oci-api-%d").setDaemon(true).build(),
                new ThreadPoolExecutor.AbortPolicy()
        );
    }

    /**
     * SSE 长连接/阻塞任务专用线程池
     */
    @Bean(name = "sseLogExecutor")
    public ThreadPoolExecutor sseLogExecutor() {
        log.debug("初始化 SSE 长连接专用线程池");

        // 采用类似 CachedThreadPool 的配置，适合处理大量长期阻塞任务
        return new MdcThreadPoolExecutor(
                0,
                200,
                60L,
                TimeUnit.SECONDS,
                new SynchronousQueue<>(),
                new ThreadFactoryBuilder()
                        .setNameFormat("sse-log-%d")
                        .setDaemon(true)
                        .build(),
                new ThreadPoolExecutor.AbortPolicy()
        );
    }
}
