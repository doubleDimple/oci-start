package com.doubledimple.ociserver.config.task;/*
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
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_TASK_ERROR_TEMPLATE;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.isCurrentHourInRange;
import static com.doubledimple.ociserver.config.constant.GenPojoUtils.bootPojo;

*/
/**
 *
 * 核心特点：
 *//*

@Service
@Slf4j
public class CreateInstanceTaskV2Older {

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

    @Resource(name = "instanceTaskExecutor")
    private ThreadPoolExecutor taskExecutor;

    @Resource
    @Lazy
    MessageFactory messageFactory;

    @Resource
    @Lazy
    OciLogBuilder ociLogBuilder;

    // 任务锁（防止同一任务重复执行）
    //private final ConcurrentHashMap<String, Lock> taskLocks = new ConcurrentHashMap<>();

    // 运行状态标记
    private final AtomicBoolean running = new AtomicBoolean(true);

    // 批次大小（根据系统资源自动调整）
    private final int BATCH_SIZE;

    // API超时时间（60秒）
    private static final long API_TIMEOUT_SECONDS = 80;

    private final Map<String, String> activeTaskKeyMap = new ConcurrentHashMap<>();


    public CreateInstanceTaskV2Older() {
        // 检测系统资源并配置批次大小
        Runtime runtime = Runtime.getRuntime();
        int cpu = runtime.availableProcessors();
        long memoryMB = runtime.maxMemory() / (1024 * 1024);

        if (cpu <= 1 && memoryMB <= 1536) {
            BATCH_SIZE = 30;  // 1C1G小机器
            log.debug("检测到小型服务器(1C1G)，批次大小: 30");
        } else if (cpu <= 2 && memoryMB <= 4096) {
            BATCH_SIZE = 50;  // 2C4G中等机器
            log.debug("检测到中型服务器(2C4G)，批次大小: 50");
        } else {
            BATCH_SIZE = 200; // 大机器
            log.debug("检测到大型服务器，批次大小: 200");
        }

        log.debug("抢机任务初始化完成 - 批次大小: {}, API超时: {}秒", BATCH_SIZE, API_TIMEOUT_SECONDS);
    }

    */
/**
     * 执行到期任务 - 由Quartz调度器调用
     * 这个方法会被 CreateInstanceJob 定时调用
     *//*

    public void checkAndExecuteTasksOnce() {
        if (!running.get()) {
            log.debug("任务系统已停止");
            return;
        }

        try {
            long startTime = System.currentTimeMillis();
            Timestamp currentTime = new Timestamp(startTime);

            // 1. 查询到期任务
            List<BootInstance> expiredTasks = instanceRepository.findTasksToExecute(
                    currentTime,
                    BATCH_SIZE
            );

            if (expiredTasks.isEmpty()) {
                log.debug("当前没有到期任务");
                return;
            }

            log.debug("查询到 {} 个到期任务（限制{}条）", expiredTasks.size(), BATCH_SIZE);

            // 2. 批量查询Tenant信息（避免N+1问题）
            Set<Long> tenantIds = expiredTasks.stream()
                    .map(BootInstance::getTenantId)
                    .collect(Collectors.toSet());

            Map<Long, Tenant> tenantMap = tenantRepository.findAllById(tenantIds)
                    .stream()
                    .collect(Collectors.toMap(Tenant::getId, t -> t));

            // 3. 去重（按 tenancy + region + architecture）
            Map<String, BootInstance> dedupedTasks = deduplicateTasks(expiredTasks, tenantMap);

            log.debug("去重后剩余 {} 个任务", dedupedTasks.size());

            // 4. 提交到线程池执行
            for (BootInstance task : dedupedTasks.values()) {
                taskExecutor.submit(() -> processTask(task));
            }

            long endTime = System.currentTimeMillis();
            log.debug("任务调度完成，提交 {} 个任务，耗时: {}ms",
                    dedupedTasks.size(), (endTime - startTime));

        } catch (Exception e) {
            log.error("执行到期任务时出错", e);
        }
    }

    */
