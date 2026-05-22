package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.ociserver.pojo.request.ProxyConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.apache.http.client.config.RequestConfig;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.telegram.telegrambots.bots.DefaultBotOptions;
import org.telegram.telegrambots.meta.TelegramBotsApi;
import org.telegram.telegrambots.meta.generics.BotSession;
import org.telegram.telegrambots.updatesreceivers.DefaultBotSession;

import javax.annotation.Resource;
import java.util.concurrent.CompletableFuture;

/**
 * @version 1.0.0
 *
 */
@Configuration
@Slf4j
public class TelegramBotConfig {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private ApplicationContext applicationContext;

    private TelegramBotsApi botsApi;
    private TelegramBotCus currentBot;

    private DefaultBotSession botSession;
    private volatile boolean botRunning = false;

    public DefaultBotSession getBotSession() {
        return botSession;
    }
    public void setBotSession(DefaultBotSession botSession) {
        this.botSession = botSession;
    }
    public TelegramBotsApi getBotsApi() {
        return botsApi;
    }

    public void setBotsApi(TelegramBotsApi botsApi) {
        this.botsApi = botsApi;
    }

    /**
     * 停止机器人
     */
    public void stopBot() {
        try {
            if (botSession != null && botSession.isRunning()){
                botSession.stop();
            }
            // 关闭bot会话
            if (currentBot != null){
                currentBot.clearWebhook();
            }


            // 清理资源
            botsApi = null;
            currentBot = null;
            botRunning = false;
            botSession = null;
            log.info("Telegram机器人已停止");

        } catch (Exception e) {
            log.warn("停止机器人时出错: {}", e.getMessage());
            botSession = null;
        }
    }

    /**
     * 配置机器人选项，根据配置启用代理
     */
    @Bean
    @Primary
    public DefaultBotOptions botOptions() {
        DefaultBotOptions options = new DefaultBotOptions();

        try {
            ProxyConfig proxyConfig = systemConfigService.getProxyConfig();

            options.setMaxThreads(3);

            // 正确设置超时参数 - 使用RequestConfig
            RequestConfig requestConfig = RequestConfig.custom()
                    .setConnectTimeout(15000)      // 连接超时15秒
                    .setSocketTimeout(30000)       // Socket读取超时30秒
                    .setConnectionRequestTimeout(10000) // 从连接池获取连接的超时时间
                    .build();
            options.setRequestConfig(requestConfig);

            // 设置获取更新的参数
            options.setGetUpdatesTimeout(30);     // 长轮询超时50秒
            options.setGetUpdatesLimit(100);      // 每次最多获取100条更新

            // 设置Webhook连接数（如果使用webhook模式）
            options.setMaxWebhookConnections(40);

            // 配置代理
            if (proxyConfig.isEnabled() && StringUtils.isNotEmpty(proxyConfig.getHost())) {
                DefaultBotOptions.ProxyType type = DefaultBotOptions.ProxyType.valueOf(proxyConfig.getType());
                options.setProxyType(type);
                options.setProxyHost(proxyConfig.getHost());
                options.setProxyPort(proxyConfig.getPort());
                log.debug("已启用Telegram代理: {} {}:{}", proxyConfig.getType(), proxyConfig.getHost(), proxyConfig.getPort());
            } else {
                // 不使用代理
                options.setProxyType(DefaultBotOptions.ProxyType.NO_PROXY);
            }

        } catch (Exception e) {
            log.warn("获取代理配置失败，使用默认设置: {}", e.getMessage());

            // 默认配置
            options.setMaxThreads(3);
            options.setProxyType(DefaultBotOptions.ProxyType.NO_PROXY);

            // 设置默认的RequestConfig
            RequestConfig defaultConfig = RequestConfig.custom()
                    .setConnectTimeout(15000)
                    .setSocketTimeout(30000)
                    .setConnectionRequestTimeout(10000)
                    .build();
            options.setRequestConfig(defaultConfig);
        }

        return options;
    }

    /**
     * 检查Telegram配置是否有效
     */
    private boolean isTelegramConfigValid() {
        try {
            TelegramConfig config = systemConfigService.getTelegramConfig();
            return config.isEnabled() &&
                    StringUtils.isNotEmpty(config.getBotToken()) &&
                    StringUtils.isNotEmpty(config.getChatId());
        } catch (Exception e) {
            log.error("检查Telegram配置时出错: {}", e.getMessage());
            return false;
        }
    }

