package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.TelegramUser;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ocicommon.enums.BootInstanceStatusEnum;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.utils.PasswordGenerator;

import com.doubledimple.ociserver.config.task.DynamicDailyTask;
import com.doubledimple.ociserver.config.task.InstanceTrafficTask;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.pojo.response.AccountCheckRes;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.ociserver.service.BootInstanceService;
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

    /** 免费架构：[key, 展示标签, 默认CPU, 默认内存, 默认磁盘] */
    private static final Object[][] FREE_ARCH = {
        {"ARM", "ARM A1", 1, 6,  50},
        {"AMD", "AMD E2", 1, 1,  50},
    };

    /** 付费架构：[key, 展示标签, 默认CPU, 默认内存, 默认磁盘] */
    private static final Object[][] PAID_ARCH = {
        {"ARM_PAID_A2",  "ARM A2", 4, 24, 200},
        {"AMD_PAID_E3",  "AMD E3", 4, 16, 50},
        {"AMD_PAID_E4",  "AMD E4", 4, 16, 50},
        {"AMD_PAID_E5",  "AMD E5", 4, 16, 50},
    };


    private static final DateTimeFormatter TIME_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final DateTimeFormatter DATE_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    /** 等待用户输入自定义配置值的状态（chatId → 待填字段信息）*/
    private final java.util.concurrent.ConcurrentHashMap<Long, PendingBootInput> pendingBootInputs =
            new java.util.concurrent.ConcurrentHashMap<>();

    /** 开机配置草稿（每个 chatId 独立，避免每次点击都查 DB）*/
    private final java.util.concurrent.ConcurrentHashMap<Long, DraftBootConfig> draftConfigs =
            new java.util.concurrent.ConcurrentHashMap<>();

    /** 异步任务线程池，复用线程避免每次 new Thread() 的开销 */
    private final java.util.concurrent.ExecutorService executor =
            java.util.concurrent.Executors.newCachedThreadPool(r -> {
                Thread t = new Thread(r);
                t.setDaemon(true);
                return t;
            });

    private static class PendingBootInput {
        final String field; // cpu | mem | disk | count | loop
        final Long tenantId;
        final String arch;
        final int ocpu, memory, disk, count, loopTime;
        final Integer messageId;
        PendingBootInput(String field, Long tenantId, String arch,
                int ocpu, int memory, int disk, int count, int loopTime, Integer messageId) {
            this.field = field; this.tenantId = tenantId; this.arch = arch;
            this.ocpu = ocpu; this.memory = memory; this.disk = disk;
            this.count = count; this.loopTime = loopTime; this.messageId = messageId;
        }
    }

    private static class DraftBootConfig {
        final Long tenantId;
        final String regionName;
        String arch;
        int cpu, mem, disk, count, loopTime;
        DraftBootConfig(Long tenantId, String regionName, String arch,
                        int cpu, int mem, int disk, int count, int loopTime) {
            this.tenantId = tenantId; this.regionName = regionName; this.arch = arch;
            this.cpu = cpu; this.mem = mem; this.disk = disk;
            this.count = count; this.loopTime = loopTime;
        }
    }

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

    private BootInstanceService getBootInstanceService() {
        return applicationContext.getBean(BootInstanceService.class);
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

            // 优先处理自定义配置输入（等待用户输入数字）
            PendingBootInput pending = pendingBootInputs.remove(chatId);
            if (pending != null) {
                handleBootCustomInput(chatId, pending, text);
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

        log.debug("[TG-CB] 收到所有回调: {} 来自: {}", callbackData, chatId);

        // 第一时间应答，立即停止 Telegram 按钮的加载动画，之后再做鉴权和业务处理
        String callbackId = callbackQuery.getId();
        answerCallback(callbackId);

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
                case "add_boot":
                    handleAddBootSelectTenant(chatId, messageId);
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

                    else if (callbackData.startsWith("boot_add_t_")) {
                        Long parentId = Long.valueOf(callbackData.substring("boot_add_t_".length()));
                        handleAddBootSelectRegion(chatId, messageId, parentId);
                    }
                    else if (callbackData.startsWith("boot_add_r_")) {
                        Long tenantId = Long.valueOf(callbackData.substring("boot_add_r_".length()));
                        handleBootConfigMenu(chatId, messageId, tenantId, "ARM", 1, 6, 50, 1, 60);
                    }
                    else if (callbackData.startsWith("boot_cfg_ok_")) {
                        String[] parts = callbackData.substring("boot_cfg_ok_".length()).split("\\|");
                        Long tid = Long.valueOf(parts[0]);
                        DraftBootConfig draft = draftConfigs.get(chatId);
                        if (draft != null && draft.tenantId.equals(tid)) {
                            // 使用草稿中记录的最新配置（包含所有快选点击的结果）
                            handleAddBootExecute(chatId, messageId, draft.tenantId, draft.arch,
                                    draft.cpu, draft.mem, draft.disk, draft.count, draft.loopTime);
                        } else {
                            // 无草稿时降级使用回调数据（兼容旧消息按钮）
                            handleAddBootExecute(chatId, messageId, tid, parts[1],
                                    Integer.parseInt(parts[2]), Integer.parseInt(parts[3]),
                                    Integer.parseInt(parts[4]), Integer.parseInt(parts[5]), Integer.parseInt(parts[6]));
                        }
                    }
                    else if (callbackData.startsWith("boot_opt_")) {
                        // 格式: boot_opt_{field}_{tenantId}|{value}
                        String rest = callbackData.substring("boot_opt_".length());
                        int under = rest.indexOf('_');
                        String field = rest.substring(0, under);
                        String[] parts = rest.substring(under + 1).split("\\|");
                        Long tid = Long.valueOf(parts[0]);
                        int value = Integer.parseInt(parts[1]);
                        handleBootOptChange(chatId, callbackId, messageId, tid, field, value);
                    }
                    else if (callbackData.startsWith("boot_more_")) {
                        // 格式: boot_more_{field}_{tenantId}，从草稿读取当前完整状态
                        String rest = callbackData.substring("boot_more_".length());
                        int under = rest.indexOf('_');
                        String field = rest.substring(0, under);
                        Long tid = Long.valueOf(rest.substring(under + 1));
                        DraftBootConfig draft = draftConfigs.get(chatId);
                        if (draft != null && draft.tenantId.equals(tid)) {
                            final DraftBootConfig d = draft;
                            executor.submit(() -> showBootMoreOptions(chatId, messageId, field, tid,
                                    d.arch, d.cpu, d.mem, d.disk, d.count, d.loopTime));
                        }
                    }
                    else if (callbackData.startsWith("boot_sel_")) {
                        // 从"更多"子菜单中选定一个值，更新草稿并返回主配置界面
                        String rest = callbackData.substring("boot_sel_".length());
                        int sep = rest.indexOf('_');
                        String[] parts = rest.substring(sep + 1).split("\\|");
                        Long tid = Long.valueOf(parts[0]);
                        String a = parts[1];
                        int c = Integer.parseInt(parts[2]), m = Integer.parseInt(parts[3]);
                        int d = Integer.parseInt(parts[4]), cnt = Integer.parseInt(parts[5]);
                        int lt = Integer.parseInt(parts[6]);
                        // 更新草稿并重新渲染主配置页（需要一次 API 调用，但"更多"不常用）
                        DraftBootConfig draft = draftConfigs.get(chatId);
                        if (draft != null) {
                            draft.arch = a; draft.cpu = c; draft.mem = m; draft.disk = d;
                            draft.count = cnt; draft.loopTime = lt;
                        }
                        handleBootConfigMenu(chatId, messageId, tid, a, c, m, d, cnt, lt);
                    }
                    else if (callbackData.startsWith("boot_ask_")) {
                        // boot_ask_{field}_{tenantId}|{arch}|{ocpu}|{mem}|{disk}|{count}|{loop}
                        String rest = callbackData.substring("boot_ask_".length());
                        int sep = rest.indexOf('_');
                        String field = rest.substring(0, sep);
                        String[] parts = rest.substring(sep + 1).split("\\|");
                        pendingBootInputs.put(chatId, new PendingBootInput(field,
                                Long.valueOf(parts[0]), parts[1],
                                Integer.parseInt(parts[2]), Integer.parseInt(parts[3]),
                                Integer.parseInt(parts[4]), Integer.parseInt(parts[5]),
                                Integer.parseInt(parts[6]), messageId));
                        Map<String, String> fieldNames = new java.util.LinkedHashMap<>();
                        fieldNames.put("cpu",   "CPU 核数 (整数)");
                        fieldNames.put("mem",   "内存大小 GB (整数)");
                        fieldNames.put("disk",  "磁盘大小 GB (整数)");
                        fieldNames.put("count", "实例数量 (整数)");
                        fieldNames.put("loop",  "轮询间隔秒数 (整数，最小 12)");
                        String hint = fieldNames.getOrDefault(field, field);
                        sendOrEdit(chatId, messageId,
                                "✏️ <b>自定义输入</b>\n" + DIVIDER + "\n\n" +
                                "请直接发送 <b>" + hint + "</b>：\n\n" +
                                "<i>发送任意非数字可取消</i>",
                                onlyBackToMainMarkup());
                    }
                    else if (callbackData.startsWith("boot_cfg_")) {
                        String[] parts = callbackData.substring("boot_cfg_".length()).split("\\|");
                        handleBootConfigMenu(chatId, messageId, Long.valueOf(parts[0]),
                                parts[1], Integer.parseInt(parts[2]), Integer.parseInt(parts[3]),
                                Integer.parseInt(parts[4]), Integer.parseInt(parts[5]), Integer.parseInt(parts[6]));
                    }
                    else if (callbackData.startsWith("boot_rst_")) {
                        String[] parts = callbackData.substring("boot_rst_".length()).split("\\|");
                        Long tid = Long.valueOf(parts[0]);
                        String a = parts[1];
                        int[] defs = bootArchDefaults(a);
                        // 同步立即重置草稿，防止异步线程时序问题导致恢复无效
                        DraftBootConfig cur = draftConfigs.get(chatId);
                        String cachedRegion = cur != null ? cur.regionName : "未知";
                        draftConfigs.put(chatId, new DraftBootConfig(tid, cachedRegion, a, defs[0], defs[1], defs[2], 1, 60));
                        handleBootConfigMenu(chatId, messageId, tid, a, defs[0], defs[1], defs[2], 1, 60);
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

        // 第三行：开机日志和添加开机
        keyboard.add(row(
                button("📋 开机日志", "boot_log"),
                button("➕ 添加开机", "add_boot")
        ));

        // 第四行：使用帮助
        keyboard.add(Collections.singletonList(button("💡 使用帮助", "help")));

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
        executor.submit(() -> {
            String resultText;
            try {
                AccountCheckRes res = getTenantService().checkBatchAccounts();
                resultText = formatAccountCheckResult(res);
            } catch (Exception e) {
                log.error("账号测活失败: {}", e.getMessage(), e);
                resultText = "❌ <b>账号测活失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage());
            }
            sendOrEdit(chatId, messageId, resultText, onlyBackToMainMarkup());
        });
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
        executor.submit(() -> {
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
        });
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

            // 2. 构建底部操作行：查询配额 + 更新实例 + 添加开机 + 返回
            Long parenId = region.getParenId();
            if (parenId == 0L) parenId = region.getId();
            keyboard.add(row(
                    button("📊 查询配额", "quota_region_" + region.getId()),
                    button("🔄 更新实例", "update_instances_" + region.getId())
            ));
            keyboard.add(Collections.singletonList(button("➕ 添加开机", "boot_add_r_" + region.getId())));
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

        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
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

    private void answerCallback(String callbackQueryId, String text) {
        try {
            execute(AnswerCallbackQuery.builder()
                    .callbackQueryId(callbackQueryId)
                    .text(text)
                    .build());
        } catch (TelegramApiException e) {
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
        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
    }

    private void handleInstStop(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId, "⏹ <b>正在停止实例</b>\n" + DIVIDER + "\n\n⏳ 请稍候…", null);
        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
    }

    private void handleInstChangeIp(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId,
                "🔄 <b>正在更换IPV4</b>\n" + DIVIDER + "\n\n⏳ 请稍候，这可能需要一些时间…", null);
        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
    }

    private void handleInstIpv6(Long chatId, Integer messageId, Long regionId, Long dbId) {
        sendOrEdit(chatId, messageId, "🔷 <b>正在处理IPv6</b>\n" + DIVIDER + "\n\n⏳ 请稍候…", null);
        executor.submit(() -> {
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
        });
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
        executor.submit(() -> {
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
        });
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

    // ---- 添加开机流程 ----

    private void handleAddBootSelectTenant(Long chatId, Integer messageId) {
        sendOrEdit(chatId, messageId, "⏳ 加载账号列表中…", onlyBackToMainMarkup());
        executor.submit(() -> {
            List<Tenant> tenants = getAllParentTenants();
            if (tenants == null || tenants.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "➕ <b>添加开机</b>\n" + DIVIDER + "\n\n暂无账号，请先添加租户。",
                        onlyBackToMainMarkup());
                return;
            }
            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();
            for (Tenant tenant : tenants) {
                String displayName = resolveDisplayName(tenant);
                keyboard.add(Collections.singletonList(
                        button(displayName, "boot_add_t_" + tenant.getId())));
            }
            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
            markup.setKeyboard(keyboard);
            sendOrEdit(chatId, messageId,
                    "➕ <b>添加开机 · 选择账号</b>\n" + DIVIDER + "\n\n请选择要开机的账号",
                    markup);
        });
    }

    private void handleAddBootSelectRegion(Long chatId, Integer messageId, Long parentId) {
        sendOrEdit(chatId, messageId, "⏳ 加载区域列表中…", onlyBackToMainMarkup());
        executor.submit(() -> {
            List<Tenant> children = getTenantService().regionList(parentId);
            if (children == null || children.isEmpty()) {
                sendOrEdit(chatId, messageId,
                        "➕ <b>添加开机</b>\n" + DIVIDER + "\n\n该账号暂无区域信息。",
                        onlyBackToMainMarkup());
                return;
            }
            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();
            List<InlineKeyboardButton> currentRow = new ArrayList<>();
            for (int i = 0; i < children.size(); i++) {
                Tenant child = children.get(i);
                String regionDisplay = child.getRegion() != null ? child.getRegion() : "未知区域";
                currentRow.add(button(regionDisplay, "boot_add_r_" + child.getId()));
                if (currentRow.size() == 2 || i == children.size() - 1) {
                    keyboard.add(new ArrayList<>(currentRow));
                    currentRow.clear();
                }
            }
            keyboard.add(Collections.singletonList(button(BTN_BACK_MAIN, "back_to_main")));
            markup.setKeyboard(keyboard);
            sendOrEdit(chatId, messageId,
                    "➕ <b>添加开机 · 选择区域</b>\n" + DIVIDER + "\n\n请选择要开机的区域",
                    markup);
        });
    }

    /**
     * 统一配置菜单：免费/付费 → 架构 → CPU → 内存 → 磁盘 → 数量 → 间隔，全部在一页完成
     * state 编码: tenantId|arch|ocpu|memory|disk|count|loopTime（用 | 分隔）
     */
    private void handleBootConfigMenu(Long chatId, Integer messageId,
            Long tenantId, String arch, int ocpu, int memory, int disk, int count, int loopTime) {
        executor.submit(() -> buildAndSendBootConfigMenu(chatId, messageId, tenantId, arch, ocpu, memory, disk, count, loopTime));
    }

    private void buildAndSendBootConfigMenu(Long chatId, Integer messageId,
            Long tenantId, String arch, int ocpu, int memory, int disk, int count, int loopTime) {
        // 优先从草稿缓存取 regionName，避免每次渲染都查 DB
        DraftBootConfig existingDraft = draftConfigs.get(chatId);
        String regionName;
        if (existingDraft != null && existingDraft.tenantId.equals(tenantId)
                && existingDraft.regionName != null && !"未知".equals(existingDraft.regionName)) {
            regionName = existingDraft.regionName;
        } else {
            Tenant tenant = getTenantService().getById(tenantId);
            regionName = tenant != null && tenant.getRegion() != null ? tenant.getRegion() : "未知";
        }
        // 保存/更新草稿
        draftConfigs.put(chatId, new DraftBootConfig(tenantId, regionName, arch, ocpu, memory, disk, count, loopTime));
        boolean isFreeTier = "ARM".equals(arch) || "AMD".equals(arch);

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        // ── 类型行：固定 5 列 [类型] [免费] [付费] [  ] [  ] ──
        Object[] freeFirst = FREE_ARCH[0];
        Object[] paidFirst = PAID_ARCH[0];
        String freeCb = "boot_cfg_" + tenantId + "|" + freeFirst[0] + "|" + freeFirst[2] + "|" + freeFirst[3] + "|" + freeFirst[4] + "|" + count + "|" + loopTime;
        String paidCb = "boot_cfg_" + tenantId + "|" + paidFirst[0] + "|" + paidFirst[2] + "|" + paidFirst[3] + "|" + paidFirst[4] + "|" + count + "|" + loopTime;
        keyboard.add(java.util.Arrays.asList(
                button("类型", "divider"),
                button(isFreeTier  ? "[免费]" : "免费", freeCb),
                button(!isFreeTier ? "[付费]" : "付费", paidCb),
                button(" ", "divider"),
                button(" ", "divider")
        ));

        // ── 架构行：固定 5 列，按钮只显示短标识（如 A1/E2）避免遮挡 ──
        Object[][] archList = isFreeTier ? FREE_ARCH : PAID_ARCH;
        List<InlineKeyboardButton> archRow = new ArrayList<>();
        archRow.add(button("架构", "divider"));
        for (Object[] a : archList) {
            String aKey   = (String) a[0];
            String aLabel = (String) a[1];
            // "ARM A1" → "A1"，"AMD E3" → "E3"，短标识防止文字被截断
            String aShort = aLabel.contains(" ") ? aLabel.substring(aLabel.lastIndexOf(' ') + 1) : aLabel;
            String cb = "boot_cfg_" + tenantId + "|" + aKey + "|" + a[2] + "|" + a[3] + "|" + a[4] + "|" + count + "|" + loopTime;
            archRow.add(button(aKey.equals(arch) ? "[" + aShort + "]" : aShort, cb));
        }
        while (archRow.size() < 5) archRow.add(button(" ", "divider"));
        keyboard.add(archRow);

        // ── 参数行：固定 5 列（说明标签 | 预设1 | 预设2 | 预设3 | 更多）──
        // 选项不足 3 个时用空占位保持列宽一致
        // boot_opt_ 按钮只携带「字段」和「新值」，其余参数始终从草稿读取，避免旧按钮数据覆盖已更改的字段
        String archBase = tenantId + "|" + arch;
        String fullState = archBase + "|" + ocpu + "|" + memory + "|" + disk + "|" + count + "|" + loopTime;

        keyboard.add(buildOptionRow5("CPU", bootCpuOptions(arch),
                v -> v + "C", v -> v == ocpu,
                v -> "boot_opt_cpu_" + tenantId + "|" + v,
                ocpu, "boot_more_cpu_" + tenantId));

        keyboard.add(buildOptionRow5("内存", bootMemOptions(arch),
                v -> v + "G", v -> v == memory,
                v -> "boot_opt_mem_" + tenantId + "|" + v,
                memory, "boot_more_mem_" + tenantId));

        keyboard.add(buildOptionRow5("磁盘", bootDiskOptions(arch),
                v -> v + "G", v -> v == disk,
                v -> "boot_opt_disk_" + tenantId + "|" + v,
                disk, "boot_more_disk_" + tenantId));

        keyboard.add(buildOptionRow5("数量", new int[]{1, 2, 3},
                v -> "x" + v, v -> v == count,
                v -> "boot_opt_count_" + tenantId + "|" + v,
                count, "boot_more_count_" + tenantId));

        keyboard.add(buildOptionRow5("间隔", new int[]{30, 60, 120},
                v -> v + "s", v -> v == loopTime,
                v -> "boot_opt_loop_" + tenantId + "|" + v,
                loopTime, "boot_more_loop_" + tenantId));

        // ── 恢复默认 / 确认 / 返回 ──
        keyboard.add(java.util.Arrays.asList(
                button("恢复默认", "boot_rst_" + tenantId + "|" + arch),
                button("确认创建", "boot_cfg_ok_" + fullState),
                button("返回主菜单", "back_to_main")
        ));

        markup.setKeyboard(keyboard);

        String archLabel = bootArchLabel(arch);
        String tierLabel = isFreeTier ? "免费" : "付费";
        StringBuilder sb = new StringBuilder();
        sb.append("<b>添加开机配置</b>\n");
        sb.append(DIVIDER).append("\n");
        sb.append("区域：<b>").append(escape(regionName)).append("</b>\n");
        sb.append(DIVIDER_THIN).append("\n");
        sb.append("类型：<code>").append(tierLabel).append("</code>    ");
        sb.append("架构：<code>").append(escape(archLabel)).append("</code>\n");
        sb.append("CPU：<code>").append(ocpu).append("C</code>    ");
        sb.append("内存：<code>").append(memory).append("G</code>    ");
        sb.append("磁盘：<code>").append(disk).append("G</code>\n");
        sb.append("数量：<code>x").append(count).append("</code>    ");
        sb.append("间隔：<code>").append(loopTime).append("s</code>\n");
        sb.append(DIVIDER_THIN).append("\n");
        sb.append("<i>[值] 表示当前选中，点击预设快速切换；点「更多」展开更多选项</i>");

        sendOrEdit(chatId, messageId, sb.toString(), markup);
    }

    /**
     * 构建固定 5 列的参数行：[标签] [预设1] [预设2] [预设3] [更多/当前值]
     * 若 currentValue 不在预设列表中，"更多"列显示 [当前值] 表示已自定义
     */
    private List<InlineKeyboardButton> buildOptionRow5(
            String label, int[] options,
            java.util.function.IntFunction<String> toText,
            java.util.function.IntPredicate isSelected,
            java.util.function.IntFunction<String> toCb,
            int currentValue,
            String customCb) {
        List<InlineKeyboardButton> row = new ArrayList<>();
        row.add(button(label, "divider"));
        boolean hitPreset = false;
        for (int v : options) {
            String text = toText.apply(v);
            boolean sel = isSelected.test(v);
            if (sel) hitPreset = true;
            row.add(button(sel ? "[" + text + "]" : text, toCb.apply(v)));
        }
        while (row.size() < 4) {
            row.add(button(" ", "divider"));
        }
        // 非预设值时在"更多"按钮显示当前自定义值
        String moreBtnLabel = hitPreset ? "更多" : "[" + toText.apply(currentValue) + "]";
        row.add(button(moreBtnLabel, customCb));
        return row;
    }

    private String bootArchLabel(String arch) {
        for (Object[] row : FREE_ARCH) {
            if (row[0].equals(arch)) return (String) row[1];
        }
        for (Object[] row : PAID_ARCH) {
            if (row[0].equals(arch)) return (String) row[1];
        }
        return arch;
    }

    /** 返回指定架构的默认 [cpu, mem, disk] */
    private int[] bootArchDefaults(String arch) {
        for (Object[] row : FREE_ARCH) {
            if (row[0].equals(arch)) return new int[]{(int) row[2], (int) row[3], (int) row[4]};
        }
        for (Object[] row : PAID_ARCH) {
            if (row[0].equals(arch)) return new int[]{(int) row[2], (int) row[3], (int) row[4]};
        }
        return new int[]{1, 6, 50};
    }

    private int[] bootCpuOptions(String arch) {
        switch (arch) {
            case "AMD":         return new int[]{1};
            case "ARM":         return new int[]{1, 2, 4};
            case "ARM_PAID_A2": return new int[]{4, 8, 16};
            default:            return new int[]{4, 8, 16};
        }
    }

    private int[] bootMemOptions(String arch) {
        switch (arch) {
            case "AMD":         return new int[]{1};
            case "ARM":         return new int[]{6, 12, 24};
            case "ARM_PAID_A2": return new int[]{24, 48, 96};
            default:            return new int[]{8, 16, 32};
        }
    }

    private int[] bootDiskOptions(String arch) {
        switch (arch) {
            case "AMD":         return new int[]{50};
            case "ARM":         return new int[]{50, 100, 200};
            case "ARM_PAID_A2": return new int[]{100, 200, 500};
            default:            return new int[]{50, 100, 200}; // AMD_PAID_E3/E4/E5 默认磁盘 50，需在预设中
        }
    }

    private void handleBootOptChange(Long chatId, String callbackId, Integer messageId,
            Long tenantId, String field, int value) {
        DraftBootConfig draft = draftConfigs.get(chatId);
        if (draft == null || !draft.tenantId.equals(tenantId)) {
            return;
        }
        // 只更新被点击的那一个字段，其余字段保持草稿中的当前值，避免旧按钮数据把已改的字段覆盖回去
        switch (field) {
            case "cpu":   draft.cpu       = value; break;
            case "mem":   draft.mem       = value; break;
            case "disk":  draft.disk      = value; break;
            case "count": draft.count     = value; break;
            case "loop":  draft.loopTime  = value; break;
        }
        final int c = draft.cpu, m = draft.mem, d = draft.disk, cnt = draft.count, lt = draft.loopTime;
        final String a = draft.arch;
        executor.submit(() -> buildAndSendBootConfigMenu(chatId, messageId, tenantId, a, c, m, d, cnt, lt));
    }

    private void showBootMoreOptions(Long chatId, Integer messageId, String field,
            Long tenantId, String arch, int cpu, int mem, int disk, int count, int loopTime) {
        int[] allOpts;
        int[] basicOpts;
        String unit;
        switch (field) {
            case "cpu":   allOpts = bootCpuOptionsExt(arch);   basicOpts = bootCpuOptions(arch);   unit = "C"; break;
            case "mem":   allOpts = bootMemOptionsExt(arch);   basicOpts = bootMemOptions(arch);   unit = "G"; break;
            case "disk":  allOpts = bootDiskOptionsExt(arch);  basicOpts = bootDiskOptions(arch);  unit = "G"; break;
            case "count": allOpts = new int[]{1,2,3,5,8,10};  basicOpts = new int[]{1,2,3};       unit = "x"; break;
            case "loop":  allOpts = new int[]{12,30,60,120,200,300,500}; basicOpts = new int[]{30,60,120}; unit = "s"; break;
            default:      allOpts = new int[]{};               basicOpts = new int[]{};             unit = "";
        }

        // 过滤掉主菜单已显示的预设值，只展示额外选项
        java.util.Set<Integer> basicSet = new java.util.HashSet<>();
        for (int v : basicOpts) basicSet.add(v);
        List<Integer> extraOpts = new ArrayList<>();
        for (int v : allOpts) {
            if (!basicSet.contains(v)) extraOpts.add(v);
        }

        String stateBase = tenantId + "|" + arch + "|" + cpu + "|" + mem + "|" + disk + "|" + count + "|" + loopTime;
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        if (extraOpts.isEmpty()) {
            keyboard.add(Collections.singletonList(button("暂无更多预设，请使用自定义输入", "divider")));
        } else {
            List<InlineKeyboardButton> row = new ArrayList<>();
            for (int i = 0; i < extraOpts.size(); i++) {
                int v = extraOpts.get(i);
                String newState;
                switch (field) {
                    case "cpu":   newState = tenantId+"|"+arch+"|"+v+"|"+mem+"|"+disk+"|"+count+"|"+loopTime; break;
                    case "mem":   newState = tenantId+"|"+arch+"|"+cpu+"|"+v+"|"+disk+"|"+count+"|"+loopTime; break;
                    case "disk":  newState = tenantId+"|"+arch+"|"+cpu+"|"+mem+"|"+v+"|"+count+"|"+loopTime;  break;
                    case "count": newState = tenantId+"|"+arch+"|"+cpu+"|"+mem+"|"+disk+"|"+v+"|"+loopTime;   break;
                    case "loop":  newState = tenantId+"|"+arch+"|"+cpu+"|"+mem+"|"+disk+"|"+count+"|"+v;      break;
                    default:      newState = stateBase;
                }
                String label = "count".equals(field) ? unit + v : v + unit;
                row.add(button(label, "boot_sel_" + field + "_" + newState));
                if (row.size() == 4 || i == extraOpts.size() - 1) {
                    keyboard.add(new ArrayList<>(row));
                    row.clear();
                }
            }
        }

        // 自定义输入按钮
        keyboard.add(Collections.singletonList(
                button("✏️ 自定义输入", "boot_ask_" + field + "_" + stateBase)));
        keyboard.add(Collections.singletonList(button("↩️ 返回配置", "boot_cfg_" + stateBase)));
        markup.setKeyboard(keyboard);

        Map<String,String> fieldLabel = new java.util.LinkedHashMap<>();
        fieldLabel.put("cpu","CPU"); fieldLabel.put("mem","内存");
        fieldLabel.put("disk","磁盘"); fieldLabel.put("count","数量"); fieldLabel.put("loop","间隔");
        sendOrEdit(chatId, messageId,
                "<b>更多 " + fieldLabel.getOrDefault(field, field) + " 选项</b>\n" + DIVIDER_THIN +
                "\n点击选择，或用「✏️ 自定义输入」填写任意值",
                markup);
    }

    private int[] bootCpuOptionsExt(String arch) {
        switch (arch) {
            case "AMD":         return new int[]{1};
            case "ARM":         return new int[]{1, 2, 3, 4};
            case "ARM_PAID_A2": return new int[]{2, 4, 8, 12, 16, 24, 32};
            default:            return new int[]{2, 4, 8, 12, 16, 24, 32, 48, 64};
        }
    }

    private int[] bootMemOptionsExt(String arch) {
        switch (arch) {
            case "AMD":         return new int[]{1};
            case "ARM":         return new int[]{6, 12, 18, 24};
            case "ARM_PAID_A2": return new int[]{12, 24, 48, 96, 128, 192};
            default:            return new int[]{8, 16, 32, 64, 128, 256};
        }
    }

    private int[] bootDiskOptionsExt(String arch) {
        switch (arch) {
            case "AMD": return new int[]{50};
            case "ARM": return new int[]{50, 100, 150, 200};
            default:    return new int[]{50, 100, 200, 300, 500, 1000};
        }
    }

    private void handleBootCustomInput(Long chatId, PendingBootInput p, String text) {
        int value;
        try {
            value = Integer.parseInt(text.trim());
        } catch (NumberFormatException e) {
            sendTextMessage(chatId, "⚠️ 输入无效，已取消自定义输入。");
            return;
        }
        int ocpu = p.ocpu, memory = p.memory, disk = p.disk, count = p.count, loopTime = p.loopTime;
        switch (p.field) {
            case "cpu":   ocpu     = Math.max(1, value);  break;
            case "mem":   memory   = Math.max(1, value);  break;
            case "disk":  disk     = Math.max(1, value);  break;
            case "count": count    = Math.max(1, value);  break;
            case "loop":  loopTime = Math.max(12, value); break;
        }
        handleBootConfigMenu(chatId, p.messageId, p.tenantId, p.arch, ocpu, memory, disk, count, loopTime);
    }

    private void handleAddBootExecute(Long chatId, Integer messageId, Long tenantId, String arch, int ocpu, int memory, int disk, int count, int loopTime) {
        sendOrEdit(chatId, messageId,
                "⏳ <b>正在创建开机任务</b>\n" + DIVIDER + "\n\n请稍候…", null);
        executor.submit(() -> {
            try {
                String rootPassword = PasswordGenerator.generatePassword2();
                BootInstance bootInstance = new BootInstance();
                bootInstance.setTenantId(tenantId);
                bootInstance.setArchitecture(arch);
                bootInstance.setOcpu(ocpu);
                bootInstance.setMemory(memory);
                bootInstance.setDisk(disk);
                bootInstance.setInstanceCount(count);
                bootInstance.setLoopTime(loopTime);
                bootInstance.setRootPassword(rootPassword);
                getBootInstanceService().saveBootInstance(bootInstance);

                Tenant tenant = getTenantService().getById(tenantId);
                String regionName = tenant != null && tenant.getRegion() != null ? tenant.getRegion() : "未知";
                sendOrEdit(chatId, messageId,
                        "✅ <b>开机任务创建成功</b>\n" + DIVIDER + "\n\n" +
                        "区域：<code>" + escape(regionName) + "</code>\n" +
                        "规格：<code>" + escape(arch) + "</code>  " + ocpu + "C/" + memory + "G/" + disk + "G\n" +
                        "数量：<code>" + count + "</code> 个\n" +
                        "间隔：<code>" + loopTime + "s</code>\n" +
                        "密码：<code>" + rootPassword + "</code>\n\n" +
                        "<i>任务已启动，可在「开机日志」中查看进度。</i>",
                        onlyBackToMainMarkup());
            } catch (Exception e) {
                log.error("创建开机任务失败 tenantId={}: {}", tenantId, e.getMessage(), e);
                sendOrEdit(chatId, messageId,
                        "❌ <b>创建开机任务失败</b>\n" + DIVIDER + "\n\n" + safe(e.getMessage()),
                        onlyBackToMainMarkup());
            }
        });
    }

}