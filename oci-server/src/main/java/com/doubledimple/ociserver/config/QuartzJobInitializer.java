package com.doubledimple.ociserver.config;

import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ociserver.job.AiChatHistoryCleanupJob;
import com.doubledimple.ociserver.job.BootInstanceRefreshJob;
import com.doubledimple.ociserver.job.MultipartUploadCleanupJob;
import com.doubledimple.ociserver.job.CheckLiveJob;
import com.doubledimple.ociserver.job.CheckOfflineInstanceJob;
import com.doubledimple.ociserver.job.CreateInstanceJob;
import com.doubledimple.ociserver.job.InstanceSyncJob;
import com.doubledimple.ociserver.job.InstanceTrafficJob;
import com.doubledimple.ociserver.job.LoadRegionJob;
import com.doubledimple.ociserver.job.MonitorFlashHeartbeatJob;
import com.doubledimple.ociserver.job.PingConnTimeJob;
import com.doubledimple.ociserver.job.SslCertJob;
import com.doubledimple.ociserver.job.VersionCheckJob;
import lombok.extern.slf4j.Slf4j;
import org.quartz.CronScheduleBuilder;
import org.quartz.JobBuilder;
import org.quartz.JobDetail;
import org.quartz.JobKey;
import org.quartz.Scheduler;
import org.quartz.SchedulerException;
import org.quartz.Trigger;
import org.quartz.TriggerBuilder;
import org.quartz.TriggerKey;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationListener;
import org.springframework.context.event.ContextRefreshedEvent;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

import static com.doubledimple.ocicommon.constant.TaskService.ACCOUNT_LIVE_CHECK_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.BOOT_INSTANCE_REFRESH_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.CREATE_INSTANCE_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.INSTANCE_SYNC_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.INSTANCE_TRAFFIC_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.LOAD_REGION_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.MONITOR_CHECK_OFFLINE_INSTANCE_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.AI_CHAT_HISTORY_CLEANUP_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.MULTIPART_UPLOAD_CLEANUP_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.MONITOR_FLASH_HEARTBEAT_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.PING_CON_TIME_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.SSL_CERT_TASK;
import static com.doubledimple.ocicommon.constant.TaskService.VERSION_CHECK_TASK;

/**
 * @version 1.0.0
 * @ClassName QuartzJobInitializer
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-15 08:54
 */
@Component
@Slf4j
public class QuartzJobInitializer implements ApplicationListener<ContextRefreshedEvent> {

    @Resource
    private Scheduler scheduler;

    @Resource
    private SystemConfigRepository systemConfigRepository;

    private final InstanceSyncJob instanceSyncJob;
    private final InstanceTrafficJob instanceTrafficJob;
    private final LoadRegionJob loadRegionJob;
    private final CreateInstanceJob createInstanceJob;

    private final PingConnTimeJob pingConnTimeJob;

    private final VersionCheckJob versionCheckJob;

    private final CheckLiveJob checkLiveJob;

    private final SslCertJob sslCertJob;
    private final BootInstanceRefreshJob bootInstanceRefreshJob;

    private final MonitorFlashHeartbeatJob monitorFlashHeartbeatJob;

    private final CheckOfflineInstanceJob checkOfflineInstanceJob;

    private final MultipartUploadCleanupJob multipartUploadCleanupJob;

    private final AiChatHistoryCleanupJob aiChatHistoryCleanupJob;

    @Autowired
    public QuartzJobInitializer(InstanceSyncJob instanceSyncJob,
                                InstanceTrafficJob instanceTrafficJob,
                                LoadRegionJob loadRegionJob,
                                CreateInstanceJob createInstanceJob,
                                VersionCheckJob versionCheckJob,
                                CheckLiveJob checkLiveJob,
                                PingConnTimeJob pingConnTimeJob,
                                SslCertJob sslCertJob,
                                BootInstanceRefreshJob bootInstanceRefreshJob,
                                MonitorFlashHeartbeatJob monitorFlashHeartbeatJob,
                                CheckOfflineInstanceJob checkOfflineInstanceJob,
                                MultipartUploadCleanupJob multipartUploadCleanupJob,
                                AiChatHistoryCleanupJob aiChatHistoryCleanupJob) {
        this.instanceSyncJob = instanceSyncJob;
        this.instanceTrafficJob = instanceTrafficJob;
        this.loadRegionJob = loadRegionJob;
        this.createInstanceJob = createInstanceJob;
        this.versionCheckJob = versionCheckJob;
        this.checkLiveJob = checkLiveJob;
        this.pingConnTimeJob = pingConnTimeJob;
        this.sslCertJob = sslCertJob;
        this.bootInstanceRefreshJob = bootInstanceRefreshJob;
        this.monitorFlashHeartbeatJob = monitorFlashHeartbeatJob;
        this.checkOfflineInstanceJob = checkOfflineInstanceJob;
        this.multipartUploadCleanupJob = multipartUploadCleanupJob;
        this.aiChatHistoryCleanupJob = aiChatHistoryCleanupJob;
    }

