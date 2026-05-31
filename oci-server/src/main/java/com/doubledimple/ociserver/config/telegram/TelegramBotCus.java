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
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.ApplicationContext;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.telegram.telegrambots.bots.DefaultBotOptions;
import org.telegram.telegrambots.bots.TelegramLongPollingBot;
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

    private static final String DIVIDER = "━━━━━━━━━━━━━━━━━━━━";

    private static final String BTN_BACK_MAIN = "主菜单";
    private static final String BTN_LAST_PAGE = "« 上一页";
    private static final String BTN_NEXT_PAGE = "下一页 »";
    private static final String BTN_REFRESH = "刷新";

    private static final int PAGE_SIZE_TENANT = 10;
    private static final int PAGE_SIZE_BOOT_LOG = 5;

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
                sendTextMessage(chatId, "抱歉，您没有权限使用此机器人.");
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
                        sendTextMessage(chatId, "已成功封禁 IP：" + ip +
                                "\n如需解封，请执行：/unbanIp_" + ip.replace('.', '_'));
                    } else {
                        sendTextMessage(chatId, "封禁失败或已存在封禁记录：" + ip);
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
                        sendTextMessage(chatId, "已成功解除封禁 IP：" + ip +
                                "\n如需重新封禁，请执行：/banIp_" + ip.replace('.', '_'));
                    } else {
                        sendTextMessage(chatId, "未找到封禁记录或已解封：" + ip);
                    }
                } else {
                    sendTextMessage(chatId, "未识别 IP 地址，请检查命令格式。");
                }
                return;
            } else {
                // 检查用户权限
                if (!telegramUserService.isUserAuthorized(user.getId())) {
                    sendTextMessage(chatId, "抱歉，您没有权限使用此机器人.");
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

        log.debug("收到回调: {} 来自: {}", callbackData, chatId);

        try {
            TelegramUserService telegramUserService = getTelegramUserService();
            if (telegramUserService == null) {
                log.error("无法获取TelegramUserService，跳过回调处理");
                sendTextMessage(chatId, "系统服务暂时不可用，请稍后重试。");
                return;
            }

            // 检查用户权限
            if (!telegramUserService.isUserAuthorized(user.getId())) {
                sendTextMessage(chatId, "抱歉，您没有权限使用此机器人。");
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

                    /*else {
                        sendTextMessage(chatId, "未知操作: " + callbackData);
                    }*/
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
                sendTextMessage(chatId, "激活成功！欢迎使用 OCI-START 管理助手");
                sendMainMenu(chatId, null);
                telegramUserUpdate.setActive(true);
            }else{
                Boolean active = userDetail.getActive();
                if (null== active || !active){
                    sendTextMessage(chatId, "欢迎使用 OCI-START 管理助手");
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
                button("账号测活", "account_check"),
                button("版本检查", "system_upgrade")
        ));

        // 第二行：我的账号和本月流量
        keyboard.add(row(
                button("我的账号", "query_tenant"),
                button("本月流量", "monthly_traffic")
        ));

        // 第三行：开机日志和帮助
        keyboard.add(row(
                button("开机日志", "boot_log"),
                button("使用帮助", "help")
        ));

        // 第四行：GitHub
        InlineKeyboardButton githubBtn = new InlineKeyboardButton();
        githubBtn.setText("GitHub");
        githubBtn.setUrl("https://github.com/doubleDimple/oci-start");
        keyboard.add(Collections.singletonList(githubBtn));

        markup.setKeyboard(keyboard);

        String text = "<b>OCI-START 智能助手</b>\n" +
                DIVIDER + "\n\n" +
                "<i>请选择您要执行的操作</i>";

        sendOrEdit(chatId, messageId, text, markup);
    }

    /**
     * 处理账号测活功能
     */
    private void handleAccountCheck(Long chatId, Integer messageId) {
        sendOrEdit(chatId, messageId,
                "<b>账号测活</b>\n" + DIVIDER + "\n\n正在批量检测账号活跃状态，请稍候...",
                onlyBackToMainMarkup());
        new Thread(() -> {
            String resultText;
            try {
                AccountCheckRes res = getTenantService().checkBatchAccounts();
                resultText = formatAccountCheckResult(res);
            } catch (Exception e) {
                log.error("账号测活失败: {}", e.getMessage(), e);
                resultText = "<b>账号测活失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage());
            }
            sendOrEdit(chatId, messageId, resultText, onlyBackToMainMarkup());
        }, "tg-account-check-" + chatId).start();
    }

    private String formatAccountCheckResult(AccountCheckRes res) {
        if (res == null) {
            return "<b>账号测活完成</b>\n" + DIVIDER + "\n\n所有账号已完成活跃状态检测。";
        }
        StringBuilder sb = new StringBuilder();
        sb.append("<b>账号测活完成</b>\n").append(DIVIDER).append("\n\n");
        sb.append("<b>统计概况</b>\n");
        sb.append("    总数：<code>").append(res.getTotalAccounts()).append("</code>\n");
        sb.append("    活跃：<code>").append(res.getActiveAccounts()).append("</code>\n");
        sb.append("    异常：<code>").append(res.getInactiveAccounts()).append("</code>\n");

        List<String> names = res.getInactiveAccountNames();
        if (names != null && !names.isEmpty()) {
            sb.append("\n<b>异常账号</b>\n");
            int limit = Math.min(names.size(), 20);
            for (int i = 0; i < limit; i++) {
                sb.append("    • ").append(escape(names.get(i))).append("\n");
            }
            if (names.size() > limit) {
                sb.append("    <i>...另有 ").append(names.size() - limit).append(" 个，略</i>\n");
            }
        }
        sb.append("\n<i>完成时间：").append(LocalDateTime.now().format(TIME_FMT)).append("</i>");
        return sb.toString();
    }

    /**
     * 处理系统升级（执行升级后服务可能重启）
     */
    private void handleSystemUpgrade(Long chatId, Integer messageId) {
        sendOrEdit(chatId, messageId,
                "<b>正在执行系统升级</b>\n" + DIVIDER +
                        "\n\n升级过程中助手将暂时离线，稍后将自动回来。",
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
                        "<b>升级失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
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
                        "<b>我的账号</b>\n" + DIVIDER + "\n\n暂无账号信息。",
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
            String label = String.format("%s · 主区:%s · %d个区域",
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

        String text = "<b>我的账号列表</b>\n" + DIVIDER + "\n" +
                String.format("共 <b>%d</b> 个账号 | 第 %d / %d 页\n\n", total, page, totalPage) +
                "请选择账号查看详情：";

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
                        "未找到该租户信息",
                        onlyBackToMainMarkup());
                return;
            }

            String displayName = resolveDisplayName(tenant);
            List<Tenant> children = getTenantService().regionList(tenantId);
            if (children == null || children.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "<b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n\n该租户暂无区域信息。",
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

                currentRow.add(button(regionDisplay + accountType, "region_info_" + child.getId()));

                // 每两个按钮一行，或者到达最后一个元素时添加到keyboard
                if (currentRow.size() == 2 || i == children.size() - 1) {
                    keyboard.add(new ArrayList<>(currentRow));
                    currentRow.clear();
                }
            }

            // 添加返回按钮
            keyboard.add(row(
                    button("账号列表", "back_to_tenant_list"),
                    button(BTN_BACK_MAIN, "back_to_main")
            ));

            markup.setKeyboard(keyboard);

            String text = "<b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n" +
                    String.format("共 <b>%d</b> 个区域\n\n", children.size()) +
                    "请选择区域查看实例：";

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
                sendOrEdit(chatId, messageId, "未找到该区域信息",
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

                    keyboard.add(Collections.singletonList(button(buttonText, "instance_detail_" + instance.getId())));
                }
            }

            // 2. 构建底部操作行：返回 + 更新实例
            Long parenId = region.getParenId();
            if (parenId == 0L) parenId = region.getId();
            keyboard.add(row(
                    button("返回", "tenant_detail_" + parenId),
                    button("更新实例", "update_instances_" + region.getId())
            ));
            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));

            markup.setKeyboard(keyboard);

            int instanceCount = (instances != null) ? instances.size() : 0;
            String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";
            String text = "<b>" + escape(regionName) + "</b>\n" + DIVIDER + "\n\n" +
                    (instanceCount > 0
                            ? String.format("共 <b>%d</b> 个实例", instanceCount)
                            : "该区域暂无实例");

            sendOrEdit(chatId, messageId, text, markup);

        } catch (Exception e) {
            log.error("显示区域实例信息时出错: {}", e.getMessage(), e);
            sendOrEdit(chatId, messageId,
                    "获取实例信息时出现错误：" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }
    private String getStateIcon(String state) {
        if (state == null) return "未知";

        switch (state.toUpperCase()) {
            case "RUNNING":
                return "运行中";
            case "STOPPED":
                return "已停止";
            case "STOPPING":
                return "停止中";
            case "STARTING":
                return "启动中";
            case "PROVISIONING":
                return "预配中";
            case "TERMINATING":
                return "终止中";
            case "TERMINATED":
                return "已终止";
            default:
                return state;
        }
    }

    /**
     * 处理帮助功能
     */
    private void handleHelp(Long chatId, Integer messageId) {
        String helpText = "<b>OCI-START 智能助手 使用帮助</b>\n" + DIVIDER + "\n\n" +
                "<b>功能说明</b>\n" +
                "• <b>账号测活</b>：批量检查所有账号的活跃状态\n" +
                "• <b>版本检查</b>：检查并执行系统升级\n" +
                "• <b>我的账号</b>：查看租户/区域/实例信息\n" +
                "• <b>本月流量</b>：查询本月各区域出站流量\n" +
                "• <b>开机日志</b>：查看预开机执行历史\n\n" +
                "<b>常用命令</b>\n" +
                "• <code>/start</code> 或 <code>/menu</code>：打开主菜单\n" +
                "• <code>/active</code>：激活账号\n" +
                "• <code>/banIp 1.2.3.4</code>：封禁 IP\n" +
                "• <code>/unbanIp 1.2.3.4</code>：解除封禁\n" +
                "• 直接发送消息：与 AI 助手对话\n\n" +
                "<b>项目地址</b>\n" +
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
                        "<b>本月流量</b>\n" + DIVIDER + "\n\n暂无账号信息。",
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
            String label = String.format("%s · %d个区域", displayName, childrenCount);
            keyboard.add(Collections.singletonList(button(label, "traffic_parent_" + tenant.getId())));
        }

        List<InlineKeyboardButton> navRow = pageNavRow(page, totalPage, "traffic_page_");
        if (!navRow.isEmpty()) {
            keyboard.add(navRow);
        }

        keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(keyboard);

        String periodStart = LocalDateTime.now().withDayOfMonth(1).format(DATE_FMT);
        String text = "<b>本月流量查询</b>\n" + DIVIDER + "\n" +
                "统计周期：<code>" + periodStart + "</code> 至今 <i>(UTC)</i>\n" +
                String.format("共 <b>%d</b> 个账号 | 第 %d / %d 页\n\n", total, page, totalPage) +
                "请选择账号查看区域：";

        sendOrEdit(chatId, messageId, text, markup);
    }

    private void showTrafficRegionMenu(Long chatId, Integer messageId, Long parentId) {
        try {
            Tenant parent = getTenantService().getById(parentId);
            if (parent == null) {
                sendOrEdit(chatId, messageId, "未找到该租户信息", trafficBackToListMarkup());
                return;
            }

            String displayName = resolveDisplayName(parent);
            List<Tenant> regions = getTenantService().regionList(parentId);
            if (regions == null || regions.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "<b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n\n该租户暂无区域信息。",
                        trafficBackToListMarkup());
                return;
            }

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            List<InlineKeyboardButton> currentRow = new ArrayList<>();
            for (int i = 0; i < regions.size(); i++) {
                Tenant region = regions.get(i);
                String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";
                currentRow.add(button(regionName, "traffic_region_" + region.getId()));
                if (currentRow.size() == 2 || i == regions.size() - 1) {
                    keyboard.add(new ArrayList<>(currentRow));
                    currentRow.clear();
                }
            }

            keyboard.add(row(
                    button("账号列表", "back_to_traffic_list"),
                    button(BTN_BACK_MAIN, "back_to_main")
            ));

            markup.setKeyboard(keyboard);

            String text = "<b>" + escape(displayName) + "</b>\n" + DIVIDER + "\n" +
                    String.format("共 <b>%d</b> 个区域\n\n", regions.size()) +
                    "请选择区域查询本月流量：";

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
            sendOrEdit(chatId, messageId, "未找到该区域信息", trafficBackToListMarkup());
            return;
        }

        Long parenId = region.getParenId();
        if (parenId == null || parenId == 0L) parenId = region.getId();
        final Long backParentId = parenId;

        String regionName = region.getRegion() != null ? region.getRegion() : "未知区域";
        String loadingText = "<b>" + escape(regionName) + "</b>\n" + DIVIDER + "\n\n" +
                (isRefresh ? "正在重新查询..." : "正在查询本月流量，请稍候...");

        sendOrEdit(chatId, messageId, loadingText, null);

        new Thread(() -> {
            TenantTrafficStats stats;
            try {
                stats = getInstanceTrafficTask().queryTenantTraffic(region);
            } catch (Exception e) {
                log.error("查询流量失败 regionId={}: {}", regionId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "<b>查询失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
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

        sb.append("<b>本月流量统计</b>\n").append(DIVIDER).append("\n");
        sb.append("区域: ").append(escape(regionName)).append("\n");
        if (stats.getStartTime() != null && stats.getEndTime() != null) {
            sb.append("周期: ")
                    .append(stats.getStartTime().format(DATE_FMT))
                    .append(" ~ ")
                    .append(stats.getEndTime().format(DATE_FMT))
                    .append(" (UTC)\n");
        }

        if (!stats.isSuccess()) {
            sb.append("\n查询失败");
            if (StringUtils.isNotBlank(stats.getMessage())) {
                sb.append(": ").append(escape(stats.getMessage()));
            }
            return sb.toString();
        }

        sb.append("总流量: ").append(formatGB(stats.getTotalEgressGB())).append(" GB");
        if (stats.getThresholdGB() != null) {
            sb.append(" | 阈值: ").append(formatGB(stats.getThresholdGB())).append(" GB");
            double diff = stats.getTotalEgressGB() - stats.getThresholdGB();
            if (diff > 0) {
                sb.append(" | 已超出: ").append(formatGB(diff)).append(" GB");
            } else {
                sb.append(" | 剩余: ").append(formatGB(-diff)).append(" GB");
            }
            if (Boolean.TRUE.equals(stats.getAutoShutdown())) {
                sb.append(" | 自动关机: 已开启");
            }
        } else {
            sb.append(" | 阈值: 未配置");
        }
        sb.append("\n\n");

        List<TenantTrafficStats.InstanceTraffic> instances = stats.getInstances();
        if (instances == null || instances.isEmpty()) {
            sb.append("暂无实例");
            if (StringUtils.isNotBlank(stats.getMessage())) {
                sb.append("\n").append(escape(stats.getMessage()));
            }
            sb.append("\n\n");
        } else {
            int idx = 1;
            for (TenantTrafficStats.InstanceTraffic ins : instances) {
                String name = StringUtils.isNotBlank(ins.getInstanceName())
                        ? ins.getInstanceName() : "instance-" + idx;
                String ip = StringUtils.isNotBlank(ins.getPublicIp()) ? ins.getPublicIp() : "无公网IP";
                sb.append("<b>").append(idx).append(".</b> ").append(escape(name)).append("\n");
                sb.append("  IP: ").append(escape(ip))
                        .append(" | 出站: ").append(formatGB(ins.getEgressGB())).append(" GB")
                        .append("\n\n");
                idx++;
            }
        }
        sb.append("更新时间: ").append(LocalDateTime.now().format(TIME_FMT));
        return sb.toString();
    }

    private InlineKeyboardMarkup trafficResultMarkup(Long regionId, Long parentId) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button(BTN_REFRESH, "traffic_refresh_" + regionId),
                button("区域列表", "traffic_back_regions_" + parentId)
        ));
        kb.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
        markup.setKeyboard(kb);
        return markup;
    }

    private InlineKeyboardMarkup trafficBackToListMarkup() {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> kb = new ArrayList<>();
        kb.add(row(
                button("账号列表", "back_to_traffic_list"),
                button(BTN_BACK_MAIN, "back_to_main")
        ));
        markup.setKeyboard(kb);
        return markup;
    }

    private String formatGB(double gb) {
        return String.format("%.2f", gb);
    }

    // ============== 通用工具 ==============

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
                button("账号列表", "back_to_tenant_list"),
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
                    .text("思考中...")
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
                            currentText = currentText.substring(0, 4000) + "\n\n回复较长，生成中...";
                        }
                        editMessage(chatId, placeholderMessageId, currentText);
                    }
                });

                // 流式结束，发送最终完整回复
                String finalText = fullReply.toString();
                if (StringUtils.isBlank(finalText)) {
                    editMessage(chatId, placeholderMessageId, "抱歉，我无法回答你的问题。");
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
                editMessage(chatId, placeholderMessageId, "抱歉，AI服务暂时不可用，请稍后重试。");
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
                    "<b>开机日志</b>\n" + DIVIDER + "\n\n暂无开机日志记录。",
                    onlyBackToMainMarkup());
            return;
        }

        // 获取分页元数据
        int totalPages = bootPage.getTotalPages();
        int currentPage = bootPage.getNumber() + 1; // 转换为 1 基准供用户查看

        // 3. 构建正文
        StringBuilder sb = new StringBuilder();
        sb.append("<b>昨日预开机统计</b>\n").append(DIVIDER).append("\n");
        sb.append("第 <b>").append(currentPage).append("</b> / <b>").append(totalPages).append("</b> 页\n\n");

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
                    .append("  所属区域: ").append(escape(safeStr(item.getRegionName())))
                    .append(" | 架构: ").append(escape(safeStr(item.getArchitecture())))
                    .append(" | 状态: ").append(escape(BootInstanceStatusEnum.getStatus(item.getStatus()).getName()))
                    .append("\n")
                    .append("  开始日期: ").append(escape(safeStr(item.getCreateAtStr()))).append("\n")
                    .append("  总计: ").append(item.getAddCount())
                    .append(" | 昨日: ").append(item.getYesterdayAttemptCount())
                    .append(" | 今日: ").append(item.getCurrentAttemptCount())
                    .append(" | 成功: ").append(item.getSuccessCount())
                    .append(" | 天数: ").append(daysBetweenCurrent(item.getCreateAtStr()))
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
            sb.append("<b>系统版本状态</b>\n").append(DIVIDER).append("\n\n");
            sb.append("当前版本：<code>").append(escape(safeStr(current))).append("</code>\n");
            sb.append("最新版本：<code>").append(escape(safeStr(latest))).append("</code>\n\n");

            if (!needUpdate) {
                sb.append("<b>您已是最新版本！</b>");
            } else {
                sb.append("<b>检测到新版本，可立即升级</b>");
            }

            // —— 构建按钮 ——
            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 需要升级才显示
            if (needUpdate) {
                keyboard.add(Collections.singletonList(button("立即升级", "do_upgrade")));
            }

            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));

            markup.setKeyboard(keyboard);

            sendOrEdit(chatId, messageId, sb.toString(), markup);

        } catch (Exception e) {
            log.error("展示升级菜单失败: {}", e.getMessage());
            sendOrEdit(chatId, messageId,
                    "获取版本信息失败：" + safe(e.getMessage()),
                    onlyBackToMainMarkup());
        }
    }

    private void handleUpdateInstances(Long chatId, Integer messageId, Long regionId) {
        sendOrEdit(chatId, messageId,
                "<b>正在同步实例信息</b>\n" + DIVIDER + "\n\n请稍候...",
                null);
        new Thread(() -> {
            try {
                getTenantService().syncOci(regionId);
            } catch (Exception e) {
                log.error("同步实例失败: {}", e.getMessage());
                sendOrEdit(chatId, messageId,
                        "<b>同步失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        onlyBackToMainMarkup());
                return;
            }
            // 同步完成后直接刷新区域实例视图
            showRegionInfo(chatId, messageId, regionId);
        }, "tg-update-instances-" + regionId).start();
    }

    // 剧透处理

}
