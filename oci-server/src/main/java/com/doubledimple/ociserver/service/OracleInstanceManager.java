package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.config.OracleUsersConfig;
import com.doubledimple.ociserver.domain.User;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.DependsOn;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.Map;
import java.util.concurrent.*;

/**
 * @author doubleDimple
 */
@Service
@Slf4j
@DependsOn("simpleAuthenticationDetailsProvider")
public class OracleInstanceManager {

    private final OracleCloudService oracleCloudService;
    private final OracleUsersConfig oracleUsersConfig;
    //ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(10);
    //private final ConcurrentHashMap<String, ScheduledFuture<?>> accountTasks = new ConcurrentHashMap<>();

    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(Runtime.getRuntime().availableProcessors());
    private final Map<String, CompletableFuture<Void>> accountTasks = new ConcurrentHashMap<>();

    @Autowired
    MessageService messageService;

    @Autowired
    public OracleInstanceManager(OracleCloudService oracleCloudService, OracleUsersConfig oracleUsersConfig) throws Exception{
        this.oracleCloudService = oracleCloudService;
        this.oracleUsersConfig = oracleUsersConfig;
    }

    @PostConstruct
    public void init() {
        Map<String, User> users = oracleUsersConfig.getUsers();
        for (User user : users.values()) {
            addUser2(user);
        }
    }

    /*public void addUser(User user) {
        if (!accountTasks.containsKey(user.getUserId())) {
            Runnable task = () -> {
                boolean isCreated = false;
                while (!isCreated) {
                    try {
                        // 尝试创建实例
                        isCreated = oracleCloudService.createInstanceData(user);
                    } catch (Exception e) {
                        if (e instanceof BmcException) {
                            BmcException bmcException = (BmcException) e;
                            String originalMessage = bmcException.getOriginalMessage();
                            String originalMessageTemplate = bmcException.getOriginalMessageTemplate();
                            String message = bmcException.getMessage();
                            log.info("originalMessage: " + originalMessage);
                            log.info("originalMessageTemplate: " + originalMessageTemplate);
                            log.info("message: " + message);
                        } else {
                            e.printStackTrace();
                            log.error("创建实例出现异常,原因为: [{}]", e.getMessage());
                        }
                    }

                    if (!isCreated) {
                        log.info("账户: [{}] 创建实例失败，[{}] 秒后重试", user.getUserName(), user.getInterval());
                        try {
                            TimeUnit.SECONDS.sleep(user.getInterval()); // 等待后重试
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                    } else {
                        sendNotification(user.getUserId(), "message");
                        removeUser(user.getUserId());
                    }
                }
            };

            // 使用调度器启动任务，立即开始执行
            ScheduledFuture<?> schedule = scheduler.schedule(task, 0, TimeUnit.SECONDS);
            accountTasks.put(user.getUserId(), schedule);
            System.out.println("启动账户 " + user.getUserId() + " 的任务，每隔 " + user.getInterval() + " 秒执行一次");
        }
    }*/


    public void removeUser(String userId) {
        CompletableFuture<Void> remove = accountTasks.remove(userId);
        if (remove != null) {
            remove.cancel(false);
            System.out.println("停止账户 " + userId + " 的任务");
        }
    }

    private void sendNotification(String userName, String message) {
        // 在这里实现发送到钉钉或 Telegram 的逻辑
        messageService.sendMessage("用户: "+userName+"===>"+message);
    }


    public void addUser2(User user) {
        if (!accountTasks.containsKey(user.getUserId())) {
            CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                while (true) {
                    boolean isCreated = false;
                    try {
                        isCreated = oracleCloudService.createInstanceData(user);
                    } catch (Exception e) {
                        handleException(user,e);
                    }

                    if (isCreated) {
                        sendNotification(user.getUserName(), "message");
                        break; // 成功时退出循环
                    } else {
                        log.info("账户: [{}] 创建实例失败，[{}] 秒后重试", user.getUserName(), user.getInterval());
                        try {
                            TimeUnit.SECONDS.sleep(user.getInterval());
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            break;
                        }
                    }
                }
            }, scheduler);

            accountTasks.put(user.getUserId(), future);
            log.info("账户 " + user.getUserName() + " 的任务，每隔 " + user.getInterval() + " 秒执行一次");
        }
    }

    private void handleException(User user,Exception e) {
        if (e instanceof BmcException) {
            BmcException bmcException = (BmcException) e;
            log.info("originalMessage: " + bmcException.getOriginalMessage());
            log.info("originalMessageTemplate: " + bmcException.getOriginalMessageTemplate());
            log.info("message: " + bmcException.getMessage());
            sendNotification(user.getUserName(), bmcException.getOriginalMessage());
        } else {
            log.error("创建实例出现异常,原因为: [{}]", e.getMessage());
        }
    }
}