/**
     * 去重逻辑：按 tenancy + region + architecture
     * 同一个账号、同一个区域、同一个架构，只保留最早到期的任务
     *//*

    private Map<String, BootInstance> deduplicateTasks(
            List<BootInstance> tasks,
            Map<Long, Tenant> tenantMap) {

        Map<String, BootInstance> dedupedTasks = new LinkedHashMap<>();

        for (BootInstance task : tasks) {
            Tenant tenant = tenantMap.get(task.getTenantId());
            if (tenant == null) {
                continue;
            }

            // 构建去重Key: tenancy_region_architecture
            String key = tenant.getTenancy() + "_" +
                    tenant.getRegion() + "_" +
                    task.getArchitecture();

            // 如果 key 已被占用 → 直接跳过
            if (activeTaskKeyMap.containsKey(key)) {
                String mainBootId = activeTaskKeyMap.get(key);

                // 只有在这个主任务刚好出现在当前 expiredTasks 时，才加入执行
                if (task.getBootId().equals(mainBootId)) {
                    dedupedTasks.put(key, task);
                    log.debug("Key {} 已被任务 {} 占用，本轮继续执行它", key, mainBootId);
                } else {
                    log.debug("Key {} 已被任务 {} 占用，跳过替补任务 {}", key, mainBootId, task.getBootId());
                }

                continue;
            }

            // key 没有被占用 → 占用它
            activeTaskKeyMap.put(key, task.getBootId());
            dedupedTasks.put(key, task);
            log.debug("占用 Key {} 为任务 {}", key, task.getBootId());
        }
        return dedupedTasks;
    }

    */
/**
     * 处理单个任务
     *//*

    private void processTask(BootInstance task) {
        String taskId = task.getBootId();
        //Lock taskLock = taskLocks.computeIfAbsent(taskId, k -> new ReentrantLock());

        boolean locked = false;
        boolean taskCompleted = false;
        BootInstance latestTask = null;
        long time = System.currentTimeMillis();

        try {
            //locked = taskLock.tryLock(1, TimeUnit.SECONDS);
            //if (!locked) return;

            latestTask = instanceRepository.findById(task.getId()).orElse(null);
            if (latestTask == null) return;
            if (latestTask.getStatus() != 1) return;
            if (latestTask.getNextExecutionTime() != null &&
                    latestTask.getNextExecutionTime().getTime() > System.currentTimeMillis()) return;

            // 占位更新
            long nextTime = time + latestTask.getLoopTime() * 1000L;
            latestTask.setNextExecutionTime(new Timestamp(nextTime));
            instanceRepository.save(latestTask);

            // 时间段校验
            if (!isCurrentHourInRange(latestTask.getDayGap())) {
                log.debug("任务 {} 时间段外，跳过", taskId);
                return;
            }

            // 执行抢机
            boolean success = executeGrabTaskWithTimeout(latestTask, buildUser(latestTask));

            if (success) {
                updateTaskCompleted(latestTask);
                taskCompleted = true;
            }

        } catch (Exception e) {
            log.error("处理任务异常", e);
        } finally {
            //if (locked) taskLock.unlock();
            if (!taskCompleted && latestTask != null && latestTask.getStatus() == 1) {
                long nextTime = time + latestTask.getLoopTime() * 1000L;
                latestTask.setNextExecutionTime(new Timestamp(nextTime));
                instanceRepository.save(latestTask);
            }
        }
    }

    private void updateTaskFailCount(BootInstance task,String err) {
        try {
            if (StringUtils.isBlank( err)) err = "conn time out";
            instanceRepository.incrementFailCount(task.getId());
            log.debug("任务 {} 失败次数已累加", task.getBootId());
            Long tenantId = task.getTenantId();
            Optional<Tenant> optionalTenant = tenantRepository.findById(tenantId);
            if (optionalTenant.isPresent()){
                Tenant tenant = optionalTenant.get();
                String defName = tenant.getUserName();
                String regionName = RegionEnum.getCodeByName(tenant.getRegion());
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_TASK_ERROR_TEMPLATE,defName,regionName,err));
            }
        } catch (Exception e) {
            log.error("更新任务失败计数异常: {}", task.getBootId(), e);
        } finally {
            removeTaskKey(task);
        }
    }

    */
/**
     * 执行抢机任务 - 带超时保护
     *//*

    private boolean executeGrabTaskWithTimeout(BootInstance task, User user) {
        String taskId = task.getBootId();

        try {
            CompletableFuture<OracleInstanceDetail> future = CompletableFuture.supplyAsync(() -> {
                try {
                    log.debug("调用云服务API - TaskId: {}", taskId);
                    return oracleCloudService.createInstanceData(user);
                } catch (Exception e) {
                    if (isNetworkTemporaryError(e)) {
                        ociLogBuilder.buildOpenNoThrow("网络连接暂时不可达(DNS/UnknownHost)，跳过本次失败计次: {}", e.getMessage());
                        return null;
                    }
                    ociLogBuilder.buildOpenNoThrow("execute openBoot error: taskId:{} reason:{}", taskId, e.getMessage());
                    updateTaskFailCount(task,e.getMessage());
                    return null;
                }
            }, taskExecutor);

            OracleInstanceDetail instanceData = future.get(API_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            if (instanceData != null && instanceData.getPublicIp() != null) {
                ociLogBuilder.buildOpenBootSuccess("抢机成功 - TaskId: {}, IP: {}", taskId, instanceData.getPublicIp());
                delayedTaskExecutor.schedule(
                        () -> eventPublisher.publishEvent(new InstanceBackUpEvent(this, instanceData)),
                        3, TimeUnit.MINUTES);
                return true;
            }
            log.debug("未抢到实例 - TaskId: {}", taskId);
            return false;
        } catch (TimeoutException e) {
            ociLogBuilder.buildOpenNoThrow("抢机API超时({}秒) - TaskId: {}", API_TIMEOUT_SECONDS, taskId);
            //todo 暂时不告警了
            //messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_TASK_TIMEOUT_TEMPLATE,user.getUserName(),RegionEnum.getNameSimple(user.getRegion())));
            //updateTaskFailCount(task,e.getMessage());
            return false;
        } catch (Exception e) {
            if (!isNetworkTemporaryError(e)) {
                ociLogBuilder.buildOpenNoThrow("抢机失败 - TaskId: {}", taskId, e);
                updateTaskFailCount(task, e.getMessage());
            } else {
                ociLogBuilder.buildOpenNoThrow("由于网络波动，任务 TaskId: {} 将在下个周期重试", taskId);
            }
            return false;
        }
    }

    private boolean isNetworkTemporaryError(Throwable e) {
        if (e == null) return false;
        String msg = e.getMessage();
        return e instanceof java.net.UnknownHostException ||
                (msg != null && (msg.contains("UnknownHostException") || msg.contains("ConnectException")));
    }

    */
