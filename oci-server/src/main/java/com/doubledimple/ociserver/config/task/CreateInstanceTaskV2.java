package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.config.event.InstanceBackUpEvent;
import com.doubledimple.ociserver.config.OciLogBuilder;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleCloudService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import java.sql.Timestamp;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_TASK_ERROR_TEMPLATE;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.isCurrentHourInRange;
import static com.doubledimple.ociserver.config.constant.GenPojoUtils.bootPojo;

/**
 * 抢机任务调度器 V3
 * <p>
 * V2 -> V3 关键改进：
 * 1. 父任务（processTask）与 OCI API 子任务（createInstanceData）使用不同线程池，
 *    彻底消除"自我耗尽 / 父等子 死锁"问题，解决小机器上 doSuccess 不触发的根因。
 * 2. 抛弃 future.get(timeout) 同步阻塞模型，改用 whenComplete + ScheduledExecutor
 *    实现的非阻塞超时机制，父任务提交子任务后立即释放线程。
 * 3. 任何非成功的退出路径（超时/异常/无 IP）都会调用 removeTaskKey，
 *    避免 activeTaskKeyMap 中的 key 永久占用导致后续任务被去重逻辑跳过。
 * 4. nextExecutionTime 推进与 key 释放分离，逻辑更清晰。
 * 5. 监控接口同时暴露两个池子的指标。
 * <p>
 * 外部调用接口（addTask / updateTaskInterval / deleteTask / getSystemStatus /
 * checkAndExecuteTasksOnce / removeTaskKey）保持与 V2 完全兼容。
 */
@Service
@Slf4j
public class CreateInstanceTaskV2 {

    @Resource
    private BootInstanceRepository instanceRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    @Lazy
    private OracleCloudService oracleCloudService;

    @Resource
    private ApplicationEventPublisher eventPublisher;

    @Resource
    private ScheduledThreadPoolExecutor delayedTaskExecutor;

    /** 父任务池：跑 processTask（轻量、调度逻辑） */
    @Resource(name = "instanceTaskExecutor")
    private ThreadPoolExecutor taskExecutor;

    /**
     * 子任务池：跑 OCI API 调用（重量、IO 密集）。
     * 必须与 taskExecutor 物理隔离，否则父任务占满池子时
     * 子任务进不来，父任务 future.get 永远等不到结果，形成自我耗尽。
     * <p>
     * 需要在 ThreadPoolConfig 中新增名为 "ociApiExecutor" 的 Bean。
     */
    @Resource(name = "ociApiExecutor")
    private ThreadPoolExecutor ociApiExecutor;

    @Resource
    @Lazy
    MessageFactory messageFactory;

    @Resource
    @Lazy
    OciLogBuilder ociLogBuilder;

    /** 运行状态标记 */
    private final AtomicBoolean running = new AtomicBoolean(true);

    /** 批次大小（根据系统资源自动调整） */
    private final int BATCH_SIZE;

    /** API 超时时间（秒） */
    private static final long API_TIMEOUT_SECONDS = 80;

    /** 同一 (tenancy + region + architecture) 同时只允许一个任务运行 */
    private final Map<String, String> activeTaskKeyMap = new ConcurrentHashMap<>();

    public CreateInstanceTaskV2() {
        Runtime runtime = Runtime.getRuntime();
        int cpu = runtime.availableProcessors();
        long memoryMB = runtime.maxMemory() / (1024 * 1024);

        if (cpu <= 1 && memoryMB <= 1536) {
            BATCH_SIZE = 30;
            log.debug("检测到小型服务器(1C1G)，批次大小: 30");
        } else if (cpu <= 2 && memoryMB <= 4096) {
            BATCH_SIZE = 50;
            log.debug("检测到中型服务器(2C4G)，批次大小: 50");
        } else {
            BATCH_SIZE = 200;
            log.debug("检测到大型服务器，批次大小: 200");
        }

        log.debug("抢机任务V3初始化完成 - 批次大小: {}, API超时: {}秒", BATCH_SIZE, API_TIMEOUT_SECONDS);
    }

    // ==================== 调度入口 ====================

