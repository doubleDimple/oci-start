package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.TelegramUser;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ocicommon.enums.BootInstanceStatusEnum;
import com.doubledimple.ocicommon.enums.RegionEnum;

import com.doubledimple.ociserver.config.task.DynamicDailyTask;
import com.doubledimple.ociserver.config.task.InstanceTrafficTask;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.pojo.response.AccountCheckRes;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.pojo.response.TenantTrafficStats;
import com.doubledimple.ociserver.service.BanService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciLimitsUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.ApplicationContext;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.telegram.telegrambots.bots.DefaultBotOptions;
import org.telegram.telegrambots.bots.TelegramLongPollingBot;
import org.telegram.telegrambots.meta.api.methods.AnswerCallbackQuery;
import org.telegram.telegrambots.meta.api.methods.send.SendMessage;
import org.telegram.telegrambots.meta.api.methods.updatingmessages.EditMessageText;
import org.telegram.telegrambots.meta.api.objects.CallbackQuery;
import org.telegram.telegrambots.meta.api.objects.Message;
import org.telegram.telegrambots.meta.api.objects.Update;
import org.telegram.telegrambots.meta.api.objects.User;
import org.telegram.telegrambots.meta.api.objects.replykeyboard.InlineKeyboardMarkup;
import org.telegram.telegrambots.meta.api.objects.replykeyboard.buttons.InlineKeyboardButton;
import org.telegram.telegrambots.meta.exceptions.TelegramApiException;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ocicommon.tg.TgUtils.getMaskedDisplayName;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.daysBetweenCurrent;
import static com.doubledimple.ociserver.config.telegram.TeleGramCon.WELCOME_COMEBACK_TEXT;
import static com.doubledimple.ociserver.config.telegram.TeleGramCon.WELCOME_TEXT;

/**
 * @version 1.0.0
 * @ClassName TelegramBot
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-21 16:24
 */
@Slf4j
public class TelegramBotCus extends TelegramLongPollingBot implements InitializingBean {

    public static final String MESSAGE_IP_BANNED_SUCCESS = "已成功封禁 IP：%s\n该 IP 的访问已被阻止。";
    public static final String MESSAGE_IP_BANNED_FAIL = "封禁 IP 失败：%s\n请检查系统配置或手动执行防火墙命令。";
    public static final String MESSAGE_IP_NOT_FOUND = "未检测到需要封禁的 IP。请先确认有异常登录记录。";

    /** 标题分隔线（粗）与内容分隔线（细），形成视觉层级 */
    private static final String DIVIDER = "━━━━━━━━━━━━━━━━━━━━";
    private static final String DIVIDER_THIN = "──────────────────";

    private static final String BTN_BACK_MAIN = "🏠 主菜单";
    private static final String BTN_LAST_PAGE = "⬅️ 上一页";
    private static final String BTN_NEXT_PAGE = "下一页 ➡️";
    private static final String BTN_REFRESH = "🔄 刷新";
    private static final String BTN_BACK = "↩️ 返回";

    private static final int PAGE_SIZE_TENANT = 10;
    private static final int PAGE_SIZE_BOOT_LOG = 5;
    private static final int QUOTA_TG_PAGE_SIZE = 5;


    private static final DateTimeFormatter TIME_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final DateTimeFormatter DATE_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd");


    private ApplicationContext applicationContext;

    private Long botId;
    private String botToken;
    private String botUsername;


    public TelegramBotCus(DefaultBotOptions options) {
        super(options);
    }

    public void setBotId(Long botId) {
        this.botId = botId;
    }

    public void setBotToken(String botToken) {
        this.botToken = botToken;
    }

    public void setBotUsername(String botUsername) {
        this.botUsername = botUsername;
    }

    public void setApplicationContext(ApplicationContext applicationContext) {
        this.applicationContext = applicationContext;
    }

    private BanService getIpBanService() {
        return applicationContext.getBean(BanService.class);
    }


    private ChatAiService getChatAiService() {
        return applicationContext.getBean(ChatAiService.class);
    }

    private SystemConfigService getSystemConfigService() {
        return applicationContext.getBean(SystemConfigService.class);
    }

    private TelegramUserService getTelegramUserService() {
        return applicationContext.getBean(TelegramUserService.class);
    }

    private TenantService getTenantService(){
        return applicationContext.getBean(TenantService.class);
    }

    private VersionCheckTask getVersionCheckTask(){
        return applicationContext.getBean(VersionCheckTask.class);
    }

    private OracleInstanceService getOracleInstanceService() {
        return applicationContext.getBean(OracleInstanceService.class);
    }

    private InstanceTrafficTask getInstanceTrafficTask() {
        return applicationContext.getBean(InstanceTrafficTask.class);
    }

    /**
     * 在机器人启动后发送欢迎消息
     */
    public void sendWelcomeMessageAfterStartup() {
        try {
            SystemConfigService systemConfigService = getSystemConfigService();
            TelegramUserService telegramUserService = getTelegramUserService();

            TelegramConfig config = systemConfigService.getTelegramConfig();
            if (config.isEnabled() && config.getChatId() != null) {
                Long chatId = Long.parseLong(config.getChatId());
                String chatName = config.getChatName();
                if (StringUtils.isBlank(chatName)){
                    chatName = "主人";
                }
                TelegramUser telegramUser = telegramUserService.getUserById();
                String text = WELCOME_TEXT;
                if (telegramUser != null){
                    text = WELCOME_COMEBACK_TEXT;
                }

                SendMessage message = SendMessage.builder()
                        .chatId(chatId)
                        .text(String.format(text, chatName))
                        .build();

                execute(message);
                log.info("已发送欢迎消息到聊天: chatId:{}", chatId);
            }
        } catch (TelegramApiException e) {
            if (e.getMessage().contains("Connection refused") ||
                    e.getMessage().contains("timeout")) {
                log.warn("网络连接问题，欢迎消息发送失败: {}", e.getMessage());
            } else {
                log.error("发送欢迎消息失败: {}", e.getMessage());
            }
        } catch (Exception e) {
            log.warn("发送欢迎消息时发生未知错误: {}", e.getMessage());
        }
    }

    @Override
    public String getBotUsername() {
        return botUsername;
    }

    @Override
    public String getBotToken() {
        return botToken;
    }

    @Override
    public void onUpdateReceived(Update update) {
        if (update == null) {
            return;
        }

        try {
            // 处理文本消息
            if (update.hasMessage() && update.getMessage().hasText()) {
                handleTextMessage(update.getMessage());
            }
            // 处理回调查询（按钮点击）
            else if (update.hasCallbackQuery()) {
                handleCallbackQuery(update.getCallbackQuery());
            }
        } catch (Exception e) {
            log.error("处理更新时出错: {}", e.getMessage(), e);
        }
    }

    /**
     * 处理文本消息
     */
    private void handleTextMessage(Message message) {
        Long chatId = message.getChatId();
        String text = message.getText();
        User user = message.getFrom();

        log.debug("收到消息: {} 来自: {}", text, chatId);

        try {
            TelegramUserService telegramUserService = getTelegramUserService();

            //也要检查用户权限
            if (!telegramUserService.checkUser(user.getId())){
                sendTextMessage(chatId, "🚫 抱歉，您没有权限使用此机器人。");
                return;
            }

            if ("/active".equals(text)) {
                handleStartCommand(chatId, user, telegramUserService);
            } else if (text.startsWith("/banIp")) {
                String ipPart = text.substring("/banIp".length());

                String ip;
                if (ipPart.startsWith("_")) {
                    // 格式 /banIp_127_0_0_1
                    ip = ipPart.substring(1).replace('_', '.');
                } else if (ipPart.startsWith(" ")) {
                    // 格式 /banIp 127.0.0.1
                    ip = ipPart.substring(1).trim();
                } else {
                    // 用户输入格式不对
                    sendTextMessage(chatId, "无效的命令格式，请使用 /banIp 127.0.0.1 或 /banIp_127_0_0_1");
                    return;
                }

                if (StringUtils.isNotBlank(ip)) {
                    boolean success = getIpBanService().banIp(ip, "手动封禁");
                    if (success) {
                        sendTextMessage(chatId, "✅ 已成功封禁 IP：" + ip +
                                "\n如需解封，请执行：/unbanIp_" + ip.replace('.', '_'));
                    } else {
                        sendTextMessage(chatId, "⚠️ 封禁失败或已存在封禁记录：" + ip);
                    }
                } else {
                    sendTextMessage(chatId, "未识别 IP 地址，请检查命令格式。");
                }
                return;
            }else if (text.startsWith("/unbanIp")) {
                // 同理支持 /unbanIp_127_0_0_1 和 /unbanIp 127.0.0.1
                String ipPart = text.substring("/unbanIp".length());

                String ip;
                if (ipPart.startsWith("_")) {
                    ip = ipPart.substring(1).replace('_', '.');
                } else if (ipPart.startsWith(" ")) {
                    ip = ipPart.substring(1).trim();
                } else {
                    sendTextMessage(chatId, "无效的命令格式，请使用 /unbanIp 127.0.0.1 或 /unbanIp_127_0_0_1");
                    return;
                }

                if (StringUtils.isNotBlank(ip)) {
                    boolean success = getIpBanService().unbanIp(ip, "手动解封");
                    if (success) {
                        sendTextMessage(chatId, "✅ 已成功解除封禁 IP：" + ip +
                                "\n如需重新封禁，请执行：/banIp_" + ip.replace('.', '_'));
                    } else {
                        sendTextMessage(chatId, "⚠️ 未找到封禁记录或已解封：" + ip);
                    }
                } else {
                    sendTextMessage(chatId, "未识别 IP 地址，请检查命令格式。");
                }
                return;
            } else {
                // 检查用户权限
                if (!telegramUserService.isUserAuthorized(user.getId())) {
                    sendTextMessage(chatId, "🚫 抱歉，您没有权限使用此机器人。");
                    return;
                }

                // 更新用户活跃时间
                telegramUserService.updateUserLastActive(user.getId());

                // 处理其他命令
                if ("/menu".equals(text) || "/start".equals(text)) {
                    sendMainMenu(chatId, null);
                } else {
                    handleAiChat(chatId, user.getId(), text);
                }
            }
        } catch (Exception e) {
            log.error("处理文本消息时出错: {}", e.getMessage(), e);
            sendTextMessage(chatId, "处理消息时出现错误，请稍后重试。");
        }
    }

    private void handleBanIp(Long chatId, User user, String text) {

        BanService banService = getIpBanService();

        // 提取 IP 参数
        String[] parts = text.split("\\s+"); // 按空格分割
        String ip = parts.length > 1 ? parts[1].trim() : null;

        if (StringUtils.isBlank(ip)) {
            sendTextMessage(chatId, "请在命令后输入要封禁的 IP，例如：/banIp 23.26.125.77");
            return;
        }

        // 封禁逻辑
        boolean success = banService.banIp(ip, "手动封禁");

        if (success) {
            sendTextMessage(chatId, String.format(MESSAGE_IP_BANNED_SUCCESS, ip));
        } else {
            sendTextMessage(chatId, String.format(MESSAGE_IP_BANNED_FAIL, ip));
        }
    }

    private void handleUnbanIp(Long chatId, User user, String text) {
        BanService banService = getIpBanService();

        // 提取 IP 参数
        String[] parts = text.split("\\s+");
        String ip = parts.length > 1 ? parts[1].trim() : null;

        if (StringUtils.isBlank(ip)) {
            sendTextMessage(chatId, "请在命令后输入要解封的 IP，例如：/unbanIp 23.26.125.77");
            return;
        }

        boolean success = banService.unbanIp(ip,"手动解封");

        if (success) {
            sendTextMessage(chatId, String.format("已解除封禁 IP：%s\n该 IP 已恢复正常访问。", ip));
        } else {
            sendTextMessage(chatId, String.format("解封 IP 失败：%s\n请确认该 IP 是否已封禁或稍后再试。", ip));
        }
    }