    public void startBot(){
        if (!isTelegramConfigValid()) {
            log.debug("Telegram配置未启用或配置不完整，跳过机器人注册");
            return;
        }
        try {
            // 获取配置
            TelegramConfig telegramConfig = systemConfigService.getTelegramConfig();
            DefaultBotOptions botOptions = botOptions();

            // 创建机器人实例
            TelegramBotCus bot = new TelegramBotCus(botOptions);
            bot.setApplicationContext(applicationContext);

            // 配置机器人参数
            String botToken = telegramConfig.getBotToken();
            String[] tokenParts = botToken.split(":");
            if (tokenParts.length >= 2) {
                try {
                    Long botId = Long.parseLong(tokenParts[0]);
                    bot.setBotId(botId);
                } catch (NumberFormatException e) {
                    log.warn("无法解析Bot ID: {}", tokenParts[0]);
                }
            }

            bot.setBotToken(botToken);
            bot.setBotUsername("OCI_START_Bot");

            log.debug("正在启动 Telegram 机器人...");
            log.debug("Bot Username: {}", bot.getBotUsername());
            log.debug("Bot Token: {}...", bot.getBotToken().substring(0, Math.min(5, bot.getBotToken().length())));

            // 创建并注册机器人
            registerBotWithRetry(bot);

        } catch (Exception e) {
            // 捕获所有其他异常，避免影响应用启动
            log.warn("注册Telegram机器人时发生未知错误，但不会影响应用启动: {}", e.getMessage());
        }

    }

    /**
     * 注册机器人到Telegram API
     */
    @Bean
    public CommandLineRunner registerTelegramBot() {
        return args -> {
            // 检查配置是否有效
            if (!isTelegramConfigValid()) {
                log.debug("Telegram配置未启用或配置不完整，跳过机器人注册");
                return;
            }

            try {
                // 获取配置
                TelegramConfig telegramConfig = systemConfigService.getTelegramConfig();
                DefaultBotOptions botOptions = botOptions();

                // 创建机器人实例
                TelegramBotCus bot = new TelegramBotCus(botOptions);
                bot.setApplicationContext(applicationContext);

                // 配置机器人参数
                String botToken = telegramConfig.getBotToken();
                String[] tokenParts = botToken.split(":");
                if (tokenParts.length >= 2) {
                    try {
                        Long botId = Long.parseLong(tokenParts[0]);
                        bot.setBotId(botId);
                    } catch (NumberFormatException e) {
                        log.warn("无法解析Bot ID: {}", tokenParts[0]);
                    }
                }

                bot.setBotToken(botToken);
                bot.setBotUsername("OCI_START_Bot");

                log.debug("正在启动 Telegram 机器人...");
                log.debug("Bot Username: {}", bot.getBotUsername());
                log.debug("Bot Token: {}...", bot.getBotToken().substring(0, Math.min(5, bot.getBotToken().length())));

                // 创建并注册机器人
                registerBotWithRetry(bot);

            } catch (Exception e) {
                log.warn("注册Telegram机器人时发生未知错误，但不会影响应用启动: {}", e.getMessage());
            }
        };
    }

    private void registerBotWithRetry(TelegramBotCus bot) {
        final int maxRetries = 3;
        final long retryDelay = 10000;

        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                TelegramBotsApi botsApi = new TelegramBotsApi(DefaultBotSession.class);
                botSession = (DefaultBotSession) botsApi.registerBot(bot);
                setBotsApi(botsApi);

                log.info("Telegram 机器人启动成功!");

                // 异步发送欢迎消息，避免阻塞启动流程
                CompletableFuture.runAsync(() -> {
                    try {
                        Thread.sleep(2000);
                        bot.sendWelcomeMessageAfterStartup();
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    } catch (Exception e) {
                        log.warn("发送欢迎消息失败: {}", e.getMessage());
                    }
                });

                return;

            } catch (Exception e) {
                String errorMsg = e.getMessage();

                // 根据错误类型进行不同处理
                if (isNetworkConnectionError(errorMsg)) {
                    log.warn("第{}次尝试: 网络连接失败 - {}", attempt, errorMsg);

                    if (attempt < maxRetries) {
                        log.info("将在{}秒后进行第{}次重试", retryDelay / 1000, attempt + 1);
                        try {
                            Thread.sleep(retryDelay);
                        } catch (InterruptedException ie) {
                            Thread.currentThread().interrupt();
                            log.warn("重试被中断");
                            return;
                        }
                    } else {
                        log.warn("Telegram 机器人启动失败: 已达到最大重试次数({}次)，但应用将继续运行", maxRetries);
                    }
                } else {
                    // 非网络错误，记录详细信息但不重试
                    log.warn("Telegram 机器人启动失败 - 配置或认证错误: {}", errorMsg);
                    logDetailedError(e);
                    return;
                }
            }
        }
    }

    private boolean isNetworkConnectionError(String errorMessage) {
        if (errorMessage == null) return false;

        String lowerMsg = errorMessage.toLowerCase();
        return lowerMsg.contains("connection refused") ||
                lowerMsg.contains("timeout") ||
                lowerMsg.contains("connect to") ||
                lowerMsg.contains("network") ||
                lowerMsg.contains("unreachable");
    }

    /**
     * 记录详细错误信息
     */
    private void logDetailedError(Exception e) {
        Throwable cause = e.getCause();
        while (cause != null) {
            log.warn("错误原因: {}", cause.getMessage());
            cause = cause.getCause();
        }
        if (e.getMessage() != null && e.getMessage().toLowerCase().contains("proxy")) {
            log.warn("可能是代理配置问题，请检查代理设置");
        }
    }

    public void reStart() {
        stopBot();
        registerTelegramBot();
    }
}