    /**
     * 执行到期任务 - 由 Quartz 调度器调用
     */
    public void checkAndExecuteTasksOnce() {
        if (!running.get()) {
            log.debug("任务系统已停止");
            return;
        }

        try {
            long startTime = System.currentTimeMillis();
            Timestamp currentTime = new Timestamp(startTime);

            // 按 (tenant_id, architecture) 去重后再取 BATCH_SIZE，避免同账号大量重复任务挤占名额、饿死其它账号
            List<BootInstance> expiredTasks = instanceRepository.findDistinctTasksToExecute(
                    currentTime,
                    BATCH_SIZE
            );

            if (expiredTasks.isEmpty()) {
                log.debug("当前没有到期任务");
                return;
            }

            log.debug("查询到 {} 个到期任务（限制{}条）", expiredTasks.size(), BATCH_SIZE);

            Set<Long> tenantIds = expiredTasks.stream()
                    .map(BootInstance::getTenantId)
                    .collect(Collectors.toSet());

            Map<Long, Tenant> tenantMap = tenantRepository.findAllById(tenantIds)
                    .stream()
                    .collect(Collectors.toMap(Tenant::getId, t -> t));

            Map<String, BootInstance> dedupedTasks = deduplicateTasks(expiredTasks, tenantMap);

            log.debug("去重后剩余 {} 个任务", dedupedTasks.size());

            for (BootInstance task : dedupedTasks.values()) {
                try {
                    taskExecutor.submit(() -> processTask(task));
                } catch (Exception e) {
                    // 提交失败(如线程池已关闭)必须释放已占用的 key，否则该 key 永久泄漏
                    log.error("提交任务失败，释放占用 - taskId: {}", task.getBootId(), e);
                    removeTaskKey(task);
                }
            }

            long endTime = System.currentTimeMillis();
            log.debug("任务调度完成，提交 {} 个任务，耗时: {}ms",
                    dedupedTasks.size(), (endTime - startTime));

        } catch (Exception e) {
            log.error("执行到期任务时出错", e);
        }
    }

    /**
     * 去重逻辑：按 tenancy + region + architecture
     * 同一个账号、同一个区域、同一个架构，只保留最早到期的任务
     */
    private Map<String, BootInstance> deduplicateTasks(
            List<BootInstance> tasks,
            Map<Long, Tenant> tenantMap) {

        Map<String, BootInstance> dedupedTasks = new LinkedHashMap<>();

        for (BootInstance task : tasks) {
            Tenant tenant = tenantMap.get(task.getTenantId());
            if (tenant == null) {
                continue;
            }

            String key = tenant.getTenancy() + "_" +
                    tenant.getRegion() + "_" +
                    task.getArchitecture();

            if (activeTaskKeyMap.containsKey(key)) {
                // key 被占用 = 该(账号+区域+架构)已有一个抢机在飞，本轮一律跳过。
                // 包括 holder 自己也要跳过：否则会对同一任务并发发起抢机，并在其中一个完成时
                // 提前释放 key，破坏单飞。等在飞任务结束释放 key 后，下一轮再重新调度。
                log.debug("Key {} 已被任务 {} 占用，本轮跳过任务 {}",
                        key, activeTaskKeyMap.get(key), task.getBootId());
                continue;
            }

            activeTaskKeyMap.put(key, task.getBootId());
            dedupedTasks.put(key, task);
            log.debug("占用 Key {} 为任务 {}", key, task.getBootId());
        }
        return dedupedTasks;
    }

    // ==================== 单任务处理（异步化） ====================

