package com.doubledimple.ociserver.service.message;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.springframework.test.util.ReflectionTestUtils;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Exercises the real fanout, replacing only outbound transports and the other channel clients. */
/*class LoginLockNotificationFanoutTest {
    private static final String MESSAGE = "private lock: 100 hours; recovery 2026-10-28T19:59:30Z; backup before deleting";
    private static final String PROVIDER_DETAIL = "private notification provider token/body";

    enum Failure { NONE, TELEGRAM_CONFIG, TELEGRAM_SEND, DING, BARK_CONFIG, BARK_SEND, FEISHU }

    @ParameterizedTest
    @EnumSource(Failure.class)
    void eachChannelIsAttemptedOnceAndOneFailureCannotStopTheRemainingChannels(Failure failure) {
        RecordingTelegram sender = new RecordingTelegram(failure);
        DingDingMessageService ding = mock(DingDingMessageService.class);
        FeishuService feishu = mock(FeishuService.class);
        ReflectionTestUtils.setField(sender, "dingDingMessageService", ding);
        ReflectionTestUtils.setField(sender, "feishuService", feishu);
        if (failure == Failure.DING) doThrow(new IllegalStateException(PROVIDER_DETAIL)).when(ding).sendMessageTemplate(MESSAGE);
        if (failure == Failure.FEISHU) doThrow(new IllegalStateException(PROVIDER_DETAIL)).when(feishu).sendMessageTemplate(MESSAGE);
        Logger logger = (Logger) LoggerFactory.getLogger(TelegramMessageService.class);
        ListAppender<ILoggingEvent> logs = new ListAppender<>();
        logs.start();
        logger.addAppender(logs);
        try {
            assertDoesNotThrow(() -> sender.sendMessageTemplateText(MESSAGE, Boolean.FALSE));

            assertEquals(failure == Failure.TELEGRAM_CONFIG ? 0 : 1, sender.telegramRequests.size());
            assertEquals(failure == Failure.BARK_CONFIG ? 0 : 1, sender.barkMessages.size());
            if (!sender.telegramRequests.isEmpty()) {
                assertTrue(URLDecoder.decode(sender.telegramRequests.get(0), StandardCharsets.UTF_8).contains(MESSAGE));
            }
            if (!sender.barkMessages.isEmpty()) assertEquals(MESSAGE, sender.barkMessages.get(0));
            verify(ding).sendMessageTemplate(MESSAGE);
            verify(feishu).sendMessageTemplate(MESSAGE);
            verifyNoMoreInteractions(ding, feishu);
            for (ILoggingEvent log : logs.list) {
                assertFalse(log.getFormattedMessage().contains(MESSAGE));
                assertFalse(log.getFormattedMessage().contains(PROVIDER_DETAIL));
                assertNull(log.getThrowableProxy(), "Provider exceptions may contain the private notification");
            }
        } finally {
            logger.detachAppender(logs);
            logs.stop();
        }
    }

    @ParameterizedTest
    @ValueSource(strings = {"disabled", "absent", "empty-credential", "empty-destination"})
    void disabledOrIncompleteTelegramAndBarkConfigurationsNeverReachTheirTransports(String setting) {
        RecordingTelegram sender = new RecordingTelegram(Failure.NONE);
        if ("disabled".equals(setting)) {
            sender.telegram.setEnabled(false);
            sender.bark.setEnabled(false);
        } else if ("absent".equals(setting)) {
            sender.telegram = null;
            sender.bark = null;
        } else if ("empty-credential".equals(setting)) {
            sender.telegram.setBotToken(" ");
            sender.bark.setDeviceKey(" ");
        } else {
            sender.telegram.setChatId("");
            sender.bark.setUrl("");
        }
        DingDingMessageService ding = mock(DingDingMessageService.class);
        FeishuService feishu = mock(FeishuService.class);
        ReflectionTestUtils.setField(sender, "dingDingMessageService", ding);
        ReflectionTestUtils.setField(sender, "feishuService", feishu);

        assertDoesNotThrow(() -> sender.sendMessageTemplateText(MESSAGE, Boolean.FALSE));

        assertTrue(sender.telegramRequests.isEmpty());
        assertTrue(sender.barkMessages.isEmpty());
        verify(ding).sendMessageTemplate(MESSAGE);
        verify(feishu).sendMessageTemplate(MESSAGE);
        verifyNoMoreInteractions(ding, feishu);
    }

    @ParameterizedTest
    @ValueSource(strings = {"allowed", "disabled", "changed-chat", "changed-token", "group-chat", "missing-hash", "provider-failure", "config-failure"})
    void recoverySecretsOnlyReachTheStillBoundPrivateTransportAndNeverFanOut(String setting) throws Exception {
        RecordingTelegram sender = new RecordingTelegram("provider-failure".equals(setting) ? Failure.TELEGRAM_SEND
                : "config-failure".equals(setting) ? Failure.TELEGRAM_CONFIG : Failure.NONE);
        sender.telegram.setChatId("1234567");
        StringBuilder hash = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest("fixture-token".getBytes(StandardCharsets.UTF_8))) {
            hash.append(String.format("%02x", value & 255));
        }
        String expectedHash = "missing-hash".equals(setting) ? null : hash.toString();
        if ("disabled".equals(setting)) sender.telegram.setEnabled(false);
        if ("changed-chat".equals(setting)) sender.telegram.setChatId("7654321");
        if ("changed-token".equals(setting)) sender.telegram.setBotToken("replacement-token");
        if ("group-chat".equals(setting)) sender.telegram.setChatId("-1234567");
        DingDingMessageService ding = mock(DingDingMessageService.class);
        FeishuService feishu = mock(FeishuService.class);
        ReflectionTestUtils.setField(sender, "dingDingMessageService", ding);
        ReflectionTestUtils.setField(sender, "feishuService", feishu);
        Logger logger = (Logger) LoggerFactory.getLogger(TelegramMessageService.class);
        ListAppender<ILoggingEvent> logs = new ListAppender<>();
        logs.start();
        logger.addAppender(logs);
        String privateMessage = "LGR-private-one-time-recovery-code";
        try {
            assertDoesNotThrow(() -> sender.sendPrivateRecoveryMessage(privateMessage, 1234567L, expectedHash));

            assertEquals("allowed".equals(setting) || "provider-failure".equals(setting) ? 1 : 0, sender.privateMessages.size());
            if (!sender.privateMessages.isEmpty()) assertEquals(privateMessage, sender.privateMessages.get(0));
            assertTrue(sender.telegramRequests.isEmpty(), "A recovery code must not use the normal GET notification URL");
            assertTrue(sender.barkMessages.isEmpty());
            verifyNoInteractions(ding, feishu);
            for (ILoggingEvent log : logs.list) {
                assertFalse(log.getFormattedMessage().contains(privateMessage));
                assertFalse(log.getFormattedMessage().contains(PROVIDER_DETAIL));
                assertNull(log.getThrowableProxy());
            }
        } finally {
            logger.detachAppender(logs);
            logs.stop();
        }
    }

    private static final class RecordingTelegram extends TelegramMessageService {
        private final Failure failure;
        private TelegramConfig telegram = new TelegramConfig();
        private BarkConfig bark = new BarkConfig();
        private final List<String> telegramRequests = new ArrayList<>();
        private final List<String> barkMessages = new ArrayList<>();
        private final List<String> privateMessages = new ArrayList<>();

        private RecordingTelegram(Failure failure) {
            this.failure = failure;
            telegram.setEnabled(true);
            telegram.setBotToken("fixture-token");
            telegram.setChatId("fixture-chat");
            bark.setEnabled(true);
            bark.setUrl("https://bark.invalid");
            bark.setDeviceKey("fixture-key");
        }

        @Override public TelegramConfig getTelegramConfig() {
            if (failure == Failure.TELEGRAM_CONFIG) throw new IllegalStateException(PROVIDER_DETAIL);
            return telegram;
        }

        @Override public BarkConfig getBarkConfig() {
            if (failure == Failure.BARK_CONFIG) throw new IllegalStateException(PROVIDER_DETAIL);
            return bark;
        }

        @Override protected void sendTelegramRequest(String url, String mode) {
            telegramRequests.add(url);
            assertEquals("HTML", mode);
            if (failure == Failure.TELEGRAM_SEND) throw new IllegalStateException(PROVIDER_DETAIL);
        }

        @Override protected void sendBarkRequest(BarkConfig config, String message) {
            assertSame(bark, config);
            barkMessages.add(message);
            if (failure == Failure.BARK_SEND) throw new IllegalStateException(PROVIDER_DETAIL);
        }

        @Override protected void sendPrivateTelegramRequest(String botToken, long chatId, String message) {
            assertEquals("fixture-token", botToken);
            assertEquals(1234567L, chatId);
            privateMessages.add(message);
            if (failure == Failure.TELEGRAM_SEND) throw new IllegalStateException(PROVIDER_DETAIL);
        }
    }
}*/