    @Override
    public void onApplicationEvent(ContextRefreshedEvent event) {
        if (event.getApplicationContext().getParent() == null) {
            try {
                initJobs();
            } catch (SchedulerException e) {
                log.warn("Failed to initialize jobs{}", e.getMessage());
            }
        }
    }

    private void initJobs() throws SchedulerException {

        // 1. 实例同步任务
        //scheduleJob(scheduler, instanceSyncJob.getClass(), INSTANCE_SYNC_TASK, INSTANCE_SYNC_TASK, "0 0 */23 * * ?"); // 每4小时
        //log.debug("实例同步任务加载完成....");
        //删除实例同步任务
        deleteScheduleJob(scheduler, INSTANCE_SYNC_TASK, INSTANCE_SYNC_TASK);

        // 2. 流量统计任务
        scheduleJob(scheduler, instanceTrafficJob.getClass(), INSTANCE_TRAFFIC_TASK, INSTANCE_TRAFFIC_TASK, "0 0/5 * * * ?"); // 每5分钟
        log.debug("流量统计任务加载完成....");

        // 3. 区域加载任务
        //scheduleJob(scheduler, loadRegionJob.getClass(), LOAD_REGION_TASK, LOAD_REGION_TASK, "14 32 11 * * ?"); // 每天执行一次
        //log.debug("区域加载任务加载完成....");
        //删除区域加载任务
        deleteScheduleJob(scheduler, LOAD_REGION_TASK, LOAD_REGION_TASK);

        // 4. 实例创建任务调度器 - ，需要每10秒执行一次
        scheduleJob(scheduler, createInstanceJob.getClass(), CREATE_INSTANCE_TASK, CREATE_INSTANCE_TASK, "*/6 * * * * ?"); // 每10秒
        log.debug("实例创建任务加载完成....");

        // 5. 版本检查(30分钟检查一次)(删除,改为登录的时候检查就行)
        //scheduleJob(scheduler, versionCheckJob.getClass(), VERSION_CHECK_TASK, VERSION_CHECK_TASK, "0 */15 * * * ?");
        //删除定时更新任务
        deleteScheduleJob(scheduler, VERSION_CHECK_TASK, VERSION_CHECK_TASK);

        //6. 账号测活任务
        scheduleJob(scheduler, checkLiveJob.getClass(), ACCOUNT_LIVE_CHECK_TASK, ACCOUNT_LIVE_CHECK_TASK, "0 0 * * * ?"); // 每10秒
        log.debug("版本检查任务加载完成....");

        //7. vpsping测试
        scheduleJob(scheduler, pingConnTimeJob.getClass(), PING_CON_TIME_TASK, PING_CON_TIME_TASK, "0 0/5 * * * ?"); // 每10秒
        log.debug("vps Ping 任务加载完成....");

        //8. ssl证书任务
        scheduleJob(scheduler, sslCertJob.getClass(), SSL_CERT_TASK, SSL_CERT_TASK, "0 0 4 * * ?"); //每天凌晨四点执行

        //9. 刷新账号粪污
        scheduleJob(scheduler, bootInstanceRefreshJob.getClass(), BOOT_INSTANCE_REFRESH_TASK, BOOT_INSTANCE_REFRESH_TASK, "0 0 0 * * ?"); //   0 0/5 * * * ?

        //探针心跳任务
        scheduleJob(scheduler, monitorFlashHeartbeatJob.getClass(), MONITOR_FLASH_HEARTBEAT_TASK, MONITOR_FLASH_HEARTBEAT_TASK, "*/15 * * * * ?"); //每15秒

        //探针离线检查
        scheduleJob(scheduler, checkOfflineInstanceJob.getClass(), MONITOR_CHECK_OFFLINE_INSTANCE_TASK, MONITOR_CHECK_OFFLINE_INSTANCE_TASK, "0 */1 * * * ?");

        // 分片上传孤儿清理（每天凌晨2点）
        scheduleJob(scheduler, multipartUploadCleanupJob.getClass(), MULTIPART_UPLOAD_CLEANUP_TASK, MULTIPART_UPLOAD_CLEANUP_TASK, "0 0 2 * * ?");
        log.debug("分片上传清理任务加载完成....");

        // AI聊天历史清理（每天凌晨3点）
        scheduleJob(scheduler, aiChatHistoryCleanupJob.getClass(), AI_CHAT_HISTORY_CLEANUP_TASK, AI_CHAT_HISTORY_CLEANUP_TASK, "0 0 3 * * ?");
        log.debug("AI聊天历史清理任务加载完成....");
    }