    /**
     * 处理单个任务（运行在 taskExecutor 父池子中）。
     * <p>
     * 核心改造：抢机调用 executeGrabTaskAsync 后立即返回，父线程释放回池子。
     * 实际抢机结果由回调处理，避免父任务长时间持有线程。
     */
    private void processTask(BootInstance task) {
        BootInstance latestTask = null;
        long time = System.currentTimeMillis();

        try {
            latestTask = instanceRepository.findById(task.getId()).orElse(null);
            if (latestTask == null) {
                removeTaskKey(task);
                return;
            }
            if (latestTask.getStatus() != 1) {
                removeTaskKey(latestTask);
                return;
            }
            if (latestTask.getNextExecutionTime() != null &&
                    latestTask.getNextExecutionTime().getTime() > System.currentTimeMillis()) {
                // 还没到执行时间（被其他线程刷过了），释放占用避免误锁
                removeTaskKey(latestTask);
                return;
            }

            // 推进 nextExecutionTime 占位，避免下一轮重复捞到
            long nextTime = time + latestTask.getLoopTime() * 1000L;
            latestTask.setNextExecutionTime(new Timestamp(nextTime));
            instanceRepository.save(latestTask);

            // 时间段校验
            if (!isCurrentHourInRange(latestTask.getDayGap())) {
                log.debug("任务 {} 时间段外，跳过", latestTask.getBootId());
                removeTaskKey(latestTask);
                return;
            }

            User user = buildUser(latestTask);
            if (user == null) {
                log.warn("任务 {} 构建 User 失败，跳过", latestTask.getBootId());
                removeTaskKey(latestTask);
                return;
            }

            // 异步发起抢机，结果由回调处理；processTask 在此立即返回，父线程释放
            executeGrabTaskAsync(latestTask, user);

        } catch (Exception e) {
            log.error("处理任务异常 - taskId: {}", task.getBootId(), e);
            // 异常路径必须释放 key，否则永久占用
            removeTaskKey(latestTask != null ? latestTask : task);
        }
    }

    // ==================== 抢机执行（异步 + 非阻塞超时） ====================

    /**
     * 异步执行抢机任务，带非阻塞超时保护。
     * <p>
     * 设计要点：
     * 1. 子任务跑在 ociApiExecutor，与父池子物理隔离
     * 2. 用 ScheduledExecutor 触发超时，而不是 future.get(timeout) 同步等
     * 3. whenComplete 回调里统一处理成功/失败/超时，并保证 key 一定被释放
     */
    private void executeGrabTaskAsync(BootInstance task, User user) {
        String taskId = task.getBootId();

        CompletableFuture<OracleInstanceDetail> future = CompletableFuture.supplyAsync(() -> {
            try {
                log.debug("调用云服务API - TaskId: {}", taskId);
                return oracleCloudService.createInstanceData(user);
            } catch (Exception e) {
                if (isNetworkTemporaryError(e)) {
                    ociLogBuilder.buildOpenNoThrow("[TaskId={}] 网络连接暂时不可达(DNS/UnknownHost)，跳过本次失败计次: {}", taskId, e.getMessage());
                    return null;
                }
                ociLogBuilder.buildOpenNoThrow("execute openBoot error: taskId:{} reason:{}", taskId, e.getMessage());
                updateTaskFailCount(task, e.getMessage());
                return null;
            }
        }, ociApiExecutor);

        // 非阻塞超时：到点强制 completeExceptionally，不占用任何线程
        ScheduledFuture<?> timeoutFuture = delayedTaskExecutor.schedule(() -> {
            if (!future.isDone()) {
                future.completeExceptionally(
                        new TimeoutException("抢机API超时(" + API_TIMEOUT_SECONDS + "秒) - TaskId: " + taskId));
            }
        }, API_TIMEOUT_SECONDS, TimeUnit.SECONDS);

        // 结果回调：成功/失败/超时统一在这里处理
        future.whenComplete((instanceData, throwable) -> {
            // 结果先到则取消超时
            timeoutFuture.cancel(false);

            try {
                if (throwable != null) {
                    handleGrabFailure(task, throwable);
                    return;
                }

                if (instanceData != null && instanceData.getPublicIp() != null) {
                    ociLogBuilder.buildOpenBootSuccess("抢机成功 - TaskId: {}, IP: {}", taskId, instanceData.getPublicIp());
                    delayedTaskExecutor.schedule(
                            () -> eventPublisher.publishEvent(new InstanceBackUpEvent(this, instanceData)),
                            3, TimeUnit.MINUTES);
                    updateTaskCompleted(task);   // 内部会 removeTaskKey
                } else {
                    log.debug("未抢到实例 - TaskId: {}", taskId);
                    // 未抢到也要释放 key，让下一轮可以重新调度
                    removeTaskKey(task);
                }
            } catch (Exception e) {
                log.error("处理抢机结果异常 - TaskId: {}", taskId, e);
                removeTaskKey(task);
            }
        });
    }