    /**
     * 处理回调查询（按钮点击）
     */
    private void handleCallbackQuery(CallbackQuery callbackQuery) {
        Long chatId = callbackQuery.getMessage().getChatId();
        Integer messageId = callbackQuery.getMessage().getMessageId();
        String callbackData = callbackQuery.getData();
        User user = callbackQuery.getFrom();

        log.info("[TG-CB] 收到所有回调: {} 来自: {}", callbackData, chatId);

        // 立即应答回调查询：消除客户端按钮上的"转圈"等待动画，点击即刻有响应（丝滑体验的关键）
        answerCallback(callbackQuery.getId());

        try {
            TelegramUserService telegramUserService = getTelegramUserService();
            if (telegramUserService == null) {
                log.error("无法获取TelegramUserService，跳过回调处理");
                sendTextMessage(chatId, "系统服务暂时不可用，请稍后重试。");
                return;
            }

            // 检查用户权限
            if (!telegramUserService.isUserAuthorized(user.getId())) {
                sendTextMessage(chatId, "🚫 抱歉，您没有权限使用此机器人。");
                return;
            }

            // 更新用户活跃时间
            telegramUserService.updateUserLastActive(user.getId());

            // 处理回调
            switch (callbackData) {
                case "account_check":
                    handleAccountCheck(chatId, messageId);
                    break;
                case "system_upgrade":
                    showUpgradeMenu(chatId, messageId);
                    break;
                case "do_upgrade":
                    handleSystemUpgrade(chatId, messageId);
                    break;
                case "query_tenant":
                    handleQueryTenant(chatId, messageId);
                    break;
                case "boot_log":
                    sendBootLogPage(chatId, messageId, 1);
                    break;
                case "monthly_traffic":
                    handleMonthlyTraffic(chatId, messageId, 1);
                    break;
                case "help":
                    handleHelp(chatId, messageId);
                    break;
                case "divider":
                    // 分隔线按钮不做任何操作
                    break;
                case "back_to_main":
                    sendMainMenu(chatId, messageId);
                    break;
                case "back_to_tenant_list":
                    handleQueryTenant(chatId, messageId);
                    break;
                case "back_to_traffic_list":
                    handleMonthlyTraffic(chatId, messageId, 1);
                    break;
                default:
                    // 处理租户详情回调
                    if (callbackData.startsWith("tenant_detail_")) {
                        Long tenantId = Long.valueOf(callbackData.substring("tenant_detail_".length()));
                        showTenantDetail(chatId, messageId, tenantId);
                    }
                    // 处理区域信息回调
                    else if (callbackData.startsWith("region_info_")) {
                        Long regionId = Long.valueOf(callbackData.substring("region_info_".length()));
                        showRegionInfo(chatId, messageId, regionId);
                    }

                    else if (callbackData.startsWith("boot_log_page_")) {
                        int page = Integer.parseInt(callbackData.replace("boot_log_page_", ""));
                        sendBootLogPage(chatId, messageId, page);
                    }

                    else if (callbackData.startsWith("tenant_page_")) {
                        int page = Integer.parseInt(callbackData.replace("tenant_page_", ""));
                        showParentTenantMenu(chatId, messageId, getAllParentTenants(), page);
                    }

                    else if (callbackData.startsWith("update_instances_")) {
                        Long regionId = Long.valueOf(callbackData.substring("update_instances_".length()));
                        handleUpdateInstances(chatId, messageId, regionId);
                    }

                    // 本月流量相关回调
                    else if (callbackData.startsWith("traffic_page_")) {
                        int page = Integer.parseInt(callbackData.replace("traffic_page_", ""));
                        handleMonthlyTraffic(chatId, messageId, page);
                    }
                    else if (callbackData.startsWith("traffic_parent_")) {
                        Long parentId = Long.valueOf(callbackData.substring("traffic_parent_".length()));
                        showTrafficRegionMenu(chatId, messageId, parentId);
                    }
                    else if (callbackData.startsWith("traffic_region_")) {
                        Long regionId = Long.valueOf(callbackData.substring("traffic_region_".length()));
                        queryAndShowRegionTraffic(chatId, messageId, regionId, false);
                    }
                    else if (callbackData.startsWith("traffic_refresh_")) {
                        Long regionId = Long.valueOf(callbackData.substring("traffic_refresh_".length()));
                        queryAndShowRegionTraffic(chatId, messageId, regionId, true);
                    }
                    else if (callbackData.startsWith("traffic_back_regions_")) {
                        Long parentId = Long.valueOf(callbackData.substring("traffic_back_regions_".length()));
                        showTrafficRegionMenu(chatId, messageId, parentId);
                    }

                    // 配额相关回调
                    else if (callbackData.startsWith("quota_region_")) {
                        Long regionId = Long.valueOf(callbackData.substring("quota_region_".length()));
                        showQuotaServiceMenu(chatId, messageId, regionId);
                    }
                    else if (callbackData.startsWith("quota_svc_")) {
                        String payload = callbackData.substring("quota_svc_".length());
                        int sep = payload.indexOf('_');
                        Long tenantId = Long.valueOf(payload.substring(0, sep));
                        String svc = payload.substring(sep + 1);
                        queryAndShowQuota(chatId, messageId, tenantId, svc, false);
                    }
                    else if (callbackData.startsWith("quota_refresh_")) {
                        String payload = callbackData.substring("quota_refresh_".length());
                        int sep = payload.indexOf('_');
                        Long tenantId = Long.valueOf(payload.substring(0, sep));
                        String svc = payload.substring(sep + 1);
                        queryAndShowQuota(chatId, messageId, tenantId, svc, true);
                    }
                    else if (callbackData.startsWith("quota_page_")) {
                        String payload = callbackData.substring("quota_page_".length());
                        int lastSep = payload.lastIndexOf('_');
                        int page = Integer.parseInt(payload.substring(lastSep + 1));
                        String rest = payload.substring(0, lastSep);
                        int firstSep = rest.indexOf('_');
                        Long tenantId = Long.valueOf(rest.substring(0, firstSep));
                        String svc = rest.substring(firstSep + 1);
                        showQuotaPage(chatId, messageId, tenantId, svc, page);
                    }

                    // 实例操作回调 - inst_term_ok_ / inst_drec_ok_ 必须在 inst_term_ / inst_drec_ 之前检查
                    else if (callbackData.startsWith("inst_d_")) {
                        log.info("[TG-INST] 收到实例回调: {}", callbackData);
                        String[] parts = callbackData.substring("inst_d_".length()).split("_");
                        if (parts.length < 2) {
                            sendTextMessage(chatId, "❌ 回调格式异常: " + callbackData + "，请重新进入区域列表。");
                        } else {
                            showInstanceActions(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                        }
                    }
                    else if (callbackData.startsWith("inst_start_")) {
                        String[] parts = callbackData.substring("inst_start_".length()).split("_");
                        handleInstStart(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_stop_")) {
                        String[] parts = callbackData.substring("inst_stop_".length()).split("_");
                        handleInstStop(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_term_ok_")) {
                        String[] parts = callbackData.substring("inst_term_ok_".length()).split("_");
                        handleInstTerminateConfirm(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_term_")) {
                        String[] parts = callbackData.substring("inst_term_".length()).split("_");
                        handleInstTerminate(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_cip_")) {
                        String[] parts = callbackData.substring("inst_cip_".length()).split("_");
                        handleInstChangeIp(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_cfs_")) {
                        String[] parts = callbackData.substring("inst_cfs_".length()).split("_");
                        handleInstConfigSet(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]),
                                Integer.parseInt(parts[2]), Integer.parseInt(parts[3]));
                    }
                    else if (callbackData.startsWith("inst_cfg_")) {
                        String[] parts = callbackData.substring("inst_cfg_".length()).split("_");
                        showInstConfigMenu(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_dsk_")) {
                        String[] parts = callbackData.substring("inst_dsk_".length()).split("_");
                        handleInstDiskSet(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]),
                                Long.parseLong(parts[2]));
                    }
                    else if (callbackData.startsWith("inst_disk_")) {
                        String[] parts = callbackData.substring("inst_disk_".length()).split("_");
                        showInstDiskMenu(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_ipv6_")) {
                        String[] parts = callbackData.substring("inst_ipv6_".length()).split("_");
                        handleInstIpv6(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_drec_ok_")) {
                        String[] parts = callbackData.substring("inst_drec_ok_".length()).split("_");
                        handleInstDeleteRecordConfirm(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_drec_")) {
                        String[] parts = callbackData.substring("inst_drec_".length()).split("_");
                        handleInstDeleteRecord(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_reboot_")) {
                        String[] parts = callbackData.substring("inst_reboot_".length()).split("_");
                        showInstRebootMenu(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]));
                    }
                    else if (callbackData.startsWith("inst_rbt_s_")) {
                        String[] parts = callbackData.substring("inst_rbt_s_".length()).split("_");
                        handleInstReboot(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]), true);
                    }
                    else if (callbackData.startsWith("inst_rbt_h_")) {
                        String[] parts = callbackData.substring("inst_rbt_h_".length()).split("_");
                        handleInstReboot(chatId, messageId, Long.valueOf(parts[0]), Long.valueOf(parts[1]), false);
                    }

                    // 兼容旧格式按钮（重启前生成的消息）
                    else if (callbackData.startsWith("instance_detail_")) {
                        sendOrEdit(chatId, messageId,
                                "⚠️ 该按钮已过期\n请重新进入区域列表刷新实例按钮。",
                                onlyBackToMainMarkup());
                    }
            }
        } catch (Exception e) {
            log.error("处理回调查询时出错: {}", e.getMessage(), e);
            sendTextMessage(chatId, "处理操作时出现错误，请稍后重试。");
        }
    }

    /**
     * 处理/start命令
     */
    private void handleStartCommand(Long chatId, User user, TelegramUserService telegramUserService) {
        try {
            TelegramUser telegramUserUpdate = new TelegramUser();
            telegramUserUpdate.setUserId(user.getId());
            telegramUserUpdate.setUsername(user.getUserName());
            telegramUserUpdate.setFirstName(user.getFirstName());
            telegramUserUpdate.setLastName(user.getLastName());

            TelegramUser userDetail = telegramUserService.getUserById(user.getId());
            if (userDetail == null){
                sendTextMessage(chatId, "🎉 激活成功！欢迎使用 OCI-START 智能助手");
                sendMainMenu(chatId, null);
                telegramUserUpdate.setActive(true);
            }else{
                Boolean active = userDetail.getActive();
                if (null== active || !active){
                    sendTextMessage(chatId, "👋 欢迎回来！OCI-START 智能助手已就绪");
                    telegramUserUpdate.setActive(true);
                }
            }
            telegramUserService.registerUser(telegramUserUpdate);

        } catch (Exception e) {
            log.error("处理start命令时出错: {}", e.getMessage(), e);
            sendTextMessage(chatId, "注册过程中出现错误，请稍后重试。");
        }
    }

    /**
     * 发送主菜单 - 优化版本（支持在原消息上编辑）
     */
    private void sendMainMenu(Long chatId, Integer messageId) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        // 第一行：账号测活和版本检查
        keyboard.add(row(
                button("🩺 账号测活", "account_check"),
                button("🚀 版本检查", "system_upgrade")
        ));

        // 第二行：我的账号和本月流量
        keyboard.add(row(
                button("👤 我的账号", "query_tenant"),
                button("📊 本月流量", "monthly_traffic")
        ));

        // 第三行：开机日志和帮助
        keyboard.add(row(
                button("📋 开机日志", "boot_log"),
                button("💡 使用帮助", "help")
        ));

        // 第四行：GitHub
        InlineKeyboardButton githubBtn = new InlineKeyboardButton();
        githubBtn.setText("⭐ GitHub 项目主页");
        githubBtn.setUrl("https://github.com/doubleDimple/oci-start");
        keyboard.add(Collections.singletonList(githubBtn));

        markup.setKeyboard(keyboard);

        String text = "⚡️ <b>OCI-START 智能助手</b>\n" +
                DIVIDER + "\n" +
                greeting() + "，欢迎回来\n" +
                "🟢 服务运行中 · " + LocalDateTime.now().format(TIME_FMT) + "\n" +
                DIVIDER_THIN + "\n\n" +
                "👇 <i>点击下方按钮开始操作，或直接发送消息与 AI 对话</i>";

        sendOrEdit(chatId, messageId, text, markup);
    }

    /**
     * 处理账号测活功能
     */
    private void handleAccountCheck(Long chatId, Integer messageId) {
        sendOrEdit(chatId, messageId,
                "🩺 <b>账号测活</b>\n" + DIVIDER + "\n\n⏳ 正在批量检测账号活跃状态，请稍候…",
                onlyBackToMainMarkup());
        new Thread(() -> {
            String resultText;
            try {
                AccountCheckRes res = getTenantService().checkBatchAccounts();
                resultText = formatAccountCheckResult(res);
            } catch (Exception e) {
                log.error("账号测活失败: {}", e.getMessage(), e);
                resultText = "❌ <b>账号测活失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage());
            }
            sendOrEdit(chatId, messageId, resultText, onlyBackToMainMarkup());
        }, "tg-account-check-" + chatId).start();
    }

    private String formatAccountCheckResult(AccountCheckRes res) {
        if (res == null) {
            return "✅ <b>账号测活完成</b>\n" + DIVIDER + "\n\n所有账号已完成活跃状态检测。";
        }
        int total = res.getTotalAccounts();
        int active = res.getActiveAccounts();
        int inactive = res.getInactiveAccounts();
        boolean allHealthy = inactive == 0;

        StringBuilder sb = new StringBuilder();
        sb.append(allHealthy ? "✅" : "⚠️").append(" <b>账号测活完成</b>\n").append(DIVIDER).append("\n\n");

        // 健康度可视化进度条
        double healthRatio = total > 0 ? (double) active / total : 1.0;
        sb.append("🩺 <b>健康度</b>  ").append(progressBar(healthRatio))
                .append("  <b>").append(String.format("%.0f%%", healthRatio * 100)).append("</b>\n");
        sb.append(DIVIDER_THIN).append("\n");
        sb.append("📦 总数  <code>").append(total).append("</code>\n");
        sb.append("🟢 活跃  <code>").append(active).append("</code>\n");
        sb.append("🔴 异常  <code>").append(inactive).append("</code>\n");

        List<String> names = res.getInactiveAccountNames();
        if (names != null && !names.isEmpty()) {
            sb.append("\n🚨 <b>异常账号</b>\n");
            int limit = Math.min(names.size(), 20);
            for (int i = 0; i < limit; i++) {
                sb.append("  ▪️ ").append(escape(names.get(i))).append("\n");
            }
            if (names.size() > limit) {
                sb.append("  <i>…另有 ").append(names.size() - limit).append(" 个，略</i>\n");
            }
        } else {
            sb.append("\n🎉 <i>全部账号状态正常，无需处理</i>\n");
        }
        sb.append("\n🕐 <i>完成时间：").append(LocalDateTime.now().format(TIME_FMT)).append("</i>");
        return sb.toString();
    }

    /**
     * 处理系统升级（执行升级后服务可能重启）
     */
    private void handleSystemUpgrade(Long chatId, Integer messageId) {
        sendOrEdit(chatId, messageId,
                "🚀 <b>正在执行系统升级</b>\n" + DIVIDER +
                        "\n\n⏳ 升级过程中助手将暂时离线，完成后会自动回来～",
                null);
        new Thread(() -> {
            try {
                Thread.sleep(800);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
            try {
                getVersionCheckTask().executeUpdate();
            } catch (Exception e) {
                log.error("升级失败: {}", e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>升级失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        onlyBackToMainMarkup());
            }
        }, "tg-upgrade-" + chatId).start();
    }

    /**
     * 处理查询租户功能 - 显示父租户列表
     */
    private void handleQueryTenant(Long chatId, Integer messageId) {
        try {
            List<Tenant> content = getAllParentTenants();
            if (content == null || content.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "👤 <b>我的账号</b>\n" + DIVIDER + "\n\n📭 暂无账号信息。",
                        onlyBackToMainMarkup());
                return;
            }
            showParentTenantMenu(chatId, messageId, content, 1);
        } catch (Exception e) {
            log.error("查询租户时出错: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "查询租户时出现错误，请稍后重试。\n" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }

    private List<Tenant> getAllParentTenants() {
        Page<Tenant> allTenants = getTenantService().getAllTenants(1, 0, 1000);
        return allTenants.getContent();
    }


    /**
     * 显示父租户菜单
     */
    private void showParentTenantMenu(Long chatId, Integer messageId, List<Tenant> tenants, int page) {

        int total = tenants.size();
        int totalPage = Math.max(1, (int) Math.ceil((double) total / PAGE_SIZE_TENANT));

        // 页码安全处理
        page = Math.max(1, Math.min(page, totalPage));

        int start = (page - 1) * PAGE_SIZE_TENANT;
        int end = Math.min(start + PAGE_SIZE_TENANT, total);

        List<Tenant> pageList = tenants.subList(start, end);

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        // 每行一个租户按钮
        for (Tenant tenant : pageList) {
            String displayName = resolveDisplayName(tenant);
            List<Tenant> children = getTenantService().regionList(tenant.getId());
            int childrenCount = children != null ? children.size() : 1;
            String label = String.format("☁️ %s · %s · %d 区域",
                    displayName,
                    RegionEnum.getNameSimple(tenant.getRegion()),
                    childrenCount);
            keyboard.add(Collections.singletonList(button(label, "tenant_detail_" + tenant.getId())));
        }

        // 分页按钮
        List<InlineKeyboardButton> navRow = pageNavRow(page, totalPage, "tenant_page_");
        if (!navRow.isEmpty()) {
            keyboard.add(navRow);
        }

        // 返回主菜单
        keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));

        markup.setKeyboard(keyboard);

        String text = "👤 <b>我的账号</b>\n" + DIVIDER + "\n" +
                String.format("📦 共 <b>%d</b> 个账号 · 第 %d/%d 页\n", total, page, totalPage) +
                DIVIDER_THIN + "\n\n" +
                "👇 <i>点击账号查看区域与实例</i>";

        sendOrEdit(chatId, messageId, text, markup);
    }


    /**
     * 显示租户详情（子区域列表）
     */
    private void showTenantDetail(Long chatId, Integer messageId, Long tenantId) {
        try {
            Tenant tenant = getTenantService().getById(tenantId);
            if (tenant == null) {
                sendOrEdit(chatId, messageId,
                        "⚠️ 未找到该租户信息",
                        onlyBackToMainMarkup());
                return;
            }

            String displayName = resolveDisplayName(tenant);
            List<Tenant> children = getTenantService().regionList(tenantId);
            if (children == null || children.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "☁️ <b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n\n📭 该租户暂无区域信息。",
                        backToTenantListMarkup());
                return;
            }

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 为每个子区域创建按钮，每行显示两个
            List<InlineKeyboardButton> currentRow = new ArrayList<>();
            for (int i = 0; i < children.size(); i++) {
                Tenant child = children.get(i);

                // 显示区域信息
                String regionDisplay = child.getRegion() != null ? child.getRegion() : "未知区域";
                String accountType = child.getAccountTypeName() != null ?
                        " (" + child.getAccountTypeName() + ")" : "";

                currentRow.add(button("🌍 " + regionDisplay + accountType, "region_info_" + child.getId()));

                // 每两个按钮一行，或者到达最后一个元素时添加到keyboard
                if (currentRow.size() == 2 || i == children.size() - 1) {
                    keyboard.add(new ArrayList<>(currentRow));
                    currentRow.clear();
                }
            }

            // 添加返回按钮
            keyboard.add(row(
                    button("↩️ 账号列表", "back_to_tenant_list"),
                    button(BTN_BACK_MAIN, "back_to_main")
            ));

            markup.setKeyboard(keyboard);

            String text = "☁️ <b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n" +
                    String.format("🌍 共 <b>%d</b> 个区域\n", children.size()) +
                    DIVIDER_THIN + "\n\n" +
                    "👇 <i>点击区域查看实例列表</i>";

            sendOrEdit(chatId, messageId, text, markup);

        } catch (Exception e) {
            log.error("显示租户详情时出错: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "获取租户详情时出现错误：" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }

    /**
     * 显示区域详细信息 - 已优化：增加更新实例按钮
     */
    private void showRegionInfo(Long chatId, Integer messageId, Long regionId) {
        try {
            Tenant region = getTenantService().getById(regionId);
            if (region == null) {
                sendOrEdit(chatId, messageId, "⚠️ 未找到该区域信息",
                        onlyBackToMainMarkup());
                return;
            }

            Page<InstanceDetailsRes> allInstances = getOracleInstanceService().getAllInstances(0, 1000, region.getIdStr());
            List<InstanceDetailsRes> instances = allInstances.getContent();

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 1. 如果有实例，渲染实例列表
            if (instances != null && !instances.isEmpty()) {
                for (InstanceDetailsRes instance : instances) {

                    String architecture = instance.getArchitecture() != null ? instance.getArchitecture() : "未知";
                    String cpu = instance.getOcpus() != null ? instance.getOcpus().toString() + "核" : "未知";
                    String memory = instance.getMemoryInGBs() != null ? instance.getMemoryInGBs().toString() + "GB" : "未知";
                    String disk = instance.getBootVolumeSizeInGBs() != null ? instance.getBootVolumeSizeInGBs().toString() + "GB" : "未知";
                    String ipv4 = instance.getPublicIps() != null && !instance.getPublicIps().isEmpty() ?
                            instance.getPublicIps() :
                            (instance.getPrivateIps() != null ? instance.getPrivateIps() : "无IP");

                    String stateIcon = getStateIcon(instance.getState());
                    String buttonText = String.format("%s/%s/%s/%s/%s %s",
                            architecture, cpu, memory, disk, ipv4, stateIcon);

                    keyboard.add(Collections.singletonList(button(buttonText, "inst_d_" + regionId + "_" + instance.getId())));
                }
            }

            // 2. 构建底部操作行：查询配额 + 更新实例 + 返回
            Long parenId = region.getParenId();
            if (parenId == 0L) parenId = region.getId();
            keyboard.add(row(
                    button("📊 查询配额", "quota_region_" + region.getId()),
                    button("🔄 更新实例", "update_instances_" + region.getId())
            ));
            keyboard.add(Collections.singletonList(button(BTN_BACK, "tenant_detail_" + parenId)));
            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));

            markup.setKeyboard(keyboard);

            int instanceCount = (instances != null) ? instances.size() : 0;
            String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";
            String text = "🌍 <b>" + escape(regionName) + "</b>\n" + DIVIDER + "\n\n" +
                    (instanceCount > 0
                            ? String.format("🖥 共 <b>%d</b> 个实例，点击查看详情", instanceCount)
                            : "📭 该区域暂无实例");

            sendOrEdit(chatId, messageId, text, markup);

        } catch (Exception e) {
            log.error("显示区域实例信息时出错: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "获取实例信息时出现错误：" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }
    private String getStateIcon(String state) {
        if (state == null) return "⚪️ 未知";

        switch (state.toUpperCase()) {
            case "RUNNING":
                return "🟢 运行中";
            case "STOPPED":
                return "🔴 已停止";
            case "STOPPING":
                return "🟠 停止中";
            case "STARTING":
                return "🟡 启动中";
            case "PROVISIONING":
                return "🔵 预配中";
            case "TERMINATING":
                return "🟠 终止中";
            case "TERMINATED":
                return "⚫️ 已终止";
            default:
                return "⚪️ " + state;
        }
    }

    /**
     * 处理帮助功能
     */
    private void handleHelp(Long chatId, Integer messageId) {
        String helpText = "💡 <b>OCI-START 使用帮助</b>\n" + DIVIDER + "\n\n" +
                "📌 <b>功能说明</b>\n" +
                "🩺 <b>账号测活</b> — 批量检查所有账号的活跃状态\n" +
                "🚀 <b>版本检查</b> — 检查并一键执行系统升级\n" +
                "👤 <b>我的账号</b> — 查看租户 / 区域 / 实例信息\n" +
                "📊 <b>本月流量</b> — 查询本月各区域出站流量\n" +
                "📋 <b>开机日志</b> — 查看预开机执行历史\n" +
                DIVIDER_THIN + "\n" +
                "⌨️ <b>常用命令</b>\n" +
                "▪️ <code>/start</code> / <code>/menu</code> — 打开主菜单\n" +
                "▪️ <code>/active</code> — 激活账号\n" +
                "▪️ <code>/banIp 1.2.3.4</code> — 封禁 IP\n" +
                "▪️ <code>/unbanIp 1.2.3.4</code> — 解除封禁\n" +
                "▪️ 直接发送消息 — 与 AI 助手对话 🤖\n" +
                DIVIDER_THIN + "\n" +
                "⭐ <b>项目地址</b>\n" +
                "<a href=\"https://github.com/doubleDimple/oci-start\">github.com/doubleDimple/oci-start</a>";

        sendOrEdit(chatId, messageId, helpText, onlyBackToMainMarkup());
    }

    // ============== 本月流量功能 ==============

    /**
     * 本月流量入口：展示父租户列表
     */
    private void handleMonthlyTraffic(Long chatId, Integer messageId, int page) {
        try {
            List<Tenant> tenants = getAllParentTenants();
            if (tenants == null || tenants.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "📊 <b>本月流量</b>\n" + DIVIDER + "\n\n📭 暂无账号信息。",
                        onlyBackToMainMarkup());
                return;
            }
            showTrafficParentMenu(chatId, messageId, tenants, page);
        } catch (Exception e) {
            log.error("加载本月流量入口失败: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "加载流量菜单失败：" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }

    private void showTrafficParentMenu(Long chatId, Integer messageId, List<Tenant> tenants, int page) {
        int total = tenants.size();
        int totalPage = Math.max(1, (int) Math.ceil((double) total / PAGE_SIZE_TENANT));
        page = Math.max(1, Math.min(page, totalPage));

        int start = (page - 1) * PAGE_SIZE_TENANT;
        int end = Math.min(start + PAGE_SIZE_TENANT, total);
        List<Tenant> pageList = tenants.subList(start, end);

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        for (Tenant tenant : pageList) {
            String displayName = resolveDisplayName(tenant);
            List<Tenant> children = getTenantService().regionList(tenant.getId());
            int childrenCount = children != null ? children.size() : 1;
            String label = String.format("☁️ %s · %d 区域", displayName, childrenCount);
            keyboard.add(Collections.singletonList(button(label, "traffic_parent_" + tenant.getId())));
        }

        List<InlineKeyboardButton> navRow = pageNavRow(page, totalPage, "traffic_page_");
        if (!navRow.isEmpty()) {
            keyboard.add(navRow);
        }

        keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(keyboard);

        String periodStart = LocalDateTime.now().withDayOfMonth(1).format(DATE_FMT);
        String text = "📊 <b>本月流量查询</b>\n" + DIVIDER + "\n" +
                "🗓 统计周期  <code>" + periodStart + "</code> 至今 <i>(UTC)</i>\n" +
                String.format("📦 共 <b>%d</b> 个账号 · 第 %d/%d 页\n", total, page, totalPage) +
                DIVIDER_THIN + "\n\n" +
                "👇 <i>点击账号查看区域流量</i>";

        sendOrEdit(chatId, messageId, text, markup);
    }

    private void showTrafficRegionMenu(Long chatId, Integer messageId, Long parentId) {
        try {
            Tenant parent = getTenantService().getById(parentId);
            if (parent == null) {
                sendOrEdit(chatId, messageId, "⚠️ 未找到该租户信息", trafficBackToListMarkup());
                return;
            }

            String displayName = resolveDisplayName(parent);
            List<Tenant> regions = getTenantService().regionList(parentId);
            if (regions == null || regions.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "☁️ <b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n\n📭 该租户暂无区域信息。",
                        trafficBackToListMarkup());
                return;
            }

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            List<InlineKeyboardButton> currentRow = new ArrayList<>();
            for (int i = 0; i < regions.size(); i++) {
                Tenant region = regions.get(i);
                String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";
                currentRow.add(button("🌍 " + regionName, "traffic_region_" + region.getId()));
                if (currentRow.size() == 2 || i == regions.size() - 1) {
                    keyboard.add(new ArrayList<>(currentRow));
                    currentRow.clear();
                }
            }

            keyboard.add(row(
                    button("↩️ 账号列表", "back_to_traffic_list"),
                    button(BTN_BACK_MAIN, "back_to_main")
            ));

            markup.setKeyboard(keyboard);

            String text = "☁️ <b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n" +
                    String.format("🌍 共 <b>%d</b> 个区域\n", regions.size()) +
                    DIVIDER_THIN + "\n\n" +
                    "👇 <i>点击区域查询本月流量</i>";

            sendOrEdit(chatId, messageId, text, markup);
        } catch (Exception e) {
            log.error("加载流量区域列表失败: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "加载区域列表失败：" + safe(e.getMessage()),
                    trafficBackToListMarkup());
        }
    }

    private void queryAndShowRegionTraffic(Long chatId, Integer messageId, Long regionId, boolean isRefresh) {
        Tenant region;
        try {
            region = getTenantService().getById(regionId);
        } catch (Exception e) {
            sendOrEdit(chatId, messageId,
                    "获取区域信息失败：" + safe(e.getMessage()),
                    trafficBackToListMarkup());
            return;
        }
        if (region == null) {
            sendOrEdit(chatId, messageId, "⚠️ 未找到该区域信息", trafficBackToListMarkup());
            return;
        }

        Long parenId = region.getParenId();
        if (parenId == null || parenId == 0L) parenId = region.getId();
        final Long backParentId = parenId;

        String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";
        String loadingText = "🌍 <b>" + escape(regionName) + "</b>\n" + DIVIDER + "\n\n" +
                (isRefresh ? "🔄 正在重新查询…" : "⏳ 正在查询本月流量，请稍候…");

        sendOrEdit(chatId, messageId, loadingText, null);

        new Thread(() -> {
            TenantTrafficStats stats;
            try {
                stats = getInstanceTrafficTask().queryTenantTraffic(region);
            } catch (Exception e) {
                log.error("查询流量失败 regionId={}: {}", regionId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>查询失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        trafficResultMarkup(regionId, backParentId));
                return;
            }
            String text = renderTrafficStats(stats, region);
            sendOrEdit(chatId, messageId, text, trafficResultMarkup(regionId, backParentId));
        }, "tg-traffic-" + regionId).start();
    }

    private String renderTrafficStats(TenantTrafficStats stats, Tenant region) {
        StringBuilder sb = new StringBuilder();
        String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";

        sb.append("📊 <b>本月流量统计</b>\n").append(DIVIDER).append("\n");
        sb.append("🌍 区域  ").append(escape(regionName)).append("\n");
        if (stats.getStartTime() != null && stats.getEndTime() != null) {
            sb.append("🗓 周期  ")
                    .append(stats.getStartTime().format(DATE_FMT))
                    .append(" ~ ")
                    .append(stats.getEndTime().format(DATE_FMT))
                    .append(" <i>(UTC)</i>\n");
        }

        if (!stats.isSuccess()) {
            sb.append("\n❌ 查询失败");
            if (StringUtils.isNotBlank(stats.getMessage())) {
                sb.append("：").append(escape(stats.getMessage()));
            }
            return sb.toString();
        }

        sb.append(DIVIDER_THIN).append("\n");
        sb.append("📤 总出站  <b>").append(formatGB(stats.getTotalEgressGB())).append(" GB</b>\n");
        if (stats.getThresholdGB() != null && stats.getThresholdGB() > 0) {
            double ratio = stats.getTotalEgressGB() / stats.getThresholdGB();
            double diff = stats.getTotalEgressGB() - stats.getThresholdGB();
            // 用量可视化进度条 + 分级预警
            String alertIcon = ratio >= 1.0 ? "🚨" : ratio >= 0.8 ? "⚠️" : "🟢";
            sb.append(alertIcon).append(" 用量  ").append(progressBar(ratio))
                    .append("  <b>").append(String.format("%.0f%%", Math.min(ratio, 9.99) * 100)).append("</b>\n");
            sb.append("🎯 阈值  ").append(formatGB(stats.getThresholdGB())).append(" GB");
            if (diff > 0) {
                sb.append("　🔺 已超出 <b>").append(formatGB(diff)).append(" GB</b>");
            } else {
                sb.append("　✅ 剩余 ").append(formatGB(-diff)).append(" GB");
            }
            sb.append("\n");
            if (Boolean.TRUE.equals(stats.getAutoShutdown())) {
                sb.append("🛡 自动关机  已开启\n");
            }
        } else {
            sb.append("🎯 阈值  <i>未配置</i>\n");
        }
        sb.append("\n");

        List<TenantTrafficStats.InstanceTraffic> instances = stats.getInstances();
        if (instances == null || instances.isEmpty()) {
            sb.append("📭 暂无实例");
            if (StringUtils.isNotBlank(stats.getMessage())) {
                sb.append("\n").append(escape(stats.getMessage()));
            }
            sb.append("\n\n");
        } else {
            sb.append("🖥 <b>实例明细</b>\n");
            int idx = 1;
            for (TenantTrafficStats.InstanceTraffic ins : instances) {
                String name = StringUtils.isNotBlank(ins.getInstanceName())
                        ? ins.getInstanceName() : "instance-" + idx;
                String ip = StringUtils.isNotBlank(ins.getPublicIp()) ? ins.getPublicIp() : "无公网IP";
                sb.append("<b>").append(idx).append(".</b> ").append(escape(name)).append("\n");
                sb.append("　🌐 ").append(escape(ip))
                        .append(" · 📤 ").append(formatGB(ins.getEgressGB())).append(" GB")
                        .append("\n");
                idx++;
            }
            sb.append("\n");
        }
        sb.append("🕐 <i>更新时间：").append(LocalDateTime.now().format(TIME_FMT)).append("</i>");
        return sb.toString();
    }

    private InlineKeyboardMarkup trafficResultMarkup(Long regionId, Long parentId) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button(BTN_REFRESH, "traffic_refresh_" + regionId),
                button("↩️ 区域列表", "traffic_back_regions_" + parentId)
        ));
        kb.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(kb);
        return markup;
    }

    private InlineKeyboardMarkup trafficBackToListMarkup() {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("↩️ 账号列表", "back_to_traffic_list"),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(kb);
        return markup;
    }

    private String formatGB(double gb) {
        return String.format("%.2f", gb);
    }

    // ============== 配额查询功能 ==============

    private void showQuotaServiceMenu(Long chatId, Integer messageId, Long regionId) {
        try {
            Tenant region = getTenantService().getById(regionId);
            if (region == null) {
                sendOrEdit(chatId, messageId, "⚠️ 未找到该区域信息", onlyBackToMainMarkup());
                return;
            }
            String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();
            keyboard.add(row(
                    button("🖥 计算", "quota_svc_" + regionId + "_compute"),
                    button("💾 块存储", "quota_svc_" + regionId + "_block-storage"),
                    button("🗄 对象存储", "quota_svc_" + regionId + "_object-storage")
            ));
            keyboard.add(row(
                    button("🐬 MySQL", "quota_svc_" + regionId + "_mysql"),
                    button("🔶 Oracle DB", "quota_svc_" + regionId + "_database"),
                    button("🤖 ADB", "quota_svc_" + regionId + "_autonomous-database")
            ));
            keyboard.add(row(
                    button("📦 NoSQL", "quota_svc_" + regionId + "_nosql"),
                    button(BTN_BACK, "region_info_" + regionId),
                    button(BTN_BACK_MAIN, "back_to_main")
            ));
            markup.setKeyboard(keyboard);

            String text = "📊 <b>配额查询 · " + escape(regionName) + "</b>\n" + DIVIDER + "\n\n" +
                    "👇 <i>请选择要查询的服务类型</i>";
            sendOrEdit(chatId, messageId, text, markup);
        } catch (Exception e) {
            log.error("加载配额服务菜单失败: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId, "加载失败：" + safe(e.getMessage()), onlyBackToMainMarkup());
        }
    }

    private void queryAndShowQuota(Long chatId, Integer messageId, Long tenantId, String serviceName, boolean isRefresh) {
        fetchAndShowQuotaPage(chatId, messageId, tenantId, serviceName, 0, isRefresh);
    }

    private void showQuotaPage(Long chatId, Integer messageId, Long tenantId, String serviceName, int page) {
        fetchAndShowQuotaPage(chatId, messageId, tenantId, serviceName, page, false);
    }

    /**
     * 通用分页查询配额并展示：服务端分页，每次只对当页条目调用 getResourceAvailability，
     * 避免 compute 等服务一次性拉取大量数据导致超时。
     */
    private void fetchAndShowQuotaPage(Long chatId, Integer messageId, Long tenantId,
                                       String serviceName, int page, boolean isRefresh) {
        Tenant tenant;
        try {
            tenant = getTenantService().getById(tenantId);
        } catch (Exception e) {
            sendOrEdit(chatId, messageId, "获取区域信息失败：" + safe(e.getMessage()), onlyBackToMainMarkup());
            return;
        }
        if (tenant == null) {
            sendOrEdit(chatId, messageId, "⚠️ 未找到该区域信息", onlyBackToMainMarkup());
            return;
        }

        String regionName = tenant.getRegion() != null ? tenant.getRegion() : "未知区域";
        String svcLabel = quotaServiceLabel(serviceName);
        String loadingText = "📊 <b>配额查询 · " + escape(regionName) + "</b>\n" + DIVIDER + "\n\n" +
                "🔧 服务  " + svcLabel + "\n" +
                (isRefresh ? "🔄 正在重新查询…" : page == 0 ? "⏳ 正在查询配额，请稍候…" : "⏳ 正在加载第 " + (page + 1) + " 页…");
        sendOrEdit(chatId, messageId, loadingText, null);

        final Tenant finalTenant = tenant;
        new Thread(() -> {
            Map<String, Object> pagedResult;
            try {
                pagedResult = OciLimitsUtils.getSingleServiceQuotasPaged(finalTenant, serviceName, page, QUOTA_TG_PAGE_SIZE);
            } catch (Exception e) {
                log.error("查询配额失败 tenantId={} service={}: {}", tenantId, serviceName, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>查询失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        quotaResultMarkup(tenantId, serviceName, 0, false));
                return;
            }
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> items = (List<Map<String, Object>>) pagedResult.get("items");
            int curPage = ((Number) pagedResult.get("page")).intValue();
            boolean hasNextPage = Boolean.TRUE.equals(pagedResult.get("hasNextPage"));

            String text = renderQuotaResult(items, regionName, svcLabel, curPage, hasNextPage);
            sendOrEdit(chatId, messageId, text, quotaResultMarkup(tenantId, serviceName, curPage, hasNextPage));
        }, "tg-quota-" + tenantId).start();
    }

    private String renderQuotaResult(List<Map<String, Object>> items, String regionName, String svcLabel,
                                     int page, boolean hasNextPage) {
        StringBuilder sb = new StringBuilder();
        sb.append("📊 <b>配额查询结果</b>\n").append(DIVIDER).append("\n");
        sb.append("🌍 区域  ").append(escape(regionName)).append("\n");
        sb.append("🔧 服务  ").append(svcLabel);
        if (page > 0 || hasNextPage) {
            sb.append("  <i>· 第 ").append(page + 1).append(" 页</i>");
        }
        sb.append("\n").append(DIVIDER_THIN).append("\n\n");

        if (items == null || items.isEmpty()) {
            sb.append("📭 暂无配额数据。\n");
        } else {
            for (Map<String, Object> item : items) {
                String name = String.valueOf(item.getOrDefault("name", ""));
                long total = toLong(item.get("total"));
                long used = toLong(item.get("used"));
                long available = toLong(item.get("available"));
                String typeLabel = quotaInstanceTypeLabel(name);
                sb.append("▫️ <code>").append(escape(name)).append("</code>");
                if (typeLabel != null) sb.append("  <i>").append(typeLabel).append("</i>");
                sb.append("\n");
                if (total > 0) {
                    double ratio = (double) used / total;
                    sb.append("　").append(progressBar(ratio))
                            .append(" ").append(String.format("%.0f%%", ratio * 100));
                    sb.append("　已用 ").append(used).append("/").append(total)
                            .append(" · 可用 <b>").append(available).append("</b>\n");
                } else {
                    sb.append("　总量 ").append(total)
                            .append(" · 已用 ").append(used)
                            .append(" · 可用 ").append(available).append("\n");
                }
            }
        }

        sb.append("\n🕐 <i>更新时间：").append(LocalDateTime.now().format(TIME_FMT)).append("</i>");
        return sb.toString();
    }

    private long toLong(Object obj) {
        if (obj == null) return 0L;
        if (obj instanceof Number) return ((Number) obj).longValue();
        try { return Long.parseLong(String.valueOf(obj)); } catch (Exception e) { return 0L; }
    }

    private String quotaServiceLabel(String serviceName) {
        switch (serviceName) {
            case "compute":            return "计算 (Compute)";
            case "block-storage":      return "块存储 (Block Storage)";
            case "object-storage":     return "对象存储 (Object Storage)";
            case "mysql":              return "MySQL HeatWave";
            case "database":           return "Oracle Database (DBCS)";
            case "autonomous-database":return "自治数据库 (ADB)";
            case "nosql":              return "NoSQL Database";
            default:                   return escape(serviceName);
        }
    }

    /**
     * 根据 OCI compute limit name 命名规律推断实例类型标签，非 compute 限额返回 null。
     * 命名规则：standard-a1/a2=Ampere, e2=AMD旧款, e3~e5=AMD新款,
     *          x9=Intel新款, standard2/3/optimized3=Intel旧款,
     *          bm-前缀=裸金属, gpu=GPU, hpc=HPC
     */
    private String quotaInstanceTypeLabel(String name) {
        if (name == null) return null;
        String n = name.toLowerCase();
        boolean bm = n.startsWith("bm-");
        String arch = null;
        if      (n.contains("-a1-") || n.contains("-a2-"))          arch = "Ampere";
        else if (n.contains("-e5-"))                                 arch = "AMD E5";
        else if (n.contains("-e4-"))                                 arch = "AMD E4";
        else if (n.contains("-e3-"))                                 arch = "AMD E3";
        else if (n.contains("-e2-") || n.contains("e2-1-micro"))    arch = "AMD E2";
        else if (n.contains("gpu"))                                  arch = "GPU";
        else if (n.contains("hpc"))                                  arch = "HPC";
        else if (n.contains("optimized3"))                           arch = "Intel 高频";
        else if (n.contains("-x9-") || n.contains("x9-"))           arch = "Intel X9";
        else if (n.contains("-x8-"))                                 arch = "Intel X8";
        else if (n.contains("-x7-"))                                 arch = "Intel X7";
        else if (n.contains("standard3"))                            arch = "Intel";
        else if (n.contains("standard2"))                            arch = "Intel 旧款";
        else if (n.contains("dense-a4-ax"))                          arch = "DenseIO A4 AX";
        else if (n.contains("dense-io") || n.contains("denseio"))   arch = "DenseIO";
        else if (n.contains("autonomous-") || n.contains("-adb-") || n.startsWith("adb-")) arch = "ADB";
        else if (n.contains("mysql"))                                arch = "MySQL";
        else if (n.contains("nosql"))                                arch = "NoSQL";
        else if (n.contains("exadata"))                              arch = "Exadata";
        else if (n.contains("db-system") || n.contains("db-vcpu") || n.contains("db-node")) arch = "DBCS";
        if (arch == null) return bm ? "裸金属" : null;
        return bm ? "裸金属·" + arch : arch;
    }

    private InlineKeyboardMarkup quotaResultMarkup(Long regionId, String serviceName, int page, boolean hasNextPage) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button(BTN_REFRESH, "quota_refresh_" + regionId + "_" + serviceName),
                button("↩️ 返回区域", "region_info_" + regionId)
        ));
        if (page > 0 || hasNextPage) {
            List<InlineKeyboardButton> pageRow = new ArrayList<>();
            if (page > 0) {
                pageRow.add(button(BTN_LAST_PAGE, "quota_page_" + regionId + "_" + serviceName + "_" + (page - 1)));
            }
            if (hasNextPage) {
                pageRow.add(button(BTN_NEXT_PAGE, "quota_page_" + regionId + "_" + serviceName + "_" + (page + 1)));
            }
            if (!pageRow.isEmpty()) {
                kb.add(pageRow);
            }
        }
        kb.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(kb);
        return markup;
    }

    // ============== 通用工具 ==============

    /**
     * 根据当前时间返回问候语，让主菜单更有温度
     */
    private String greeting() {
        int hour = LocalDateTime.now().getHour();
        if (hour >= 5 && hour < 9)   return "🌅 早上好";
        if (hour >= 9 && hour < 12)  return "☀️ 上午好";
        if (hour >= 12 && hour < 14) return "🌤 中午好";
        if (hour >= 14 && hour < 18) return "🌇 下午好";
        if (hour >= 18 && hour < 23) return "🌙 晚上好";
        return "🌌 夜深了";
    }

    /**
     * 用量可视化进度条，例如 ▰▰▰▰▰▰▱▱▱▱
     * @param ratio 0.0 ~ 1.0（超过 1.0 显示为满格）
     */
    private String progressBar(double ratio) {
        final int totalBlocks = 10;
        int filled = (int) Math.round(Math.max(0, Math.min(1.0, ratio)) * totalBlocks);
        StringBuilder bar = new StringBuilder();
        for (int i = 0; i < totalBlocks; i++) {
            bar.append(i < filled ? "▰" : "▱");
        }
        return bar.toString();
    }

    /**
     * 应答回调查询：让客户端按钮上的加载动画立即消失。
     * 不调用此方法时，Telegram 客户端会在按钮上转圈直到超时（约 15~30 秒），体验很卡。
     */
    private void answerCallback(String callbackQueryId) {
        try {
            execute(AnswerCallbackQuery.builder()
                    .callbackQueryId(callbackQueryId)
                    .build());
        } catch (TelegramApiException e) {
            // 回调过期等情况可安全忽略
            log.debug("应答回调失败（可忽略）: {}", e.getMessage());
        }
    }

    /**
     * 仅返回主菜单的键盘
     */
    private InlineKeyboardMarkup onlyBackToMainMarkup() {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(kb);
        return markup;
    }

    private InlineKeyboardMarkup backToTenantListMarkup() {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("↩️ 账号列表", "back_to_tenant_list"),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(kb);
        return markup;
    }

    private InlineKeyboardButton button(String text, String callback) {
        InlineKeyboardButton b = new InlineKeyboardButton();
        b.setText(text);
        b.setCallbackData(callback);
        return b;
    }

    private List<InlineKeyboardButton> row(InlineKeyboardButton... buttons) {
        List<InlineKeyboardButton> row = new ArrayList<>();
        Collections.addAll(row, buttons);
        return row;
    }

    private List<InlineKeyboardButton> pageNavRow(int page, int totalPage, String callbackPrefix) {
        List<InlineKeyboardButton> navRow = new ArrayList<>();
        if (page > 1) {
            navRow.add(button(BTN_LAST_PAGE, callbackPrefix + (page - 1)));
        }
        if (page < totalPage) {
            navRow.add(button(BTN_NEXT_PAGE, callbackPrefix + (page + 1)));
        }
        return navRow;
    }

    private String resolveDisplayName(Tenant tenant) {
        String defName = tenant.getDefName();
        if (StringUtils.isBlank(defName) || "未设置".equals(defName)) {
            return tenant.getTenancyName() != null ? tenant.getTenancyName() : "未命名";
        }
        return defName;
    }

    private String safe(String s) {
        if (s == null) return "";
        return escape(s);
    }

    /**
     * HTML 转义（Telegram HTML 模式）
     */
    private String escape(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }

    /**
     * 发送或编辑菜单：如果传入了 messageId，则在原消息上编辑；否则发送新消息。
     * 用于实现"菜单不重复打开"的体验。
     */
    private void sendOrEdit(Long chatId, Integer messageId, String text, InlineKeyboardMarkup markup) {
        if (messageId != null) {
            try {
                EditMessageText.EditMessageTextBuilder builder = EditMessageText.builder()
                        .chatId(chatId)
                        .messageId(messageId)
                        .text(text)
                        .parseMode("HTML")
                        .disableWebPagePreview(true);
                if (markup != null) {
                    builder.replyMarkup(markup);
                }
                execute(builder.build());
                return;
            } catch (TelegramApiException e) {
                String msg = e.getMessage() == null ? "" : e.getMessage();
                if (msg.contains("message is not modified")) {
                    return;
                }
                // 老消息无法编辑（超过 48 小时）等情况：退化为发送新消息
                log.warn("编辑消息失败，将以新消息发送: {}", msg);
            }
        }
        try {
            SendMessage.SendMessageBuilder builder = SendMessage.builder()
                    .chatId(chatId)
                    .text(text)
                    .parseMode("HTML")
                    .disableWebPagePreview(true);
            if (markup != null) {
                builder.replyMarkup(markup);
            }
            execute(builder.build());
        } catch (TelegramApiException e) {
            log.error("发送消息失败: {}", e.getMessage());
        }
    }

    /**
     * 发送文本消息（自动处理超长消息分段）
     */
    private void sendTextMessage(Long chatId, String text) {
        try {
            if (text.length() <= 4096) {
                SendMessage message = SendMessage.builder()
                        .chatId(chatId)
                        .text(text)
                        .build();
                execute(message);
            } else {
                // 超长消息分段发送
                List<String> parts = splitMessage(text, 4096);
                for (String part : parts) {
                    SendMessage message = SendMessage.builder()
                            .chatId(chatId)
                            .text(part)
                            .build();
                    execute(message);
                }
            }
        } catch (TelegramApiException e) {
            if (e.getMessage().contains("Connection refused") ||
                    e.getMessage().contains("timeout")) {
                log.warn("网络连接问题，消息发送失败: {}", e.getMessage());
            } else {
                log.error("发送消息失败: {}", e.getMessage());
            }
        }
    }

    @Override
    public void afterPropertiesSet() throws Exception {
        log.info("TelegramBotCus启动中...");
    }



    private void handleAiChat(Long chatId, Long userId, String userMessage) {
        ChatAiService chatAiService = getChatAiService();

        // 发送"思考中"占位消息，获取消息ID用于后续编辑
        Integer placeholderMessageId;
        try {
            SendMessage placeholder = SendMessage.builder()
                    .chatId(chatId)
                    .text("💭 思考中…")
                    .build();
            Message sent = execute(placeholder);
            placeholderMessageId = sent.getMessageId();
        } catch (TelegramApiException e) {
            log.error("发送占位消息失败: {}", e.getMessage());
            return;
        }

        // 在异步线程中执行流式对话
        new Thread(() -> {
            try {
                StringBuilder fullReply = new StringBuilder();
                long[] lastEditTime = {System.currentTimeMillis()};
                final long EDIT_INTERVAL_MS = 1500; // 每1.5秒更新一次消息

                chatAiService.chatStream(String.valueOf(userId), userMessage, null, chunk -> {
                    fullReply.append(chunk);

                    long now = System.currentTimeMillis();
                    if (now - lastEditTime[0] >= EDIT_INTERVAL_MS) {
                        lastEditTime[0] = now;
                        String currentText = "" + fullReply.toString();
                        // Telegram消息限制4096字符，编辑时截取前4000字符显示
                        if (currentText.length() > 4000) {
                            currentText = currentText.substring(0, 4000) + "\n\n✍️ 回复较长，继续生成中…";
                        }
                        editMessage(chatId, placeholderMessageId, currentText);
                    }
                });

                // 流式结束，发送最终完整回复
                String finalText = fullReply.toString();
                if (StringUtils.isBlank(finalText)) {
                    editMessage(chatId, placeholderMessageId, "😥 抱歉，我无法回答你的问题。");
                    return;
                }

                // 处理最终消息：如果超过4096字符，需要分段发送
                String prefix = "";
                String fullText = prefix + finalText;
                if (fullText.length() <= 4096) {
                    editMessage(chatId, placeholderMessageId, fullText);
                } else {
                    // 第一条消息使用edit更新占位消息
                    List<String> parts = splitMessage(fullText, 4096);
                    editMessage(chatId, placeholderMessageId, parts.get(0));
                    // 后续分段作为新消息发送
                    for (int i = 1; i < parts.size(); i++) {
                        sendTextMessage(chatId, parts.get(i));
                    }
                }
            } catch (Exception e) {
                log.error("流式AI对话异常: {}", e.getMessage(), e);
                editMessage(chatId, placeholderMessageId, "😥 抱歉，AI 服务暂时不可用，请稍后重试。");
            }
        }, "tg-ai-stream-" + userId).start();
    }

    /**
     * 编辑已发送的消息
     */
    private void editMessage(Long chatId, Integer messageId, String text) {
        try {
            EditMessageText editMessage = EditMessageText.builder()
                    .chatId(chatId)
                    .messageId(messageId)
                    .text(text)
                    .build();
            execute(editMessage);
        } catch (TelegramApiException e) {
            // "message is not modified" 是正常的（内容没变化时会报这个错）
            if (!e.getMessage().contains("message is not modified")) {
                log.warn("编辑消息失败: {}", e.getMessage());
            }
        }
    }

    /**
     * 将长文本按指定长度分段，尽量在换行符处分割
     */
    private List<String> splitMessage(String text, int maxLength) {
        List<String> parts = new ArrayList<>();
        while (text.length() > maxLength) {
            // 尝试在换行符处分割
            int splitIndex = text.lastIndexOf('\n', maxLength);
            if (splitIndex <= 0 || splitIndex < maxLength / 2) {
                // 没有合适的换行符，在空格处分割
                splitIndex = text.lastIndexOf(' ', maxLength);
            }
            if (splitIndex <= 0 || splitIndex < maxLength / 2) {
                // 实在找不到合适位置，硬切
                splitIndex = maxLength;
            }
            parts.add(text.substring(0, splitIndex));
            text = text.substring(splitIndex).trim();
        }
        if (!text.isEmpty()) {
            parts.add(text);
        }
        return parts;
    }

    private void sendBootLogPage(Long chatId, Integer messageId, int pageNum) {
        Pageable pageable = PageRequest.of(pageNum - 1, PAGE_SIZE_BOOT_LOG);

        DynamicDailyTask task = applicationContext.getBean(DynamicDailyTask.class);
        Page<BootInstanceRes> bootPage = task.getBootList(pageable);

        if (bootPage.isEmpty()) {
            sendOrEdit(chatId, messageId,
                    "📋 <b>开机日志</b>\n" + DIVIDER + "\n\n📭 暂无开机日志记录。",
                    onlyBackToMainMarkup());
            return;
        }

        // 获取分页元数据
        int totalPages = bootPage.getTotalPages();
        int currentPage = bootPage.getNumber() + 1; // 转换为 1 基准供用户查看

        // 3. 构建正文
        StringBuilder sb = new StringBuilder();
        sb.append("📋 <b>预开机统计</b>\n").append(DIVIDER).append("\n");
        sb.append("📄 第 <b>").append(currentPage).append("</b>/<b>").append(totalPages).append("</b> 页\n")
                .append(DIVIDER_THIN).append("\n\n");

        List<BootInstanceRes> content = bootPage.getContent();
        for (int i = 0; i < content.size(); i++) {
            BootInstanceRes item = content.get(i);

            String displayName;
            final String defName = item.getDefName();
            if (StringUtils.isEmpty(defName) || "未设置".equals(defName)){
                displayName = item.getTenancyName();
            }else{
                displayName = item.getDefName();
            }

            // 计算当前页显示的序号
            int num = (currentPage - 1) * PAGE_SIZE_BOOT_LOG + i + 1;
            // 先转义再加 spoiler 标签，避免 escape() 把 <tg-spoiler> 标签也转义掉
            String maskedDisplayName = getMaskedDisplayName(escape(displayName));
            sb.append("<b>").append(num).append(".</b> ")
                    .append(maskedDisplayName)
                    .append("\n")
                    .append("　🌍 ").append(escape(safeStr(item.getRegionName())))
                    .append(" · 🧬 ").append(escape(safeStr(item.getArchitecture())))
                    .append(" · ").append(escape(BootInstanceStatusEnum.getStatus(item.getStatus()).getName()))
                    .append("\n")
                    .append("　🗓 ").append(escape(safeStr(item.getCreateAtStr())))
                    .append(" · 已运行 ").append(daysBetweenCurrent(item.getCreateAtStr())).append(" 天\n")
                    .append("　🎯 总计 ").append(item.getAddCount())
                    .append(" · 昨日 ").append(item.getYesterdayAttemptCount())
                    .append(" · 今日 ").append(item.getCurrentAttemptCount())
                    .append(" · ✅ 成功 <b>").append(item.getSuccessCount()).append("</b>")
                    .append("\n\n");
        }

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        List<InlineKeyboardButton> navRow = new ArrayList<>();
        if (bootPage.hasPrevious()) {
            navRow.add(button(BTN_LAST_PAGE, "boot_log_page_" + (currentPage - 1)));
        }
        if (bootPage.hasNext()) {
            navRow.add(button(BTN_NEXT_PAGE, "boot_log_page_" + (currentPage + 1)));
        }
        if (!navRow.isEmpty()) keyboard.add(navRow);

        keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(keyboard);

        sendOrEdit(chatId, messageId, sb.toString(), markup);
    }

    private String safeStr(String s) {
        return s == null ? "" : s;
    }

    private void showUpgradeMenu(Long chatId, Integer messageId) {
        try {
            VersionCheckTask versionCheckTask = getVersionCheckTask();

            versionCheckTask.checkVersion();

            AppVersion version = versionCheckTask.getVersion();
            String current = version.getCurrentVersion();
            String latest = version.getLatestVersion();
            boolean needUpdate = version.needUpdate();

            StringBuilder sb = new StringBuilder();
            sb.append("🚀 <b>系统版本状态</b>\n").append(DIVIDER).append("\n\n");
            sb.append("📌 当前版本  <code>").append(escape(safeStr(current))).append("</code>\n");
            sb.append("☁️ 最新版本  <code>").append(escape(safeStr(latest))).append("</code>\n");
            sb.append(DIVIDER_THIN).append("\n");

            if (!needUpdate) {
                sb.append("✅ <b>您已是最新版本，无需升级</b>");
            } else {
                sb.append("🆕 <b>检测到新版本，可一键升级</b>");
            }

            // —— 构建按钮 ——
            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 需要升级才显示
            if (needUpdate) {
                keyboard.add(Collections.singletonList(button("🚀 立即升级", "do_upgrade")));
            }

            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));

            markup.setKeyboard(keyboard);

            sendOrEdit(chatId, messageId, sb.toString(), markup);

        } catch (Exception e) {
            log.error("展示升级菜单失败: {}", e.getMessage());
            sendOrEdit(chatId, messageId,
                    "❌ 获取版本信息失败：" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }

    private void handleUpdateInstances(Long chatId, Integer messageId, Long regionId) {
        sendOrEdit(chatId, messageId,
                "🔄 <b>正在同步实例信息</b>\n" + DIVIDER + "\n\n⏳ 请稍候…",
                null);
        new Thread(() -> {
            try {
                getTenantService().syncOci(regionId);
            } catch (Exception e) {
                log.error("同步实例失败: {}", e.getMessage());
                sendOrEdit(chatId, messageId,
                        "❌ <b>同步失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        onlyBackToMainMarkup());
                return;
            }
            // 同步完成后直接刷新区域实例视图
            showRegionInfo(chatId, messageId, regionId);
        }, "tg-update-instances-" + regionId).start();
    }

    // ============== 实例操作功能 ==============

    private InstanceDetailsRes findInstanceById(Long regionId, Long dbId) {
        try {
            com.doubledimple.dao.entity.InstanceDetails entity = getOracleInstanceService().getInstanceById(dbId);
            if (entity == null) return null;
            InstanceDetailsRes res = new InstanceDetailsRes();
            org.springframework.beans.BeanUtils.copyProperties(entity, res);
            res.setId(entity.getId().toString());
            return res;
        } catch (Exception e) {
            log.error("查询实例失败 regionId={} dbId={}: {}", regionId, dbId, e.getMessage());
            return null;
        }
    }

    private InlineKeyboardMarkup instanceBackMarkup(Long regionId, Long dbId) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("↩️ 返回实例", "inst_d_" + regionId + "_" + dbId),
                button("↩️ 返回区域", "region_info_" + regionId)
        ));
        kb.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(kb);
        return markup;
    }

