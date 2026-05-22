package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.dao.entity.TelegramUser;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Service;
import org.telegram.telegrambots.bots.DefaultBotOptions;
import org.telegram.telegrambots.meta.TelegramBotsApi;
import org.telegram.telegrambots.updatesreceivers.DefaultBotSession;

import javax.annotation.Resource;

@Service
@Slf4j
public class TelegramBotService implements InitializingBean {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private TelegramUserService telegramUserService;

    @Resource
    private TelegramBotConfig telegramBotConfig;

    @Resource
    private ApplicationContext applicationContext;

    private TelegramBotCus telegramBot;

    private TelegramBotsApi botsApi;
    private boolean isBotRegistered = false;

    // 重试相关参数
    private int maxRetryAttempts = 3;
    private int currentRetryCount = 0;
    private long retryIntervalMs = 30000;

    public DefaultBotSession getBotSession() {
        return telegramBotConfig.getBotSession();
    }

    /**
     * 启动机器人
     */
    public synchronized boolean startBot() {
        try {

            telegramBotConfig.registerTelegramBot();

            if (isBotRegistered) {
                log.info("机器人已注册，开始重新启动");
            }

            TelegramConfig telegramConfig = systemConfigService.getTelegramConfig();
            if (!telegramConfig.isEnabled() ||
                    StringUtils.isEmpty(telegramConfig.getBotToken()) ||
                    StringUtils.isEmpty(telegramConfig.getChatId())) {
                log.warn("Telegram配置无效，无法启动机器人");
                return false;
            }
            TelegramUser userById = telegramUserService.getUserById();
            String userName = "OCI-START_BOT";
            if (userById != null){
                userName = userById.getUsername();
            }
            telegramBot.setBotId(Long.valueOf(telegramConfig.getChatId()));
            telegramBot.setBotToken(telegramConfig.getBotToken());
            telegramBot.setBotUsername(userName);
            // 创建API实例并注册
            botsApi = telegramBotConfig.getBotsApi();
            if (botsApi == null) {
                botsApi = new TelegramBotsApi(DefaultBotSession.class);
                DefaultBotSession botSession = (DefaultBotSession)botsApi.registerBot(telegramBot);
                telegramBotConfig.setBotSession(botSession);
            }
            isBotRegistered = true;
            currentRetryCount = 0;

            log.info("Telegram机器人注册成功");

            // 异步发送欢迎消息
            new Thread(() -> {
                try {
                    Thread.sleep(2000);
                    telegramBot.sendWelcomeMessageAfterStartup();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }).start();

            return true;

        } catch (Exception e) {
            log.error("注册Telegram机器人失败 (第{}次尝试): {}", currentRetryCount + 1, e.getMessage());

            currentRetryCount++;
            isBotRegistered = false;

            if (currentRetryCount < maxRetryAttempts) {
                log.info("将在{}秒后进行第{}次重试", retryIntervalMs / 1000, currentRetryCount + 1);
                scheduleRetry();
            } else {
                log.error("Telegram机器人注册失败，已达到最大重试次数({}次)", maxRetryAttempts);
                currentRetryCount = 0;
            }

            return false;
        }
    }

    /**
     * 计划重试
     */
    private void scheduleRetry() {
        new Thread(() -> {
            try {
                Thread.sleep(retryIntervalMs);
                log.info("开始第{}次重试注册Telegram机器人", currentRetryCount + 1);
                startBot();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("重试被中断");
            }
        }).start();
    }

    @Override
    public void afterPropertiesSet() throws Exception {
        DefaultBotOptions defaultBotOptions = telegramBotConfig.botOptions();
        telegramBot = new TelegramBotCus(defaultBotOptions);
        telegramBot.setApplicationContext(applicationContext);
    }
}