    /**
     * 抢机失败统一处理（包含超时、网络异常、其他异常）。
     */
    private void handleGrabFailure(BootInstance task, Throwable throwable) {
        String taskId = task.getBootId();

        // 解包 CompletionException
        Throwable real = throwable;
        while (real instanceof java.util.concurrent.CompletionException && real.getCause() != null) {
            real = real.getCause();
        }

        try {
            if (real instanceof TimeoutException) {
                ociLogBuilder.buildOpenNoThrow("抢机API超时({}秒) - TaskId: {}", API_TIMEOUT_SECONDS, taskId);
                // todo 暂时不告警了
                // messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(
                //         String.format(MESSAGE_CONFIG_TASK_TIMEOUT_TEMPLATE,
                //                 user.getUserName(), RegionEnum.getNameSimple(user.getRegion())));
            } else if (isNetworkTemporaryError(real)) {
                ociLogBuilder.buildOpenNoThrow("由于网络波动，任务 TaskId: {} 将在下个周期重试", taskId);
            } else {
                ociLogBuilder.buildOpenNoThrow("抢机失败 - TaskId: {}", taskId, real);
                updateTaskFailCount(task, real.getMessage());
            }
        } finally {
            // 任何失败路径都必须释放 key
            removeTaskKey(task);
        }
    }

    private boolean isNetworkTemporaryError(Throwable e) {
        if (e == null) return false;
        String msg = e.getMessage();
        return e instanceof java.net.UnknownHostException ||
                (msg != null && (msg.contains("UnknownHostException") || msg.contains("ConnectException")));
    }

    // ==================== 失败/完成处理 ====================

    private void updateTaskFailCount(BootInstance task, String err) {
        try {
            if (StringUtils.isBlank(err)) err = "conn time out";
            instanceRepository.incrementFailCount(task.getId());
            log.debug("任务 {} 失败次数已累加", task.getBootId());

            Long tenantId = task.getTenantId();
            Optional<Tenant> optionalTenant = tenantRepository.findById(tenantId);
            if (optionalTenant.isPresent()) {
                Tenant tenant = optionalTenant.get();
                String defName = tenant.getUserName();
                String regionName = RegionEnum.getCodeByName(tenant.getRegion());
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(
                        String.format(MESSAGE_CONFIG_TASK_ERROR_TEMPLATE, defName, regionName, err));
            }
        } catch (Exception e) {
            log.error("更新任务失败计数异常: {}", task.getBootId(), e);
        }
    }

    /**
     * 更新任务为已完成
     */
    private void updateTaskCompleted(BootInstance task) {
        try {
            instanceRepository.markStatusAsSuccess(task.getId());
        } catch (Exception e) {
            log.error("更新任务完成状态失败: {}", task.getBootId(), e);
        } finally {
            removeTaskKey(task);
        }
    }

    /**
     * 构建 User 对象
     */
    private User buildUser(BootInstance bootInstance) {
        try {
            Tenant tenant = tenantRepository.findById(bootInstance.getTenantId()).orElse(null);
            return bootPojo(tenant, bootInstance);
        } catch (Exception e) {
            log.error("构建用户对象失败", e);
            return null;
        }
    }

    // ==================== 外部接口（与 V2 兼容） ====================

    public void addTask(BootInstance bootInstance) {
        try {
            long nextTime = System.currentTimeMillis() + bootInstance.getLoopTime() * 1000L;
            bootInstance.setNextExecutionTime(new Timestamp(nextTime));
            bootInstance.setStatus(1);
            instanceRepository.save(bootInstance);
            log.info("添加新任务 - ID: {}, 下次执行: {}",
                    bootInstance.getBootId(), new Timestamp(nextTime));
        } catch (Exception e) {
            log.error("添加任务失败: {}", bootInstance.getBootId(), e);
        }
    }

    public boolean updateTaskInterval(String taskId, int newInterval) {
        if (newInterval <= 0) {
            log.warn("无效的间隔: {}", newInterval);
            return false;
        }

        try {
            BootInstance task = instanceRepository.queryBootInstanceById(taskId);
            if (task == null) {
                log.warn("任务未找到: {}", taskId);
                return false;
            }
            task.setLoopTime(newInterval);
            long newExecuteAt = System.currentTimeMillis() + newInterval * 1000L;
            task.setNextExecutionTime(new Timestamp(newExecuteAt));

            instanceRepository.save(task);

            log.info("任务间隔已更新 - TaskId: {}, 新间隔: {}秒, 下次执行: {}",
                    taskId, newInterval, new Timestamp(newExecuteAt));
            return true;
        } catch (Exception e) {
            log.error("更新任务间隔失败: {}", taskId, e);
            return false;
        }
    }

