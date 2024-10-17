package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.config.OracleUsersConfig;
import com.doubledimple.ociserver.domain.OracleInstanceDetail;
import com.doubledimple.ociserver.domain.User;
import com.doubledimple.ociserver.enums.MessageEnum;
import com.doubledimple.ociserver.exception.OciException;
import com.doubledimple.ociserver.message.factory.MessageFactory;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.DependsOn;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.Map;
import java.util.concurrent.*;

import static com.doubledimple.ociserver.exception.ErrorCode.LIMIT_EXCEEDED;

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
    public OracleInstanceManager(OracleCloudService oracleCloudService, OracleUsersConfig oracleUsersConfig) throws Exception {
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

    private void sendNotification(String userName, OracleInstanceDetail instanceData) {
        instanceData.setUserName(userName);
        messageFactory.getType(MessageEnum.TELEGRAM).sendMessage(instanceData);
    }


    public void addUser2(User user) {
        if (!accountTasks.containsKey(user.getUserName())) {
            CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                while (true) {
                    OracleInstanceDetail instanceData = null;
                    try {
                        instanceData = oracleCloudService.createInstanceData(user);
                    } catch (Exception e) {
                        if (e instanceof OciException) {
                            OciException error = (OciException) e;
                            if (error.getCode() == 400 && error.getMessage().equals(LIMIT_EXCEEDED.getMessage())) {
                                handleException(user, error);
                                break;
                            }
                        }
                    }
                    if (null != instanceData && null != instanceData.getPublicIp()) {
                        sendNotification(user.getUserName(), instanceData);
                        break; // 成功时退出循环
                    } else {
                        log.info("租户: [{}] 创建实例失败，[{}] 秒后重试", user.getUserName(), user.getInterval());
                        try {
                            TimeUnit.SECONDS.sleep(user.getInterval());
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            break;
                        }
                    }
                }
            }, scheduler);

            accountTasks.put(user.getUserName(), future);
            log.info("租户 " + user.getUserName() + " 的任务，每隔 " + user.getInterval() + " 秒执行一次");
        }
    }

    private void handleException(User user, Exception e) {
        if (e instanceof BmcException) {
            BmcException bmcException = (BmcException) e;
            log.info("originalMessage: " + bmcException.getOriginalMessage());
            log.info("originalMessageTemplate: " + bmcException.getOriginalMessageTemplate());
            log.info("message: " + bmcException.getMessage());
            sendErrorMessage(user.getUserName(), bmcException.getServiceCode());
        } else {
            log.error("创建实例出现异常,原因为: [{}]", e.getMessage());
            sendErrorMessage(user.getUserName(), e.getMessage());
        }
    }

    private void sendErrorMessage(String userName, String originalMessage) {
        messageFactory.getType(MessageEnum.TELEGRAM).sendErrorMessage("用户: " + userName + "===>" + " " + originalMessage);
    }
}
