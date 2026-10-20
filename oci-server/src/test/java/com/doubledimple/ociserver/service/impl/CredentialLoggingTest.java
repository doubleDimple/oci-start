package com.doubledimple.ociserver.service.impl;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.ThrowableProxyUtil;
import ch.qos.logback.core.read.ListAppender;
import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.service.message.DingDingMessageService;
import com.doubledimple.ociserver.service.message.FeishuService;
import com.doubledimple.ociserver.service.message.MessageService;
import com.doubledimple.ociserver.service.message.TelegramMessageService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.slf4j.LoggerFactory;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class CredentialLoggingTest {
    private static final String USER = "logging-test-user";
    private static final String CODE = "947281";
    private final Logger logger = (Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME);
    private final ListAppender<ILoggingEvent> logs = new ListAppender<>();
    private Level oldLevel;
    private VerifyServiceImpl service;
    private MessageService notifications;
    private LoginUserService users;

    @BeforeEach
    void setUp() {
        oldLevel = logger.getLevel();
        logger.setLevel(Level.DEBUG);
        logs.start();
        logger.addAppender(logs);
        service = spy(new VerifyServiceImpl());
        notifications = mock(MessageService.class);
        users = mock(LoginUserService.class);
        LoginUserRepository repository = mock(LoginUserRepository.class);
        LoginUser user = new LoginUser();
        user.setUsername(USER);
        user.setPassword("stored-password-hash-must-stay-private");
        when(repository.findByUsername(USER)).thenReturn(Optional.of(user));
        MessageFactory factory = mock(MessageFactory.class);
        when(factory.getType(MessageEnum.TELEGRAM)).thenReturn(notifications);
        ReflectionTestUtils.setField(service, "loginUserRepository", repository);
        ReflectionTestUtils.setField(service, "loginUserService", users);
        ReflectionTestUtils.setField(service, "messageFactory", factory);
        ReflectionTestUtils.setField(service, "systemConfigService", mock(SystemConfigService.class));
        doReturn(CODE).when(service).generateVerificationCode();
        service.init();
    }

    @AfterEach
    void tearDown() {
        logger.detachAppender(logs);
        logs.stop();
        logger.setLevel(oldLevel);
    }

    @Test
    void verificationAndResetStillDeliverSecretsWithoutWritingThemToLogs() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        service.sendVerificationCodeForLogin(USER, request);
        service.checkCodeForLogin(USER, CODE);
        service.sendVerificationCodeForPasswordReset(USER, request);
        String token = service.verifyCodeForPasswordReset(USER, CODE, request);
        service.resetPassword(USER, token);
        service.sendVerifyCodeForExport(USER, request);
        service.checkCodeForExport(USER, CODE);

        ArgumentCaptor<String> newPassword = ArgumentCaptor.forClass(String.class);
        verify(users).updateUser(eq(USER), eq(USER), newPassword.capture());
        assertFalse(newPassword.getValue().isEmpty());
        verify(notifications).sendVerificationCodeMessage(USER, CODE);
        verify(notifications).sendMessageTemplate(contains(newPassword.getValue()));
        assertSecretsAbsent(CODE, token, newPassword.getValue(), "stored-password-hash-must-stay-private");
    }

    @Test
    void notificationExceptionsCannotEchoNewPasswordsOrCodesIntoLogs() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        service.sendVerificationCodeForPasswordReset(USER, request);
        String token = service.verifyCodeForPasswordReset(USER, CODE, request);
        doAnswer(invocation -> {
            throw new IllegalStateException("provider echoed body: " + invocation.getArgument(0));
        }).when(notifications).sendMessageTemplate(anyString());
        service.resetPassword(USER, token);

        ArgumentCaptor<String> newPassword = ArgumentCaptor.forClass(String.class);
        verify(users).updateUser(eq(USER), eq(USER), newPassword.capture());
        assertSecretsAbsent(newPassword.getValue(), CODE, token, "provider echoed body");
        assertTrue(logText().contains("IllegalStateException"));
    }

    @Test
    void everyTelegramTemplatePathKeepsNotificationContentsOutOfLogs() {
        String password = "notification-password-secret";
        String message = "Password=" + password + ", code=" + CODE;
        TelegramMessageService telegram = new TelegramMessageService() {
            @Override public TelegramConfig getTelegramConfig() { return new TelegramConfig(); }
            @Override public BarkConfig getBarkConfig() { return null; }
            @Override public String formatVerificationCodeMessage(String username, String code) {
                return "Verification=" + code;
            }
        };
        DingDingMessageService ding = mock(DingDingMessageService.class);
        FeishuService feishu = mock(FeishuService.class);
        ReflectionTestUtils.setField(telegram, "dingDingMessageService", ding);
        ReflectionTestUtils.setField(telegram, "feishuService", feishu);
        telegram.sendMessageTemplate(message);
        telegram.sendMessageTemplateText(message);
        telegram.sendMessageTemplateText(message, true);
        telegram.sendMessageTemplateText(message, false);
        telegram.sendVerificationCodeMessage(USER, CODE);
        verify(ding, times(4)).sendMessageTemplate(message);
        verify(feishu, times(4)).sendMessageTemplate(message);
        assertSecretsAbsent(password, CODE, message);
    }

    private void assertSecretsAbsent(String... secrets) {
        String output = logText();
        for (String secret : secrets) assertFalse(output.contains(secret), "Credential leaked into a log event");
    }

    private String logText() {
        return logs.list.stream().map(event -> event.getFormattedMessage()
                + (event.getThrowableProxy() == null ? "" : ThrowableProxyUtil.asString(event.getThrowableProxy())))
                .collect(Collectors.joining("\n"));
    }
}