    public boolean deleteTask(String taskId) {
        BootInstance task = null;
        try {
            task = instanceRepository.queryBootInstanceById(taskId);
            if (task == null) {
                log.warn("任务未找到: {}", taskId);
                return false;
            }

            task.setStatus(0);
            instanceRepository.save(task);

            log.debug("删除任务: {}", taskId);
            return true;
        } catch (Exception e) {
            log.error("删除任务失败: {}", taskId, e);
            return false;
        } finally {
            if (task != null) {
                removeTaskKey(task);
            }
        }
    }

    /**
     * 获取系统状态（监控接口）。V3 同时暴露父池子和子池子的指标。
     */
    public Map<String, Object> getSystemStatus() {
        Map<String, Object> status = new HashMap<>();

        try {
            long totalTasks = instanceRepository.count();
            long runningTasks = instanceRepository.countByStatus(1);

            // 父池子（taskExecutor / instanceTaskExecutor）
            Map<String, Object> parentPool = new HashMap<>();
            parentPool.put("activeThreads", taskExecutor.getActiveCount());
            parentPool.put("queueSize", taskExecutor.getQueue().size());
            parentPool.put("poolSize", taskExecutor.getPoolSize());
            parentPool.put("maxPoolSize", taskExecutor.getMaximumPoolSize());
            parentPool.put("completedTasks", taskExecutor.getCompletedTaskCount());

            // 子池子（ociApiExecutor）
            Map<String, Object> ociPool = new HashMap<>();
            ociPool.put("activeThreads", ociApiExecutor.getActiveCount());
            ociPool.put("queueSize", ociApiExecutor.getQueue().size());
            ociPool.put("poolSize", ociApiExecutor.getPoolSize());
            ociPool.put("maxPoolSize", ociApiExecutor.getMaximumPoolSize());
            ociPool.put("completedTasks", ociApiExecutor.getCompletedTaskCount());

            status.put("totalTasks", totalTasks);
            status.put("runningTasks", runningTasks);
            status.put("activeKeyCount", activeTaskKeyMap.size());
            status.put("parentPool", parentPool);
            status.put("ociApiPool", ociPool);
            status.put("batchSize", BATCH_SIZE);
            status.put("running", running.get());

            log.debug("系统状态V3 - 总任务: {}, 运行中: {}, 占用Key: {}, 父池[活跃{}/队列{}], OCI池[活跃{}/队列{}]",
                    totalTasks, runningTasks, activeTaskKeyMap.size(),
                    taskExecutor.getActiveCount(), taskExecutor.getQueue().size(),
                    ociApiExecutor.getActiveCount(), ociApiExecutor.getQueue().size());

        } catch (Exception e) {
            log.error("获取系统状态失败", e);
        }

        return status;
    }

    @PreDestroy
    public void shutdown() {
        log.debug("正在关闭任务系统V3...");
        running.set(false);
        log.debug("任务系统V3关闭完成");
    }

    /**
     * 移除某个任务对应的占用 key。
     * 在任务完成 / 失败 / 超时 / 删除任务 / 异常退出时调用。
     */
    public void removeTaskKey(BootInstance task) {
        try {
            if (task == null || task.getBootId() == null) return;

            // 按持有者 bootId 释放，不再重新查询租户重建 key：
            // 1) 租户被删/查询失败时也能正常释放，避免 key 永久泄漏导致该(账号+区域+架构)永远被跳过；
            // 2) 省去每次释放都要做的一次 DB 查询。
            // 一个 bootId 至多持有一个 key，只移除“值 == 该 bootId”的条目，不会误删别的任务占用的 key。
            boolean removed = activeTaskKeyMap.entrySet()
                    .removeIf(e -> task.getBootId().equals(e.getValue()));
            if (removed) {
                log.debug("释放占用 - TaskId={}", task.getBootId());
            }
        } catch (Exception e) {
            log.error("释放 key 失败", e);
        }
    }
}