    private InlineKeyboardMarkup backRegionMarkup(Long regionId) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button(BTN_BACK, "region_info_" + regionId),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(kb);
        return markup;
    }

    private void showInstanceActions(Long chatId, Integer messageId, Long regionId, Long dbId) {
        log.info("[TG-INST] showInstanceActions regionId={} dbId={}", regionId, dbId);
        try {
            InstanceDetailsRes instance = findInstanceById(regionId, dbId);
            log.info("[TG-INST] findInstanceById result: {}", instance != null ? instance.getDisplayName() : "NULL");
            if (instance == null) {
                sendTextMessage(chatId, "⚠️ 未找到实例信息 (regionId=" + regionId + ", dbId=" + dbId + ")，请刷新区域列表。");
                return;
            }

            String state = instance.getState() != null ? instance.getState().toUpperCase() : "";
            String arch = instance.getArchitecture() != null ? instance.getArchitecture() : "未知";
            String cpu = instance.getOcpus() != null ? instance.getOcpus() + "核" : "未知";
            String mem = instance.getMemoryInGBs() != null ? instance.getMemoryInGBs() + "GB" : "未知";
            String disk = instance.getBootVolumeSizeInGBs() != null ? instance.getBootVolumeSizeInGBs() + "GB" : "未知";
            String ip = instance.getPublicIps() != null && !instance.getPublicIps().isEmpty()
                    ? instance.getPublicIps() : "无公网IP";
            String name = instance.getDisplayName() != null ? instance.getDisplayName() : "未命名";
            boolean hasIpv6 = instance.getIpv6Addresses() != null && !instance.getIpv6Addresses().trim().isEmpty();

            StringBuilder sb = new StringBuilder();
            sb.append("🖥 <b>").append(escape(name)).append("</b>\n").append(DIVIDER).append("\n");
            sb.append("📍 状态  ").append(getStateIcon(state)).append("\n");
            sb.append("🌐 IP    <code>").append(escape(ip)).append("</code>\n");
            sb.append("⚙️ 配置  ").append(escape(arch)).append(" · ").append(cpu).append(" / ").append(mem).append("\n");
            sb.append("💾 磁盘  ").append(disk).append("\n");
            if (hasIpv6) {
                sb.append("🔷 IPv6  <code>").append(escape(instance.getIpv6Addresses())).append("</code>\n");
            }
            sb.append(DIVIDER_THIN).append("\n").append("👇 <i>选择操作</i>");

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 启动 / 停止 / 重启（根据当前状态显示）
            if ("STOPPED".equals(state)) {
                keyboard.add(Collections.singletonList(button("▶️ 启动实例", "inst_start_" + regionId + "_" + dbId)));
            } else if ("RUNNING".equals(state)) {
                keyboard.add(row(
                        button("⏹ 停止实例", "inst_stop_" + regionId + "_" + dbId),
                        button("🔁 重启实例", "inst_reboot_" + regionId + "_" + dbId)
                ));
            }

            // 更换IP + IPv6
            keyboard.add(row(
                    button("🔄 更换IPV4", "inst_cip_" + regionId + "_" + dbId),
                    button(hasIpv6 ? "🔷 刷新IPv6" : "🔷 启用IPv6", "inst_ipv6_" + regionId + "_" + dbId)
            ));

            // 修改配置 + 修改磁盘
            keyboard.add(row(
                    button("⚙️ 修改配置", "inst_cfg_" + regionId + "_" + dbId),
                    button("💾 修改磁盘", "inst_disk_" + regionId + "_" + dbId)
            ));

            // 删除记录 + 终止实例（危险操作行）
            keyboard.add(row(
                    button("🗑 删除记录", "inst_drec_" + regionId + "_" + dbId),
                    button("⚠️ 终止实例", "inst_term_" + regionId + "_" + dbId)
            ));

            // 刷新 + 返回区域
            keyboard.add(row(
                    button("🔄 刷新状态", "inst_d_" + regionId + "_" + dbId),
                    button(BTN_BACK, "region_info_" + regionId)
            ));
            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));

            markup.setKeyboard(keyboard);
            log.info("[TG-INST] 准备发送实例操作菜单, text长度={}", sb.length());
            sendOrEdit(chatId, messageId, sb.toString(), markup);

        } catch (Exception e) {
            log.error("[TG-INST] 显示实例操作菜单失败: {}", e.getMessage(), e);
            sendTextMessage(chatId, "❌ 加载实例操作菜单失败：" + e.getMessage());
        }
    }

    private void handleInstStart(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId, "▶️ <b>正在启动实例</b>\n" + DIVIDER + "\n\n⏳ 请稍候…", null);
        new Thread(() -> {
            try {
                boolean success = getOracleInstanceService().startInstance(dbId.toString());
                String resultText = success
                        ? "✅ <b>启动请求已发送</b>\n" + DIVIDER + "\n\n实例正在启动中，请稍后刷新查看状态。"
                        : "❌ <b>启动失败</b>\n" + DIVIDER + "\n\n请检查实例状态后重试。";
                sendOrEdit(chatId, messageId, resultText, instanceBackMarkup(regionId, dbId));
            } catch (Exception e) {
                log.error("启动实例失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>启动失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-start-" + dbId).start();
    }

    private void handleInstStop(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId, "⏹ <b>正在停止实例</b>\n" + DIVIDER + "\n\n⏳ 请稍候…", null);
        new Thread(() -> {
            try {
                boolean success = getOracleInstanceService().stopInstanceByInstanceId(dbId.toString());
                String resultText = success
                        ? "✅ <b>停止请求已发送</b>\n" + DIVIDER + "\n\n实例正在停止中，请稍后刷新查看状态。"
                        : "❌ <b>停止失败</b>\n" + DIVIDER + "\n\n请检查实例状态后重试。";
                sendOrEdit(chatId, messageId, resultText, instanceBackMarkup(regionId, dbId));
            } catch (Exception e) {
                log.error("停止实例失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>停止失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-stop-" + dbId).start();
    }

    private void handleInstTerminate(Long chatId, Integer messageId, Long regionId, Long dbId) {
        InstanceDetailsRes instance = findInstanceById(regionId, dbId);
        String name = instance != null && instance.getDisplayName() != null
                ? escape(instance.getDisplayName()) : "该实例";

        String text = "⚠️ <b>确认终止实例？</b>\n" + DIVIDER + "\n\n" +
                "🖥 实例：<b>" + name + "</b>\n\n" +
                "🚨 <b>此操作不可撤销！</b>\n终止后实例将被永久删除，数据无法恢复。\n\n" +
                "确认继续吗？";

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("✅ 确认终止", "inst_term_ok_" + regionId + "_" + dbId),
                button("❌ 取消", "inst_d_" + regionId + "_" + dbId)
        ));
        markup.setKeyboard(kb);
        sendOrEdit(chatId, messageId, text, markup);
    }

    private void handleInstTerminateConfirm(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId, "⚠️ <b>正在终止实例</b>\n" + DIVIDER + "\n\n⏳ 请稍候…", null);
        new Thread(() -> {
            try {
                getOracleInstanceService().killInstance(dbId);
                sendOrEdit(chatId, messageId,
                        "✅ <b>终止请求已发送</b>\n" + DIVIDER + "\n\n实例正在终止，稍后将从列表中消失。",
                        backRegionMarkup(regionId));
            } catch (Exception e) {
                log.error("终止实例失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>终止失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-term-" + dbId).start();
    }

    private void handleInstChangeIp(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId,
                "🔄 <b>正在更换IPV4</b>\n" + DIVIDER + "\n\n⏳ 请稍候，这可能需要一些时间…", null);
        new Thread(() -> {
            try {
                com.doubledimple.ociserver.pojo.request.IpSwitchRequest req =
                        com.doubledimple.ociserver.pojo.request.IpSwitchRequest.builder()
                                .tenantId(dbId)
                                .cidrRanges(new java.util.ArrayList<>())
                                .build();
                org.springframework.http.ResponseEntity<?> resp = getOracleInstanceService().switchToSpecificIpRange(req);
                if (resp.getStatusCode().is2xxSuccessful()) {
                    String newIp = "";
                    try {
                        @SuppressWarnings("unchecked")
                        java.util.Map<String, Object> body = (java.util.Map<String, Object>) resp.getBody();
                        if (body != null && body.get("details") != null) {
                            @SuppressWarnings("unchecked")
                            java.util.Map<String, String> details = (java.util.Map<String, String>) body.get("details");
                            newIp = details.getOrDefault("newIp", "");
                        }
                    } catch (Exception ignored) {}
                    String resultText = newIp.isEmpty()
                            ? "✅ <b>IP更换成功</b>\n" + DIVIDER + "\n\n请刷新实例信息查看新IP。"
                            : "✅ <b>IP更换成功</b>\n" + DIVIDER + "\n\n🌐 新IP：<code>" + escape(newIp) + "</code>";
                    sendOrEdit(chatId, messageId, resultText, instanceBackMarkup(regionId, dbId));
                } else {
                    String errMsg = "";
                    try {
                        @SuppressWarnings("unchecked")
                        java.util.Map<String, Object> body = (java.util.Map<String, Object>) resp.getBody();
                        if (body != null) errMsg = String.valueOf(body.getOrDefault("message", ""));
                    } catch (Exception ignored) {}
                    sendOrEdit(chatId, messageId,
                            "❌ <b>IPV4更换失败</b>\n" + DIVIDER + "\n\n" + safe(errMsg),
                            instanceBackMarkup(regionId, dbId));
                }
            } catch (Exception e) {
                log.error("更换IPV4失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>更换IPV4失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-cip-" + dbId).start();
    }

    private void showInstConfigMenu(Long chatId, Integer messageId, Long regionId, Long dbId) {
        InstanceDetailsRes instance = findInstanceById(regionId, dbId);
        String name = instance != null && instance.getDisplayName() != null
                ? escape(instance.getDisplayName()) : "实例";
        String currentArch = instance != null && instance.getArchitecture() != null
                ? instance.getArchitecture().toLowerCase() : "";
        String currentCpu = instance != null && instance.getOcpus() != null ? instance.getOcpus() + "C" : "?";
        String currentMem = instance != null && instance.getMemoryInGBs() != null ? instance.getMemoryInGBs() + "GB" : "?";

        String text = "⚙️ <b>修改实例配置</b>\n" + DIVIDER + "\n" +
                "🖥 " + name + "\n" +
                "📌 当前  " + currentCpu + " / " + currentMem + "\n" +
                DIVIDER_THIN + "\n\n" +
                "👇 <i>选择新的 CPU / 内存配置</i>\n" +
                "<i>⚠️ 修改配置需要实例处于停止状态</i>";

        boolean isArm = currentArch.contains("aarch") || currentArch.contains("arm") || currentArch.contains("a1");

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        if (isArm) {
            keyboard.add(row(
                    button("1C / 6GB", "inst_cfs_" + regionId + "_" + dbId + "_1_6"),
                    button("2C / 12GB", "inst_cfs_" + regionId + "_" + dbId + "_2_12")
            ));
            keyboard.add(row(
                    button("4C / 24GB", "inst_cfs_" + regionId + "_" + dbId + "_4_24"),
                    button("6C / 36GB", "inst_cfs_" + regionId + "_" + dbId + "_6_36")
            ));
            keyboard.add(row(
                    button("8C / 48GB", "inst_cfs_" + regionId + "_" + dbId + "_8_48"),
                    button("16C / 96GB", "inst_cfs_" + regionId + "_" + dbId + "_16_96")
            ));
        } else {
            keyboard.add(row(
                    button("1C / 1GB (E2 Micro)", "inst_cfs_" + regionId + "_" + dbId + "_1_1"),
                    button("1C / 6GB", "inst_cfs_" + regionId + "_" + dbId + "_1_6")
            ));
            keyboard.add(row(
                    button("2C / 12GB", "inst_cfs_" + regionId + "_" + dbId + "_2_12"),
                    button("4C / 24GB", "inst_cfs_" + regionId + "_" + dbId + "_4_24")
            ));
        }

        keyboard.add(row(
                button(BTN_BACK, "inst_d_" + regionId + "_" + dbId),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(keyboard);
        sendOrEdit(chatId, messageId, text, markup);
    }

    private void handleInstConfigSet(Long chatId, Integer messageId, Long regionId, Long dbId, int cpu, int mem) {
        sendOrEdit(chatId, messageId,
                "⚙️ <b>正在修改配置</b>\n" + DIVIDER + "\n\n⏳ 设置 " + cpu + "核 / " + mem + "GB，请稍候…", null);
        new Thread(() -> {
            try {
                getOracleInstanceService().updateInstanceConfig(dbId.toString(), cpu, mem);
                sendOrEdit(chatId, messageId,
                        "✅ <b>配置修改成功</b>\n" + DIVIDER + "\n\n已更新为 <b>" + cpu + "核 / " + mem + "GB</b>。\n启动实例后生效。",
                        instanceBackMarkup(regionId, dbId));
            } catch (Exception e) {
                log.error("修改配置失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>配置修改失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-cfg-" + dbId).start();
    }

    private void showInstDiskMenu(Long chatId, Integer messageId, Long regionId, Long dbId) {
        InstanceDetailsRes instance = findInstanceById(regionId, dbId);
        String name = instance != null && instance.getDisplayName() != null
                ? escape(instance.getDisplayName()) : "实例";
        String current = instance != null && instance.getBootVolumeSizeInGBs() != null
                ? instance.getBootVolumeSizeInGBs() + "GB" : "未知";

        String text = "💾 <b>修改磁盘大小</b>\n" + DIVIDER + "\n" +
                "🖥 " + name + "\n" +
                "💾 当前磁盘  <b>" + current + "</b>\n" +
                DIVIDER_THIN + "\n\n" +
                "👇 <i>选择新的磁盘大小</i>\n" +
                "<i>⚠️ 扩容无需停机，缩容可能造成数据丢失</i>";

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();
        keyboard.add(row(
                button("50 GB",  "inst_dsk_" + regionId + "_" + dbId + "_50"),
                button("100 GB", "inst_dsk_" + regionId + "_" + dbId + "_100")
        ));
        keyboard.add(row(
                button("150 GB", "inst_dsk_" + regionId + "_" + dbId + "_150"),
                button("200 GB", "inst_dsk_" + regionId + "_" + dbId + "_200")
        ));
        keyboard.add(row(
                button("300 GB", "inst_dsk_" + regionId + "_" + dbId + "_300"),
                button("400 GB", "inst_dsk_" + regionId + "_" + dbId + "_400")
        ));
        keyboard.add(row(
                button(BTN_BACK, "inst_d_" + regionId + "_" + dbId),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(keyboard);
        sendOrEdit(chatId, messageId, text, markup);
    }

    private void handleInstDiskSet(Long chatId, Integer messageId, Long regionId, Long dbId, long sizeGb) {
        sendOrEdit(chatId, messageId,
                "💾 <b>正在调整磁盘大小</b>\n" + DIVIDER + "\n\n⏳ 设置为 " + sizeGb + "GB，请稍候…", null);
        new Thread(() -> {
            try {
                getOracleInstanceService().handleExpansion(dbId.toString(), sizeGb);
                sendOrEdit(chatId, messageId,
                        "✅ <b>磁盘调整请求已发送</b>\n" + DIVIDER + "\n\n已设置为 <b>" + sizeGb + "GB</b>，请稍后刷新查看。",
                        instanceBackMarkup(regionId, dbId));
            } catch (Exception e) {
                log.error("磁盘调整失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>磁盘调整失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-disk-" + dbId).start();
    }

    private void handleInstIpv6(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId, "🔷 <b>正在处理IPv6</b>\n" + DIVIDER + "\n\n⏳ 请稍候…", null);
        new Thread(() -> {
            try {
                String ipv6 = getOracleInstanceService().enableOrRefreshIpv6(dbId, false);
                String resultText = ipv6 != null && !ipv6.isEmpty()
                        ? "✅ <b>IPv6 处理成功</b>\n" + DIVIDER + "\n\n🔷 IPv6 地址：<code>" + escape(ipv6) + "</code>"
                        : "✅ <b>IPv6 请求已发送</b>\n" + DIVIDER + "\n\n请稍后刷新实例信息查看IPv6地址。";
                sendOrEdit(chatId, messageId, resultText, instanceBackMarkup(regionId, dbId));
            } catch (Exception e) {
                log.error("处理IPv6失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>IPv6处理失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-ipv6-" + dbId).start();
    }

    private void handleInstDeleteRecord(Long chatId, Integer messageId, Long regionId, Long dbId) {
        InstanceDetailsRes instance = findInstanceById(regionId, dbId);
        String name = instance != null && instance.getDisplayName() != null
                ? escape(instance.getDisplayName()) : "该实例";

        String text = "🗑 <b>确认删除本地记录？</b>\n" + DIVIDER + "\n\n" +
                "🖥 实例：<b>" + name + "</b>\n\n" +
                "ℹ️ 此操作仅删除本地数据库记录，不会影响 OCI 云上的实例。\n\n" +
                "确认继续吗？";

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("✅ 确认删除", "inst_drec_ok_" + regionId + "_" + dbId),
                button("❌ 取消", "inst_d_" + regionId + "_" + dbId)
        ));
        markup.setKeyboard(kb);
        sendOrEdit(chatId, messageId, text, markup);
    }

    private void showInstRebootMenu(Long chatId, Integer messageId, Long regionId, Long dbId) {
        InstanceDetailsRes instance = findInstanceById(regionId, dbId);
        String name = instance != null && instance.getDisplayName() != null
                ? escape(instance.getDisplayName()) : "实例";

        String text = "🔁 <b>重启实例</b>\n" + DIVIDER + "\n" +
                "🖥 " + name + "\n" +
                DIVIDER_THIN + "\n\n" +
                "请选择重启方式：\n\n" +
                "🟢 <b>软重启 (SOFTRESET)</b> — 优雅关机后启动，推荐\n" +
                "🔴 <b>硬重启 (RESET)</b> — 强制断电重启，可能丢失未保存数据";

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("🟢 软重启 (推荐)", "inst_rbt_s_" + regionId + "_" + dbId),
                button("🔴 硬重启 (强制)", "inst_rbt_h_" + regionId + "_" + dbId)
        ));
        kb.add(row(
                button(BTN_BACK, "inst_d_" + regionId + "_" + dbId),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(kb);
        sendOrEdit(chatId, messageId, text, markup);
    }

    private void handleInstReboot(Long chatId, Integer messageId, Long regionId, Long dbId, boolean softReset) {
        String mode = softReset ? "软重启" : "硬重启";
        sendOrEdit(chatId, messageId,
                "🔁 <b>正在" + mode + "</b>\n" + DIVIDER + "\n\n⏳ 重启中，完成前请勿重复操作…", null);
        new Thread(() -> {
            try {
                Tenant region = getTenantService().getById(regionId);
                if (region == null) {
                    sendOrEdit(chatId, messageId, "❌ <b>重启失败</b>\n" + DIVIDER + "\n\n未找到租户信息。",
                            instanceBackMarkup(regionId, dbId));
                    return;
                }
                InstanceDetailsRes instance = findInstanceById(regionId, dbId);
                if (instance == null || instance.getInstanceId() == null) {
                    sendOrEdit(chatId, messageId, "❌ <b>重启失败</b>\n" + DIVIDER + "\n\n未找到实例信息。",
                            instanceBackMarkup(regionId, dbId));
                    return;
                }
                OciUtils.rebootInstance(region, instance.getInstanceId(), softReset);
                sendOrEdit(chatId, messageId,
                        "✅ <b>" + mode + "成功</b>\n" + DIVIDER + "\n\n实例已恢复运行状态。",
                        instanceBackMarkup(regionId, dbId));
            } catch (Exception e) {
                log.error("重启实例失败 dbId={}: {}", dbId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>" + mode + "失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        instanceBackMarkup(regionId, dbId));
            }
        }, "tg-inst-reboot-" + dbId).start();
    }

    private void handleInstDeleteRecordConfirm(Long chatId, Integer messageId, Long regionId, Long dbId) {
        try {
            getOracleInstanceService().deleteInstanceRecord(dbId);
            sendOrEdit(chatId, messageId,
                    "✅ <b>记录已删除</b>\n" + DIVIDER + "\n\n本地实例记录已成功删除。",
                    backRegionMarkup(regionId));
        } catch (Exception e) {
            log.error("删除实例记录失败 dbId={}: {}", dbId, e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "❌ <b>删除失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                    instanceBackMarkup(regionId, dbId));
        }
    }

    // 剧透处理

}