/**
     * 更新任务为已完成
     *//*

    private void updateTaskCompleted(BootInstance task) {
        try {
            instanceRepository.markStatusAsSuccess(task.getId());
        } catch (Exception e) {
            log.error("更新任务完成状态失败: {}", task.getBootId(), e);
        } finally {
            removeTaskKey(task);
        }
    }

    */
/**
     * 构建User对象
     *//*

    private User buildUser(BootInstance bootInstance) {
        try {
            Tenant tenant = tenantRepository.findById(bootInstance.getTenantId()).orElse(null);
            return bootPojo(tenant, bootInstance);
        } catch (Exception e) {
            log.error("构建用户对象失败", e);
            return null;
        }
    }

    */
/**
     * 新增任务（外部调用接口）
     *//*

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

    */
/**
     * 更新任务间隔（外部调用接口）
     *//*

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

    */
/**
     * 删除任务（外部调用接口）
     *//*

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
        }finally {
            if (task != null){
                removeTaskKey(task);
            }
        }
    }

    */
/**
     * 获取系统状态（监控接口）
     *//*

    public Map<String, Object> getSystemStatus() {
        Map<String, Object> status = new HashMap<>();

        try {
            // 统计数据库中的任务数量
            long totalTasks = instanceRepository.count();
            long runningTasks = instanceRepository.countByStatus(1);

            // 线程池状态
            int activeThreads = taskExecutor.getActiveCount();
            int queueSize = taskExecutor.getQueue().size();
            int poolSize = taskExecutor.getPoolSize();

            status.put("totalTasks", totalTasks);
            status.put("runningTasks", runningTasks);
            status.put("activeThreads", activeThreads);
            status.put("queueSize", queueSize);
            status.put("poolSize", poolSize);
            status.put("batchSize", BATCH_SIZE);
            status.put("running", running.get());

            log.debug("系统状态 - 总任务: {}, 运行中: {}, 活跃线程: {}, 队列: {}",
                    totalTasks, runningTasks, activeThreads, queueSize);

        } catch (Exception e) {
            log.error("获取系统状态失败", e);
        }

        return status;
    }

    @PreDestroy
    public void shutdown() {
        log.debug("正在关闭任务系统V2...");
        running.set(false);
        if (taskExecutor != null) {
            taskExecutor.shutdown();
            try {
                if (!taskExecutor.awaitTermination(30, TimeUnit.SECONDS)) {
                    taskExecutor.shutdownNow();
                }
            } catch (InterruptedException e) {
                taskExecutor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
        log.debug("任务系统V2关闭完成");
    }

    */
/**
     * 移除某个任务对应的占用 key
     * 在任务完成 / 删除任务 / 手动释放 时可调用
     *//*

    public void removeTaskKey(BootInstance task) {
        try {
            if (task == null) return;

            Tenant tenant = tenantRepository.findById(task.getTenantId()).orElse(null);
            if (tenant == null) return;
            String key = tenant.getTenancy() + "_" +
                    tenant.getRegion() + "_" +
                    task.getArchitecture();
            String existBootId = activeTaskKeyMap.get(key);
            if (existBootId != null && existBootId.equals(task.getBootId())) {
                activeTaskKeyMap.remove(key);
                log.debug("释放占用: Key={} -> TaskId={}", key, task.getBootId());
            } else {
                log.debug("Key {} 当前未被任务 {} 占用，无需释放", key, task.getBootId());
            }

        } catch (Exception e) {
            log.error("释放 key 失败", e);
        }
    }
}
*/
