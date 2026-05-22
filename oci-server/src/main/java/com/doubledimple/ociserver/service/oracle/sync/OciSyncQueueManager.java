package com.doubledimple.ociserver.service.oracle.sync;

import com.doubledimple.dao.entity.Tenant;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * @version 1.0.0
 * @ClassName OciSyncQueueManager
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-13 11:30
 */
@Component
@Slf4j
public class OciSyncQueueManager {

    @Resource
    private ThreadPoolExecutor executor;

    @Resource
    OciSyncService ociSyncService;

    // 创建有界阻塞队列
    private final BlockingQueue<Tenant> syncQueue = new LinkedBlockingQueue<>(500);

    // 控制线程运行状态
    private volatile boolean running = true;

    @PostConstruct
    public void init() {
        log.debug("OCI同步队列管理器初始化...");
        // 启动消费者线程
        startConsumers();
    }

    /**
     * 将租户同步任务提交到队列
     */
    public boolean submitSyncTask(Tenant tenant) {
        try {
            boolean added = syncQueue.offer(tenant, 2, TimeUnit.SECONDS);
            if (added) {
                log.info("已将租户[{}]同步任务添加到队列", tenant.getId());
            } else {
                log.warn("队列已满，无法添加租户[{}]同步任务", tenant.getId());
            }
            return added;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("提交同步任务被中断", e);
            return false;
        }
    }

    /**
     * 批量提交租户同步任务到队列
     */
    public int submitAllTenants(Iterable<Tenant> tenants) {
        int count = 0;
        for (Tenant tenant : tenants) {
            if (submitSyncTask(tenant)) {
                count++;
            }
        }
        log.info("已将{}个租户同步任务提交到队列", count);
        return count;
    }

    /**
     * 启动消费者线程处理队列
     */
    private void startConsumers() {
        // 创建多个消费者线程从队列取任务执行
        for (int i = 0; i < 5; i++) {
            final int consumerId = i;
            executor.execute(() -> {
                log.debug("OCI同步消费者线程-{}启动", consumerId);
                while (running) {
                    try {
                        // 从队列获取任务，最多等待5秒
                        Tenant tenant = syncQueue.poll(10, TimeUnit.SECONDS);
                        if (tenant != null) {
                            log.info("消费者-{}开始处理租户[{}]同步任务", consumerId, tenant.getId());
                            processTenantSync(tenant);
                        }
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        log.warn("消费者-{}被中断", consumerId);
                        break;
                    } catch (Exception e) {
                        log.error("消费者-{}处理同步任务时发生错误", consumerId, e);
                    }
                }
                log.debug("OCI同步消费者线程-{}退出", consumerId);
            });
        }
    }

    /**
     * 获取当前队列深度
     */
    public int getQueueDepth() {
        return syncQueue.size();
    }

    @PreDestroy
    public void shutdown() {
        log.debug("关闭OCI同步队列管理器...");
        running = false;
        executor.shutdown();
        try {
            // 等待任务完成
            if (!executor.awaitTermination(30, TimeUnit.SECONDS)) {
                executor.shutdownNow();
            }
        } catch (InterruptedException e) {
            executor.shutdownNow();
            Thread.currentThread().interrupt();
        }
        log.debug("OCI同步队列管理器已关闭");
    }

    public void processTenantSync(Tenant tenant) {
        ociSyncService.processTenantSync(tenant);
    }

}
