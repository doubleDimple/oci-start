package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.config.OracleUsersConfig;
import com.doubledimple.ociserver.domain.User;
import com.doubledimple.ociserver.enums.MessageEnum;
import com.doubledimple.ociserver.message.factory.MessageFactory;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.DependsOn;
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
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(Runtime.getRuntime().availableProcessors());
    private final Map<String, CompletableFuture<Void>> accountTasks = new ConcurrentHashMap<>();

    @Autowired
    MessageFactory messageFactory;

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


    public void removeUser(String userId) {
        CompletableFuture<Void> remove = accountTasks.remove(userId);
        if (remove != null) {
            remove.cancel(false);
            System.out.println("停止账户 " + userId + " 的任务");
        }
    }

    private void sendNotification(String userName, String message) {
        messageFactory.getType(MessageEnum.TELEGRAM).sendMessage("用户: "+userName+"===>"+message);
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