    /**
     * 获取每日通知任务的Cron表达式
     */
    private String getDailyTaskCron() {
        // 从配置中获取时间
        try {
            int hour = systemConfigRepository.findByKey("task.execute.hour")
                    .map(config -> Integer.parseInt(config.getValue()))
                    .orElse(9); // 默认9点

            return String.format("0 0 %d * * ?", hour);
        } catch (Exception e) {
            return "0 0 9 * * ?"; // 默认每天9点
        }
    }

    /**
     * 获取IP检测任务的Cron表达式
     */
    private String getIpCheckCron() {
        try {
            int interval = systemConfigRepository.findByKey("ipcheck.interval")
                    .map(config -> Integer.parseInt(config.getValue()))
                    .orElse(6); // 默认6小时

            return String.format("0 0 */%d * * ?", interval);
        } catch (Exception e) {
            return "0 0 */6 * * ?"; // 默认每6小时
        }
    }

    /**
     * 调度作业的通用方法
     */
    private void scheduleJob(Scheduler scheduler, Class jobClass, String jobName, String groupName, String cronExpression)
            throws SchedulerException {

        JobKey jobKey = JobKey.jobKey(jobName, groupName);
        TriggerKey triggerKey = TriggerKey.triggerKey(jobName + "Trigger", groupName);

        // 检查Job是否存在
        if (scheduler.checkExists(jobKey)) {
            log.debug("Job已存在: {}.{}", groupName, jobName);

            // 只更新触发器
            Trigger newTrigger = TriggerBuilder.newTrigger()
                    .withIdentity(triggerKey)
                    .withSchedule(CronScheduleBuilder.cronSchedule(cronExpression))
                    .build();

            // 如果触发器存在，重新调度；否则，添加新触发器
            if (scheduler.checkExists(triggerKey)) {
                scheduler.rescheduleJob(triggerKey, newTrigger);
                log.debug("重新调度现有触发器: {}", triggerKey);
            } else {
                scheduler.scheduleJob(newTrigger);
                log.debug("为现有Job添加新触发器: {}", triggerKey);
            }
        } else {
            // Job不存在，创建新Job和触发器
            JobDetail jobDetail = JobBuilder.newJob(jobClass)
                    .withIdentity(jobName, groupName)
                    .storeDurably()
                    .build();

            Trigger trigger = TriggerBuilder.newTrigger()
                    .withIdentity(triggerKey)
                    .withSchedule(CronScheduleBuilder.cronSchedule(cronExpression))
                    .build();

            scheduler.scheduleJob(jobDetail, trigger);
            log.debug("创建新Job和触发器: {}.{}", groupName, jobName);
        }
    }

    private void deleteScheduleJob(Scheduler scheduler, String jobName, String groupName) throws SchedulerException {
        JobKey jobKey = JobKey.jobKey(jobName, groupName);

        // 检查Job是否存在
        if (scheduler.checkExists(jobKey)) {
            log.debug("Job已存在: {}.{}", groupName, jobName);
            scheduler.deleteJob(jobKey);
        }
    }

    /**
     * 更新任务的执行时间
     */
    public void updateJobSchedule(String jobName, String groupName, String cronExpression)
            throws SchedulerException {
        TriggerKey triggerKey = TriggerKey.triggerKey(jobName + "Trigger", groupName);

        // 创建新的触发器
        Trigger newTrigger = TriggerBuilder.newTrigger()
                .withIdentity(triggerKey)
                .withSchedule(CronScheduleBuilder.cronSchedule(cronExpression))
                .build();

        // 重新调度任务
        scheduler.rescheduleJob(triggerKey, newTrigger);
    }

    /**
     * 暂停任务
     */
    public void pauseJob(String jobName, String groupName) throws SchedulerException {
        scheduler.pauseJob(org.quartz.JobKey.jobKey(jobName, groupName));
        log.info("任务已暂停: {}", jobName);
    }

    /**
     * 恢复任务
     */
    public void resumeJob(String jobName, String groupName) throws SchedulerException {
        scheduler.resumeJob(org.quartz.JobKey.jobKey(jobName, groupName));
        log.info("任务已恢复: {}", jobName);
    }


    /**
    * @Description: 创建实例的执行秒数
    *
    */
     public static String getDailyTaskCron(int second) {
         return String.format("%d * * * * ?", second);
    }
}
