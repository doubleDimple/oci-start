package com.doubledimple.ociserver.config.telegram;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.TelegramLoginRecoveryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationContext;
import org.springframework.test.util.ReflectionTestUtils;
import org.telegram.telegrambots.meta.api.objects.CallbackQuery;
import org.telegram.telegrambots.meta.api.objects.Chat;
import org.telegram.telegrambots.meta.api.objects.Message;
import org.telegram.telegrambots.meta.api.objects.Update;
import org.telegram.telegrambots.meta.api.objects.User;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class TelegramLoginRecoveryHandlerTest {
    private static final long CHAT_ID = 42L;
    private static final String BOT_TOKEN = "123:fixture-token";
    private static final String CODE = "LGR-fixture-recovery-secret";
    private static final String USERNAME = "fixture-site-owner";
    private static final String TENANT = "Tenant With Spaces";
    private static final Instant NOW = Instant.parse("2026-10-24T12:00:00Z");
    private SystemConfigService configs;
    private TelegramLoginRecoveryService recovery;
    private TelegramLoginRecoveryHandler handler;
    private TelegramLoginRecoveryHandler.Messenger messenger;
    private TelegramConfig config;

    @BeforeEach
    void setup() {
        configs = mock(SystemConfigService.class);
        recovery = mock(TelegramLoginRecoveryService.class);
        messenger = mock(TelegramLoginRecoveryHandler.Messenger.class);
        config = new TelegramConfig();
        config.setEnabled(true);
        config.setChatId(String.valueOf(CHAT_ID));
        config.setBotToken(BOT_TOKEN);
        when(configs.getTelegramConfig()).thenReturn(config);
        when(recovery.recover(anyLong(), anyLong(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(TelegramLoginRecoveryService.RecoveryResult.SUCCESS);
        handler = new TelegramLoginRecoveryHandler(configs, recovery, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void boundPrivateSenderRecoversWithoutTelegramUserTableAndPreservesTenantSpaces() throws Exception {
        Message message = message("/unlock_login\r\n  " + USERNAME + "  \r\n " + CODE + " \r\n " + TENANT + " ");
        assertTrue(handler.handle(message, BOT_TOKEN, messenger));
        verify(recovery).recover(CHAT_ID, CHAT_ID, BOT_TOKEN, USERNAME, CODE, TENANT);
        verify(messenger).delete(CHAT_ID, message.getMessageId());
        verify(messenger).reply(CHAT_ID, TelegramLoginRecoveryHandler.SUCCESS);
        verifyNoMoreInteractions(recovery, messenger);
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "-42", "0", "43", "group", "9999999999999999999"})
    void absentInvalidOrDifferentConfiguredPrivateChatIsSilentlyRejected(String chatId) {
        config.setChatId(chatId);
        assertTrue(handler.handle(message(validText()), BOT_TOKEN, messenger));
        verifyNoInteractions(recovery, messenger);
    }

    @ParameterizedTest
    @ValueSource(strings = {"disabled", "stale-token", "empty-token", "group", "other-sender", "bot", "unknown-bot", "missing-sender", "missing-chat"})
    void refusesUnboundOrNonPrivateMessagesWithoutRepliesOrDeletion(String scenario) {
        Message message = message(validText());
        String token = BOT_TOKEN;
        switch (scenario) {
            case "disabled": config.setEnabled(false); break;
            case "stale-token": token = "old-token"; break;
            case "empty-token": token = ""; break;
            case "group": message.getChat().setType("supergroup"); break;
            case "other-sender": message.getFrom().setId(43L); break;
            case "bot": message.getFrom().setIsBot(true); break;
            case "unknown-bot":
                User unknownSender = mock(User.class);
                when(unknownSender.getId()).thenReturn(CHAT_ID);
                when(unknownSender.getIsBot()).thenReturn(null);
                message.setFrom(unknownSender);
                break;
            case "missing-sender": message.setFrom(null); break;
            case "missing-chat": message.setChat(null); break;
            default: fail("Missing scenario");
        }
        assertTrue(handler.handle(message, token, messenger));
        verifyNoInteractions(recovery, messenger);
    }

    @ParameterizedTest
    @ValueSource(strings = {"/unlock_login", "/unlock_loginBAD\nowner\nLGR-secret\ntenant", "/UNLOCK_LOGIN\nowner\nLGR-secret\ntenant", "/unlock_login@other_bot\nowner\nLGR-secret\ntenant", "/unlock_login\nowner\nLGR-secret", "/unlock_login\nowner\nLGR-secret\ntenant\nextra", "/unlock_login\nowner\n \ntenant", "LGR-accidentally-pasted-code", "Please use lgr-accidentally-pasted-code", "\u3000/unlock_login"})
    void malformedOrAccidentallyPastedRecoveryInputIsConsumedWithFixedHelp(String text) throws Exception {
        assertTrue(handler.handle(message(text), BOT_TOKEN, messenger));
        verifyNoInteractions(recovery);
        verify(messenger).reply(CHAT_ID, TelegramLoginRecoveryHandler.HELP);
    }

    @ParameterizedTest
    @ValueSource(strings = {"stale", "future", "missing-date", "forwarded", "edited", "missing-message-id"})
    void staleForwardedEditedAndInvalidUpdatesNeverReachRecoveryService(String scenario) throws Exception {
        Message message = message(validText());
        switch (scenario) {
            case "stale": message.setDate((int) NOW.getEpochSecond() - 301); break;
            case "future": message.setDate((int) NOW.getEpochSecond() + 31); break;
            case "missing-date": message.setDate(null); break;
            case "forwarded": message.setForwardDate((int) NOW.getEpochSecond()); break;
            case "edited": message.setEditDate((int) NOW.getEpochSecond()); break;
            case "missing-message-id": message.setMessageId(null); break;
            default: fail("Missing scenario");
        }
        assertTrue(handler.handle(message, BOT_TOKEN, messenger));
        verifyNoInteractions(recovery);
        verify(messenger).reply(CHAT_ID, TelegramLoginRecoveryHandler.EXPIRED);
    }

    @Test
    void duplicateDeliveryCannotConsumeAnotherAttemptButANewMessageCan() {
        when(recovery.recover(anyLong(), anyLong(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(TelegramLoginRecoveryService.RecoveryResult.REJECTED);
        Message message = message(validText());
        assertTrue(handler.handle(message, BOT_TOKEN, messenger));
        assertTrue(handler.handle(message, BOT_TOKEN, messenger));
        verify(recovery, times(1)).recover(CHAT_ID, CHAT_ID, BOT_TOKEN, USERNAME, CODE, TENANT);
        message.setMessageId(8);
        assertTrue(handler.handle(message, BOT_TOKEN, messenger));
        verify(recovery, times(2)).recover(CHAT_ID, CHAT_ID, BOT_TOKEN, USERNAME, CODE, TENANT);
    }

    @Test
    void rechecksCurrentBindingOnEveryMessage() {
        assertTrue(handler.handle(message(validText()), BOT_TOKEN, messenger));
        config.setChatId("43");
        Message next = message(validText());
        next.setMessageId(8);
        assertTrue(handler.handle(next, BOT_TOKEN, messenger));
        verify(recovery, times(1)).recover(CHAT_ID, CHAT_ID, BOT_TOKEN, USERNAME, CODE, TENANT);
    }

    @ParameterizedTest
    @EnumSource(TelegramLoginRecoveryService.RecoveryResult.class)
    void resultMessagesAreFixedAndNeverEchoFields(TelegramLoginRecoveryService.RecoveryResult result) throws Exception {
        when(recovery.recover(anyLong(), anyLong(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(result);
        assertTrue(handler.handle(message(validText()), BOT_TOKEN, messenger));
        String expected = result == TelegramLoginRecoveryService.RecoveryResult.SUCCESS ? TelegramLoginRecoveryHandler.SUCCESS
                : result == TelegramLoginRecoveryService.RecoveryResult.REJECTED ? TelegramLoginRecoveryHandler.REJECTED
                : result == TelegramLoginRecoveryService.RecoveryResult.RATE_LIMITED ? TelegramLoginRecoveryHandler.RATE_LIMITED
                : TelegramLoginRecoveryHandler.UNAVAILABLE;
        verify(messenger).reply(CHAT_ID, expected);
        assertFalse(expected.contains(USERNAME));
        assertFalse(expected.contains(CODE));
        assertFalse(expected.contains(TENANT));
    }

    @Test
    void deletionAndDeliveryFailuresAreContainedAndSecretsAreAbsentFromLogs() throws Exception {
        Logger logger = (Logger) LoggerFactory.getLogger(TelegramLoginRecoveryHandler.class);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        try {
            String secretError = USERNAME + " " + CODE + " " + TENANT;
            doThrow(new IllegalStateException(secretError)).when(messenger).delete(anyLong(), anyInt());
            when(recovery.recover(anyLong(), anyLong(), anyString(), anyString(), anyString(), anyString()))
                    .thenThrow(new IllegalArgumentException(secretError));
            doThrow(new IllegalStateException(secretError)).when(messenger).reply(anyLong(), anyString());
            assertTrue(handler.handle(message(validText()), BOT_TOKEN, messenger));
            verify(recovery).recover(CHAT_ID, CHAT_ID, BOT_TOKEN, USERNAME, CODE, TENANT);
            verify(messenger).reply(CHAT_ID, TelegramLoginRecoveryHandler.UNAVAILABLE);
            assertEquals(3, appender.list.size());
            for (ILoggingEvent event : appender.list) {
                assertFalse(event.getFormattedMessage().contains(CODE));
                assertFalse(event.getFormattedMessage().contains(USERNAME));
                assertFalse(event.getFormattedMessage().contains(TENANT));
                assertNull(event.getThrowableProxy());
            }
        } finally {
            logger.detachAppender(appender);
            appender.stop();
        }
    }

    @Test
    void unavailableBindingFailsClosedWithoutNotifyingUnknownSender() {
        when(configs.getTelegramConfig()).thenThrow(new IllegalStateException(CODE));
        assertTrue(handler.handle(message(validText()), BOT_TOKEN, messenger));
        verifyNoInteractions(recovery, messenger);
    }

    @Test
    void unrelatedTextIsLeftToTheExistingBot() {
        assertFalse(handler.handle(message("/menu"), BOT_TOKEN, messenger));
        assertFalse(TelegramLoginRecoveryHandler.isRecoveryText(null));
        verifyNoInteractions(configs, recovery, messenger);
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void botDispatchStopsBeforeRawLoggingPendingBootAndAiEvenWhenHandlerFails(boolean fails) {
        ApplicationContext context = mock(ApplicationContext.class);
        TelegramLoginRecoveryHandler recoveryHandler = mock(TelegramLoginRecoveryHandler.class);
        when(context.getBean(TelegramLoginRecoveryHandler.class)).thenReturn(recoveryHandler);
        if (fails) when(recoveryHandler.handle(any(), anyString(), any())).thenThrow(new IllegalStateException(CODE));
        TelegramBotCus bot = mock(TelegramBotCus.class, CALLS_REAL_METHODS);
        bot.setApplicationContext(context);
        bot.setBotToken(BOT_TOKEN);
        Map<Long, Object> pending = new ConcurrentHashMap<>();
        Object originalPending = new Object();
        pending.put(CHAT_ID, originalPending);
        ReflectionTestUtils.setField(bot, "pendingBootInputs", pending);
        Logger logger = (Logger) LoggerFactory.getLogger(TelegramBotCus.class);
        Level oldLevel = logger.getLevel();
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        logger.setLevel(Level.DEBUG);
        try {
            Update update = new Update();
            Message message = message(validText());
            update.setMessage(message);
            bot.onUpdateReceived(update);
            verify(recoveryHandler).handle(eq(message), eq(BOT_TOKEN), any());
            verify(context).getBean(TelegramLoginRecoveryHandler.class);
            verifyNoMoreInteractions(context);
            assertSame(originalPending, pending.get(CHAT_ID));
            for (ILoggingEvent event : appender.list) {
                assertFalse(event.getFormattedMessage().contains(CODE));
                assertNull(event.getThrowableProxy());
            }
        } finally {
            logger.setLevel(oldLevel);
            logger.detachAppender(appender);
            appender.stop();
        }
    }

    @Test
    void editedMessagesAndCallbackDataCannotInvokeRecoveryOrGenericHandlers() {
        ApplicationContext context = mock(ApplicationContext.class);
        TelegramBotCus bot = mock(TelegramBotCus.class, CALLS_REAL_METHODS);
        bot.setApplicationContext(context);
        Update edited = new Update();
        edited.setEditedMessage(message(validText()));
        bot.onUpdateReceived(edited);
        Update callback = new Update();
        CallbackQuery query = new CallbackQuery();
        query.setData(CODE);
        callback.setCallbackQuery(query);
        bot.onUpdateReceived(callback);
        verifyNoInteractions(context);
    }

    @Test
    void missingRecoveryBeanConsumesEvenAnAccidentallyPastedCodeWithoutFallback() {
        ApplicationContext context = mock(ApplicationContext.class);
        when(context.getBean(TelegramLoginRecoveryHandler.class)).thenThrow(new IllegalStateException(CODE));
        TelegramBotCus bot = mock(TelegramBotCus.class, CALLS_REAL_METHODS);
        bot.setApplicationContext(context);
        Update update = new Update();
        update.setMessage(message(CODE));
        assertDoesNotThrow(() -> bot.onUpdateReceived(update));
        verify(context).getBean(TelegramLoginRecoveryHandler.class);
        verifyNoMoreInteractions(context);
    }

    private static String validText() {
        return "/unlock_login\n" + USERNAME + "\n" + CODE + "\n" + TENANT;
    }

    private static Message message(String text) {
        Chat chat = new Chat();
        chat.setId(CHAT_ID);
        chat.setType("private");
        User sender = new User();
        sender.setId(CHAT_ID);
        sender.setIsBot(false);
        Message message = new Message();
        message.setChat(chat);
        message.setFrom(sender);
        message.setMessageId(7);
        message.setDate((int) NOW.getEpochSecond());
        message.setText(text);
        return message;
    }
}
