package com.doubledimple.ociserver.service.login;

import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.message.TelegramMessageService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.util.HtmlUtils;

import javax.annotation.Resource;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.Executor;

/** Best-effort private alert after the global lock has committed; never delay or undo credential rejection. */
@Service
@Slf4j
public class GlobalLoginLockNotifier {
    @Resource private SystemConfigService systemConfigService;
    @Resource private MessageFactory messageFactory;
    @Resource private TelegramMessageService telegramMessageService;
    @Resource(name = "loginNotificationExecutor") private Executor notificationExecutor;

    public void notifyBlocked(GlobalLoginGuard.LockEvent event) {
        try {
            notificationExecutor.execute(() -> {
                try {
                    String site = systemConfigService.getSiteLogoName();
                    if (site == null || site.trim().isEmpty()) site = "OCI-START";
                    site = HtmlUtils.htmlEscape(site.substring(0, Math.min(site.length(), 128))
                            .replaceAll("[\\p{Cntrl}]", " "));
                    String deadline = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss XXX")
                            .withZone(event.getZone()).format(event.getBlockedUntil());
                    String message = "———— 全站登录安全告警 ————\n"
                            + "站点：" + site + "\n"
                            + "检测到连续 3 次异常登录，可能正在遭受攻击。所有账号现已暂停新登录。\n"
                            + "本次封禁时长：" + event.getHours() + " 小时\n"
                            + "恢复时间：" + deadline + "（" + event.getZone().getId() + "）\n\n"
                            + (event.getRecoveryCode() == null ? ""
                            : "本次支持通过绑定的 Telegram 私聊恢复：请查收单独的一次性恢复码，使用 /unlock_login 验证后可保留数据并恢复登录。\n\n")
                            + "如无法通过绑定 Telegram 恢复且不愿等待，可自行手动重置：\n"
                            + "1. 先备份租户完整凭证及所需资料，停止服务后完整备份数据库。\n"
                            + "2. 确认接受数据丢失后，删除实际部署使用的数据库文件。此操作会丢失本地账号、租户、任务、设置及通知配置。\n"
                            + "3. 重启服务后重新注册、导入租户，并重新配置通知终端。\n"
                            + "请勿在服务运行时删除数据库。";
                    // This existing entry fans out once to Telegram, DingTalk, Bark and Feishu as configured.
                    messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(message, Boolean.FALSE);
                } catch (Exception failure) {
                    log.warn("全站登录封禁通知发送失败，异常类型：{}", failure.getClass().getSimpleName());
                }
                // Recovery secrets never enter the fanout message, logs, or the normal GET notification URL.
                if (event.getRecoveryCode() != null) {
                    try {
                        String recoveryMessage = "本次全站登录封禁的一次性恢复码：\n<code>"
                                + event.getRecoveryCode() + "</code>\n\n"
                                + "请仅在本私聊发送以下四行，替换后三行内容：\n"
                                + "<code>/unlock_login\n登录用户名\n恢复码\n任意一个已录入租户名</code>\n\n"
                                + "验证成功仅解除全站登录封禁，不清除 IP 封禁或导出限制。恢复码使用一次后失效，连续验证失败 5 次暂停恢复验证 15 分钟。";
                        telegramMessageService.sendPrivateRecoveryMessage(recoveryMessage,
                                event.getRecoveryChatId(), event.getRecoveryBotTokenHash());
                    } catch (Exception failure) {
                        log.warn("Telegram 登录恢复码发送失败，异常类型：{}", failure.getClass().getSimpleName());
                    }
                }
            });
        } catch (RuntimeException failure) {
            log.warn("全站登录封禁通知提交失败，异常类型：{}", failure.getClass().getSimpleName());
        }
    }
}
