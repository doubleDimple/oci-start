package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.IpQualityCheckService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.support.CronTrigger;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.concurrent.ScheduledFuture;

/**
 * @version 1.0.0
 * @ClassName 执行IP质量检测的定时任务
 * @Description IP质量检测定时任务，根据配置的时间间隔定期检测所有实例的IP质量
 */
@Component
@EnableScheduling
@Slf4j
public class DynamicIpCheckTask {

    @Resource
    private TaskScheduler taskScheduler;

    private ScheduledFuture<?> scheduledFuture;

    @Resource
    private SystemConfigRepository systemConfigRepository;

    @Resource
    @Lazy
    private IpQualityCheckService ipQualityCheckService;

    @Resource
    @Lazy
    MessageFactory messageFactory;

    /**
     * 更新IP检测间隔
     * @param interval 检测间隔（小时）
     * @param enabled 是否启用
     */
    public void updateCheckInterval(int interval, boolean enabled) {
        if (interval <= 0 || interval > 24) {
            throw new IllegalArgumentException("检测间隔必须在1-24小时之间");
        }

        // 取消现有的定时任务
        if (scheduledFuture != null) {
            scheduledFuture.cancel(false);
        }

        if (!enabled) {
            log.debug("IP质量检测任务已禁用");
            return;
        }

        // 创建新的定时任务，每隔指定小时数执行一次
        String cronExpression = String.format("0 0 */%d * * ?", interval);
        scheduledFuture = taskScheduler.schedule(
                () -> executeTask(),
                new CronTrigger(cronExpression)
        );

        log.info("IP质量检测任务已更新，将每{}小时执行一次", interval);
    }

    private void executeTask() {
        log.info("执行IP质量检测任务，当前时间：{}", LocalDateTime.now());
        // 执行IP质量检测的业务逻辑
        doIpQualityCheck();
    }

    private void doIpQualityCheck() {
        log.info("开始执行IP质量检测...");
        try {
            // 调用服务执行IP质量检测
            ipQualityCheckService.checkAllInstancesIpQuality();

        } catch (Exception e) {
            log.error("执行IP质量检测任务失败，原因: {}", e.getMessage(), e);
        }
        log.info("执行IP质量检测结束");
    }

    // 系统启动时，根据配置初始化定时任务
    @PostConstruct
    public void init() {
        try {
            // 从配置中获取检测间隔和启用状态
            SystemConfig intervalConfig = systemConfigRepository.findByKey("ipcheck.interval")
                    .orElse(new SystemConfig());
            SystemConfig enabledConfig = systemConfigRepository.findByKey("ipcheck.enabled")
                    .orElse(new SystemConfig());

            int interval = intervalConfig.getValue() != null ?
                    Integer.parseInt(intervalConfig.getValue()) : 6; // 默认6小时
            boolean enabled = enabledConfig.isEnabled();

            // 初始化定时任务
            updateCheckInterval(interval, enabled);
        } catch (Exception e) {
            log.error("初始化IP质量检测任务失败", e);
        }
    }
}
