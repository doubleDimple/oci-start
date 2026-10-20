package com.doubledimple.ociserver.service.login;

import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.LoginAttemptService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.util.HtmlUtils;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.Executor;

import static com.doubledimple.ocicommon.utils.IpUtils.getClientIpAddress;

/**
 * Uses the existing ban system's client-IP resolution. No credentials enter
 * counters or notifications, and notification delivery cannot undo a ban.
 */
@Service
@Slf4j
public class LoginFailureGuard {
    @Resource
    private LoginAttemptService loginAttemptService;

    @Resource
    private MessageFactory messageFactory;

    @Resource(name = "loginNotificationExecutor")
    private Executor notificationExecutor;

    public String assertAllowed(HttpServletRequest request) {
        String ip = getClientIpAddress(request);
        loginAttemptService.assertAllowed(ip);
        return ip;
    }

    public void loginSucceeded(String ip) {
        loginAttemptService.loginSucceeded(ip);
    }

    public void failed(String ip, String username, boolean unknownUsername) {
        // This call commits independently before a credential exception is returned.
        LoginAttemptService.FailureResult result = loginAttemptService.recordFailure(ip, unknownUsername);
        if (!result.isBanned() || result.isNewlyBanned()) {
            notifyFailure(ip, username, result);
        }
        if (result.isBanned()) {
            throw new IpBannedException("登录失败次数已达上限，IP 已被封禁，请联系管理员解封。");
        }
    }

    private void notifyFailure(String ip, String username, LoginAttemptService.FailureResult result) {
        String failure = result.isUnknownUsername() ? "用户名不存在" : "密码错误";
        String outcome = result.isNewlyBanned()
                ? "处理结果：已自动封禁该 IP，需手动解封。\n"
                : "处理结果：已记录失败，达到 " + result.getThreshold() + " 次后自动封禁。\n";
        String message = "———— 异常登录警告 ————\n"
                + "来源 IP：" + safeText(ip, 64) + "\n"
                + "用户名：" + safeText(username, 128) + "\n"
                + "原因：" + failure + "\n"
                + "本次计数：" + result.getFailureCount() + "/" + result.getThreshold() + "\n"
                + "时间：" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")) + "\n"
                + outcome
                + (result.isNewlyBanned() ? "解封命令：<code>/unbanIp " + safeText(ip, 64) + "</code>\n" : "")
                + "#安全告警";
        try {
            notificationExecutor.execute(() -> {
                try {
                    messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(message);
                } catch (Exception e) {
                    log.warn("登录失败通知发送失败，异常类型：{}", e.getClass().getSimpleName());
                }
            });
        } catch (RuntimeException e) {
            log.warn("登录失败通知提交失败，异常类型：{}", e.getClass().getSimpleName());
        }
    }

    private static String safeText(String value, int maxLength) {
        if (value == null) return "";
        String truncated = value.substring(0, Math.min(value.length(), maxLength));
        return HtmlUtils.htmlEscape(truncated.replaceAll("[\\p{Cntrl}]", " "));
    }
}
