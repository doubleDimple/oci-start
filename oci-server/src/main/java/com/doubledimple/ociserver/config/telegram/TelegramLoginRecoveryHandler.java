package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.TelegramLoginRecoveryService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.telegram.telegrambots.meta.api.objects.Message;
import org.telegram.telegrambots.meta.api.objects.User;

import java.time.Clock;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** Consumes recovery credentials before ordinary logging, pending input, or AI handling. */
@Component
@Slf4j
public class TelegramLoginRecoveryHandler {
    static final String COMMAND = "/unlock_login";
    static final String HELP = "请在当前绑定的 Telegram 私聊中，用一条消息发送以下四行：\n"
            + "/unlock_login\n网站用户名\n独立恢复码\n任意一个已录入的租户名称\n"
            + "请勿发送网站密码。恢复码仅用于解除本站登录封禁。";
    static final String SUCCESS = "本站登录封禁已解除，请返回网站重新登录。IP 封禁和敏感导出限制保持不变。";
    static final String REJECTED = "恢复验证未通过，请核对信息后重新发送。";
    static final String EXPIRED = "此恢复消息已失效，请重新发送一条消息。";
    static final String RATE_LIMITED = "恢复验证尝试过多，请稍后再试。";
    static final String UNAVAILABLE = "登录恢复暂时不可用，请稍后再试。";
    private static final long MAX_AGE_SECONDS = 300;
    private static final long MAX_FUTURE_SECONDS = 30;
    private static final int MAX_REMEMBERED_MESSAGES = 4096;

    private final SystemConfigService configs;
    private final TelegramLoginRecoveryService recovery;
    private final Clock clock;
    // Only IDs and expiry times; credentials never enter a cache or a log.
    private final Map<String, Long> seenMessages = new LinkedHashMap<>();

    @Autowired
    public TelegramLoginRecoveryHandler(SystemConfigService configs, TelegramLoginRecoveryService recovery) {
        this(configs, recovery, Clock.systemUTC());
    }

    TelegramLoginRecoveryHandler(SystemConfigService configs, TelegramLoginRecoveryService recovery, Clock clock) {
        this.configs = configs;
        this.recovery = recovery;
        this.clock = clock;
    }

    /** Catch malformed commands and an accidentally pasted recovery code as well. */
    public static boolean isRecoveryText(String text) {
        if (text == null) return false;
        int start = 0;
        while (start < text.length()
                && (Character.isWhitespace(text.charAt(start)) || Character.isSpaceChar(text.charAt(start)))) {
            start++;
        }
        return text.regionMatches(true, start, COMMAND, 0, COMMAND.length())
                || text.toUpperCase(Locale.ROOT).contains("LGR-");
    }

    public boolean handle(Message message, String currentBotToken, Messenger messenger) {
        if (message == null || !isRecoveryText(message.getText())) return false;
        boolean authorized = false;
        try {
            authorized = isBoundPrivateSender(message, currentBotToken);
            if (!authorized) return true;

            String text = message.getText();
            // Telegram deletion is best effort; never echo the incoming message or fields.
            if (!COMMAND.equals(text.trim()) && message.getMessageId() != null && message.getMessageId() > 0) {
                try {
                    messenger.delete(message.getChatId(), message.getMessageId());
                } catch (Exception exception) {
                    log.warn("Telegram recovery message deletion failed: {}", exception.getClass().getSimpleName());
                }
            }

            long now = clock.instant().getEpochSecond();
            if (message.getDate() == null || message.getDate() <= 0
                    || now - message.getDate().longValue() > MAX_AGE_SECONDS
                    || message.getDate().longValue() - now > MAX_FUTURE_SECONDS
                    || message.getForwardDate() != null || message.getEditDate() != null
                    || message.getMessageId() == null || message.getMessageId() <= 0) {
                reply(messenger, message.getChatId(), EXPIRED);
                return true;
            }
            if (!claimMessage(message, now)) return true;

            String[] lines = text.replace("\r\n", "\n").split("\n", -1);
            if (text.length() > 4096 || lines.length != 4 || !COMMAND.equals(lines[0].trim())
                    || !validLine(lines[1]) || !validLine(lines[2]) || !validLine(lines[3])) {
                reply(messenger, message.getChatId(), HELP);
                return true;
            }
            TelegramLoginRecoveryService.RecoveryResult result = recovery.recover(
                    message.getChatId(), message.getFrom().getId(), currentBotToken,
                    lines[1].trim(), lines[2].trim(), lines[3].trim());
            String response = result == TelegramLoginRecoveryService.RecoveryResult.SUCCESS ? SUCCESS
                    : result == TelegramLoginRecoveryService.RecoveryResult.RATE_LIMITED ? RATE_LIMITED
                    : result == TelegramLoginRecoveryService.RecoveryResult.REJECTED ? REJECTED : UNAVAILABLE;
            reply(messenger, message.getChatId(), response);
        } catch (Exception exception) {
            // Do not log exception messages/stack traces: downstream errors may contain credentials.
            log.warn("Telegram recovery handling failed: {}", exception.getClass().getSimpleName());
            if (authorized) reply(messenger, message.getChatId(), UNAVAILABLE);
        }
        return true;
    }

    private boolean isBoundPrivateSender(Message message, String currentBotToken) {
        User sender = message.getFrom();
        if (message.getChat() == null || !"private".equals(message.getChat().getType())
                || sender == null || !Boolean.FALSE.equals(sender.getIsBot())
                || sender.getId() == null || sender.getId() <= 0
                || message.getChatId() == null || !sender.getId().equals(message.getChatId())) return false;
        TelegramConfig config = configs.getTelegramConfig();
        if (config == null || !config.isEnabled() || currentBotToken == null || currentBotToken.isEmpty()
                || !currentBotToken.equals(config.getBotToken()) || config.getChatId() == null) return false;
        String chatId = config.getChatId().trim();
        if (!chatId.matches("[1-9][0-9]{0,18}")) return false;
        try {
            return Long.parseLong(chatId) == sender.getId();
        } catch (NumberFormatException exception) {
            return false;
        }
    }

    private synchronized boolean claimMessage(Message message, long now) {
        Iterator<Map.Entry<String, Long>> iterator = seenMessages.entrySet().iterator();
        while (iterator.hasNext()) {
            if (iterator.next().getValue() < now) iterator.remove();
        }
        String key = message.getChatId() + ":" + message.getMessageId();
        if (seenMessages.containsKey(key) || seenMessages.size() >= MAX_REMEMBERED_MESSAGES) return false;
        seenMessages.put(key, message.getDate().longValue() + MAX_AGE_SECONDS);
        return true;
    }

    private static boolean validLine(String line) {
        if (line.trim().isEmpty()) return false;
        for (int index = 0; index < line.length(); index++) {
            if (Character.isISOControl(line.charAt(index))) return false;
        }
        return true;
    }

    private static void reply(Messenger messenger, long chatId, String text) {
        try {
            messenger.reply(chatId, text);
        } catch (Exception exception) {
            log.warn("Telegram recovery reply failed: {}", exception.getClass().getSimpleName());
        }
    }

    public interface Messenger {
        void reply(long chatId, String text) throws Exception;
        void delete(long chatId, int messageId) throws Exception;
    }
}
