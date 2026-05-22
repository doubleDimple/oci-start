package com.doubledimple.ociserver.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/**
 * @version 1.0.0
 * @ClassName SchedulingConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-01-03 20:56
 */
@Configuration
@EnableScheduling
public class SchedulingConfig {

    @Bean
    public TaskScheduler taskScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(5);  // 设置线程池大小
        scheduler.setThreadNamePrefix("custom-scheduler-");
        scheduler.setErrorHandler(throwable ->
                System.err.println("定时任务执行异常: " + throwable.getMessage()));
        return scheduler;
    }
}
