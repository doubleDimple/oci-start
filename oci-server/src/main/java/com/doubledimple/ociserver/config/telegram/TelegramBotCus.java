package com.doubledimple.ociserver.config.telegram;

import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.TelegramUser;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ocicommon.enums.BootInstanceStatusEnum;
import com.doubledimple.ocicommon.enums.RegionEnum;

import com.doubledimple.ociserver.config.task.DynamicDailyTask;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
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

    public static final String MESSAGE_IP_BANNED_SUCCESS = "✅ 已成功封禁 IP：%s\n该 IP 的访问已被阻止。";
    public static final String MESSAGE_IP_BANNED_FAIL = "⚠️ 封禁 IP 失败：%s\n请检查系统配置或手动执行防火墙命令。";
    public static final String MESSAGE_IP_NOT_FOUND = "未检测到需要封禁的 IP。请先确认有异常登录记录。";

    private static final String BTN_BACK_MAIN = "🔙 返回主菜单";
    private static final String BTN_LAST_PAGE = "⬅️ 上一页";
    private static final String BTN_NEXT_PAGE = "下一页 ➡️";



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
                    sendTextMessage(chatId, "⚠️ 无效的命令格式，请使用 /banIp 127.0.0.1 或 /banIp_127_0_0_1");
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
                    sendTextMessage(chatId, "⚠️ 未识别 IP 地址，请检查命令格式。");
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
                    sendTextMessage(chatId, "⚠️ 无效的命令格式，请使用 /unbanIp 127.0.0.1 或 /unbanIp_127_0_0_1");
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
                    sendTextMessage(chatId, "⚠️ 未识别 IP 地址，请检查命令格式。");
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
                    sendMainMenu(chatId);
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
            sendTextMessage(chatId, "❗️请在命令后输入要封禁的 IP，例如：/banIp 23.26.125.77");
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
            sendTextMessage(chatId, "❗️请在命令后输入要解封的 IP，例如：/unbanIp 23.26.125.77");
            return;
        }

        boolean success = banService.unbanIp(ip,"手动解封");

        if (success) {
            sendTextMessage(chatId, String.format("♻️ 已解除封禁 IP：%s\n该 IP 已恢复正常访问。", ip));
        } else {
            sendTextMessage(chatId, String.format("⚠️ 解封 IP 失败：%s\n请确认该 IP 是否已封禁或稍后再试。", ip));
        }
    }



    /**
     * 处理回调查询（按钮点击）
     */
    private void handleCallbackQuery(CallbackQuery callbackQuery) {
        Long chatId = callbackQuery.getMessage().getChatId();
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
                    handleAccountCheck(chatId);
                    break;
                case "system_upgrade":
                    showUpgradeMenu(chatId);
                    break;
                case "do_upgrade":
                    handleSystemUpgrade(chatId);
                    break;
                case "query_tenant":
                    handleQueryTenant(chatId);
                    break;
                case "boot_log":
                    sendBootLogPage(chatId, 1);
                    break;
                case "help":
                    handleHelp(chatId);
                    break;
                case "divider":
                    // 分隔线按钮不做任何操作
                    break;
                case "back_to_main":
                    sendMainMenu(chatId);
                    break;
                case "back_to_tenant_list":
                    handleQueryTenant(chatId);
                    break;
                default:
                    // 处理租户详情回调
                    if (callbackData.startsWith("tenant_detail_")) {
                        Long tenantId = Long.valueOf(callbackData.substring("tenant_detail_".length()));
                        showTenantDetail(chatId, tenantId);
                    }
                    // 处理区域信息回调
                    else if (callbackData.startsWith("region_info_")) {
                        Long regionId = Long.valueOf(callbackData.substring("region_info_".length()));
                        showRegionInfo(chatId, regionId);
                    }

                    else if (callbackData.startsWith("boot_log_page_")) {
                        int page = Integer.parseInt(callbackData.replace("boot_log_page_", ""));
                        sendBootLogPage(chatId, page);
                    }

                    else if (callbackData.startsWith("tenant_page_")) {
                        int page = Integer.parseInt(callbackData.replace("tenant_page_", ""));
                        Page<Tenant> allTenants = getTenantService().getAllTenants(1, 0, 1000);
                        showParentTenantMenu(chatId, allTenants.getContent(), page);
                    }

                    else if (callbackData.startsWith("update_instances_")) {
                        Long regionId = Long.valueOf(callbackData.substring("update_instances_".length()));
                        handleUpdateInstances(chatId, regionId);
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
                sendMainMenu(chatId);
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
     * 发送主菜单 - 优化版本
     */
    private void sendMainMenu(Long chatId) {
        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        // 第一行：账号测活和一键升级
        List<InlineKeyboardButton> row1 = new ArrayList<>();
        InlineKeyboardButton accountCheckBtn = new InlineKeyboardButton();
        accountCheckBtn.setText("账号测活");
        accountCheckBtn.setCallbackData("account_check");
        row1.add(accountCheckBtn);

        InlineKeyboardButton upgradeBtn = new InlineKeyboardButton();
        upgradeBtn.setText("版本检查");
        upgradeBtn.setCallbackData("system_upgrade");
        row1.add(upgradeBtn);
        keyboard.add(row1);

        // 第二行：查询租户
        List<InlineKeyboardButton> row2 = new ArrayList<>();
        InlineKeyboardButton queryTenantBtn = new InlineKeyboardButton();
        queryTenantBtn.setText("我的账号");
        queryTenantBtn.setCallbackData("query_tenant");
        InlineKeyboardButton bootLogBtn = new InlineKeyboardButton();
        bootLogBtn.setText("开机日志");
        bootLogBtn.setCallbackData("boot_log");
        row2.add(queryTenantBtn);
        row2.add(bootLogBtn);
        keyboard.add(row2);


        // 底部菜单：GitHub链接和帮助
        List<InlineKeyboardButton> bottomRow = new ArrayList<>();
        InlineKeyboardButton githubBtn = new InlineKeyboardButton();
        githubBtn.setText("GitHub");
        githubBtn.setUrl("https://github.com/doubleDimple/oci-start");
        bottomRow.add(githubBtn);

        InlineKeyboardButton helpBtn = new InlineKeyboardButton();
        helpBtn.setText("帮助");
        helpBtn.setCallbackData("help");
        bottomRow.add(helpBtn);
        keyboard.add(bottomRow);

        markup.setKeyboard(keyboard);

        try {
            SendMessage message = SendMessage.builder()
                    .chatId(chatId)
                    .text("🚀 <b>OCI-START 智能助手</b>\n")
                    .parseMode("HTML")
                    .replyMarkup(markup)
                    .build();

            execute(message);
        } catch (TelegramApiException e) {
            log.error("发送主菜单失败: {}", e.getMessage(), e);
        }
    }

    /**
     * 处理账号测活功能 - 预留接口，等待具体实现
     */
    private void handleAccountCheck(Long chatId) {
        sendTextMessage(chatId, "🔍 开始执行账号测活，请稍等....");
        getTenantService().checkBatchAccounts();
    }

    /**
     * 处理系统升级功能 - 预留接口，等待具体实现
     */
    private void handleSystemUpgrade(Long chatId) {
        sendTextMessage(chatId, "⬆️ 开始执行系统升级，请稍后，升级过程中我会暂时离线，稍后回来");
        getVersionCheckTask().executeUpdate();
    }

    /**
     * 处理查询租户功能 - 显示父租户列表
     *
     */
    private void handleQueryTenant(Long chatId) {
        try {
            Page<Tenant> allTenants = getTenantService().getAllTenants(1, 0, 1000);
            List<Tenant> content = allTenants.getContent();

            if (content == null || content.isEmpty()) {
                sendTextMessage(chatId, "暂无账号信息");
                return;
            }

            // 显示父租户菜单
            showParentTenantMenu(chatId, content,1);

        } catch (Exception e) {
            log.error("查询租户时出错: {}", e.getMessage(), e);
            sendTextMessage(chatId, "查询租户时出现错误，请稍后重试。");
        }
    }


    /**
     * 显示父租户菜单
     */
    private void showParentTenantMenu(Long chatId, List<Tenant> tenants, int page) {

        int pageSize = 10;
        int total = tenants.size();
        int totalPage = (int) Math.ceil((double) total / pageSize);

        // 页码安全处理
        page = Math.max(1, Math.min(page, totalPage));

        int start = (page - 1) * pageSize;
        int end = Math.min(start + pageSize, total);

        List<Tenant> pageList = tenants.subList(start, end);

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        // 每行一个租户按钮
        for (int i = 0; i < pageList.size(); i++) {
            Tenant tenant = pageList.get(i);

            // 全局编号
            int index = start + i + 1;
            String displayName;
            final String defName = tenant.getDefName();
            if (StringUtils.isEmpty(defName) || "未设置".equals(defName)){
                displayName = tenant.getTenancyName();
            }else{
                displayName = tenant.getDefName();
            }
            List<Tenant> children = getTenantService().regionList(tenant.getId());
            int childrenCount = children != null ? children.size() : 1;

            InlineKeyboardButton btn = new InlineKeyboardButton();
            btn.setText(String.format("%s[主区:%s][%d个区域]", displayName, RegionEnum.getNameSimple(tenant.getRegion()), childrenCount));
            btn.setCallbackData("tenant_detail_" + tenant.getId());

            List<InlineKeyboardButton> row = new ArrayList<>();
            row.add(btn);
            keyboard.add(row);
        }

        // 分页按钮
        List<InlineKeyboardButton> navRow = new ArrayList<>();

        if (page > 1) {
            InlineKeyboardButton prev = new InlineKeyboardButton();
            prev.setText(BTN_LAST_PAGE);
            prev.setCallbackData("tenant_page_" + (page - 1));
            navRow.add(prev);
        }

        if (page < totalPage) {
            InlineKeyboardButton next = new InlineKeyboardButton();
            next.setText(BTN_NEXT_PAGE);
            next.setCallbackData("tenant_page_" + (page + 1));
            navRow.add(next);
        }

        if (!navRow.isEmpty()) {
            keyboard.add(navRow);
        }

        // 返回主菜单按钮
        InlineKeyboardButton back = new InlineKeyboardButton();
        back.setText(BTN_BACK_MAIN);
        back.setCallbackData("back_to_main");

        List<InlineKeyboardButton> backRow = new ArrayList<>();
        backRow.add(back);
        keyboard.add(backRow);

        markup.setKeyboard(keyboard);

        try {
            SendMessage msg = SendMessage.builder()
                    .chatId(chatId)
                    .text(String.format("账号列表（第 %d/%d 页）：", page, totalPage))
                    .parseMode("HTML")
                    .replyMarkup(markup)
                    .build();

            execute(msg);

        } catch (TelegramApiException e) {
            log.error("发送租户菜单失败: {}", e.getMessage(), e);
        }
    }


    /**
     * 显示租户详情（子区域列表）
     */
    private void showTenantDetail(Long chatId, Long tenantId) {
        try {
            Tenant tenant = getTenantService().getById(tenantId);
            if (tenant == null) {
                sendTextMessage(chatId, "未找到该租户信息");
                return;
            }

            String displayName = tenant.getTenancyName() + "["+tenant.getDefName()+"]";
            List<Tenant> children = getTenantService().regionList(tenantId);
            if (children == null || children.isEmpty()) {
                sendTextMessage(chatId, "该租户暂无子区域信息");
                return;
            }

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 为每个子区域创建按钮，每行显示两个
            List<InlineKeyboardButton> currentRow = new ArrayList<>();
            for (int i = 0; i < children.size(); i++) {
                Tenant child = children.get(i);
                InlineKeyboardButton childBtn = new InlineKeyboardButton();

                // 显示区域信息
                String regionDisplay = child.getRegion() != null ? child.getRegion() : "未知区域";
                String accountType = child.getAccountTypeName() != null ?
                        " (" + child.getAccountTypeName() + ")" : "";

                childBtn.setText(regionDisplay + accountType);
                childBtn.setCallbackData("region_info_" + child.getId());
                currentRow.add(childBtn);

                // 每两个按钮一行，或者到达最后一个元素时添加到keyboard
                if (currentRow.size() == 2 || i == children.size() - 1) {
                    keyboard.add(new ArrayList<>(currentRow));
                    currentRow.clear();
                }
            }

            // 添加返回按钮
            List<InlineKeyboardButton> backRow = new ArrayList<>();
            InlineKeyboardButton backToListBtn = new InlineKeyboardButton();
            backToListBtn.setText("🔙 返回账号列表");
            backToListBtn.setCallbackData("back_to_tenant_list");
            backRow.add(backToListBtn);

            InlineKeyboardButton backToMainBtn = new InlineKeyboardButton();
            backToMainBtn.setText("🏠 主菜单");
            backToMainBtn.setCallbackData("back_to_main");
            backRow.add(backToMainBtn);
            keyboard.add(backRow);

            markup.setKeyboard(keyboard);

            SendMessage message = SendMessage.builder()
                    .chatId(chatId)
                    .text(displayName)
                    .replyMarkup(markup)
                    .build();
            execute(message);

        } catch (Exception e) {
            log.error("显示租户详情时出错: {}", e.getMessage(), e);
            sendTextMessage(chatId, "获取租户详情时出现错误，请稍后重试。");
        }
    }

    /**
     * 显示区域详细信息
     */
    /**
     * 显示区域详细信息 - 已优化：增加更新实例按钮
     */
    private void showRegionInfo(Long chatId, Long regionId) {
        try {
            Tenant region = getTenantService().getById(regionId);
            if (region == null) {
                sendTextMessage(chatId, "未找到该区域信息");
                return;
            }

            Page<InstanceDetailsRes> allInstances = getOracleInstanceService().getAllInstances(0, 1000, region.getIdStr());
            List<InstanceDetailsRes> instances = allInstances.getContent();

            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 1. 如果有实例，渲染实例列表
            if (instances != null && !instances.isEmpty()) {
                for (InstanceDetailsRes instance : instances) {
                    List<InlineKeyboardButton> row = new ArrayList<>();
                    InlineKeyboardButton instanceBtn = new InlineKeyboardButton();

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

                    instanceBtn.setText(buttonText);
                    instanceBtn.setCallbackData("instance_detail_" + instance.getId());
                    row.add(instanceBtn);
                    keyboard.add(row);
                }
            }

            // 2. 构建底部操作行：返回 + 更新实例
            List<InlineKeyboardButton> actionRow = new ArrayList<>();

            // 返回按钮
            InlineKeyboardButton backBtn = new InlineKeyboardButton();
            backBtn.setText("🔙 返回");
            Long parenId = region.getParenId();
            if (parenId == 0L) parenId = region.getId();
            backBtn.setCallbackData("tenant_detail_" + parenId);
            actionRow.add(backBtn);

            // 更新实例按钮
            InlineKeyboardButton updateBtn = new InlineKeyboardButton();
            updateBtn.setText("🔄 更新实例");
            updateBtn.setCallbackData("update_instances_" + region.getId()); // 携带区域ID
            actionRow.add(updateBtn);

            keyboard.add(actionRow);
            markup.setKeyboard(keyboard);

            // 3. 构建头部文本
            int instanceCount = (instances != null) ? instances.size() : 0;
            String headerText = String.format("<b>%s</b>\n%s",
                    region.getRegion() != null ? region.getRegion() : "未知区域",
                    instanceCount > 0 ? "共 " + instanceCount + " 个实例" : "⚠️ 该区域暂无实例");

            SendMessage message = SendMessage.builder()
                    .chatId(chatId)
                    .text(headerText)
                    .parseMode("HTML")
                    .replyMarkup(markup)
                    .build();
            execute(message);

        } catch (Exception e) {
            log.error("显示区域实例信息时出错: {}", e.getMessage(), e);
            sendTextMessage(chatId, "获取实例信息时出现错误，请稍后重试。");
        }
    }
    private String getStateIcon(String state) {
        if (state == null) return "❓";

        switch (state.toUpperCase()) {
            case "RUNNING":
                return "✅";
            case "STOPPED":
            case "STOPPING":
                return "🔴";
            case "STARTING":
                return "🟡";
            case "PROVISIONING":
                return "🔄";
            case "TERMINATING":
                return "❌";
            case "TERMINATED":
                return "💀";
            default:
                return "❓";
        }
    }

    /**
     * 处理帮助功能
     */
    private void handleHelp(Long chatId) {
        String helpText = "<b>OCI-START 智能助手使用帮助</b>\n\n" +
                "<b>账号测活</b>：检查所有账号的活跃状态\n" +
                "<b>一键升级</b>：自动升级系统到最新版本\n" +
                "<b>查询租户</b>：查看租户信息和状态\n\n" +
                "<b>使用提示</b>：\n" +
                "• 使用 /menu 或 /start 打开主菜单\n" +
                "• 使用 /active 激活账号\n" +
                "• 点击按钮即可执行相应功能\n\n" +
                "<b>项目地址</b>：https://github.com/doubleDimple/oci-start\n" +
                "<b>开发者</b>：doubleDimple";

        try {
            SendMessage message = SendMessage.builder()
                    .chatId(chatId)
                    .text(helpText)
                    .parseMode("HTML")
                    .build();
            execute(message);
        } catch (TelegramApiException e) {
            log.error("发送帮助信息失败: {}", e.getMessage(), e);
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
                    .text("🤖 思考中...")
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
                        String currentText = "🤖 " + fullReply.toString();
                        // Telegram消息限制4096字符，编辑时截取前4000字符显示
                        if (currentText.length() > 4000) {
                            currentText = currentText.substring(0, 4000) + "\n\n⏳ 回复较长，生成中...";
                        }
                        editMessage(chatId, placeholderMessageId, currentText);
                    }
                });

                // 流式结束，发送最终完整回复
                String finalText = fullReply.toString();
                if (StringUtils.isBlank(finalText)) {
                    editMessage(chatId, placeholderMessageId, "🤖 抱歉，我无法回答你的问题。");
                    return;
                }

                // 处理最终消息：如果超过4096字符，需要分段发送
                String prefix = "🤖 ";
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
                editMessage(chatId, placeholderMessageId, "🤖 抱歉，AI服务暂时不可用，请稍后重试。");
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

    private void sendBootLogPage(Long chatId, int pageNum) {
        int pageSize = 5;
        Pageable pageable = PageRequest.of(pageNum - 1, pageSize);

        DynamicDailyTask task = applicationContext.getBean(DynamicDailyTask.class);
        Page<BootInstanceRes> bootPage = task.getBootList(pageable);

        if (bootPage.isEmpty()) {
            sendTextMessage(chatId, "暂无开机日志记录。");
            return;
        }

        // 获取分页元数据
        int totalPages = bootPage.getTotalPages();
        int currentPage = bootPage.getNumber() + 1; // 转换为 1 基准供用户查看

        // 3. 构建正文
        StringBuilder sb = new StringBuilder();
        sb.append("昨日预开机统计（第 ").append(currentPage).append(" / ").append(totalPages).append(" 页）\n\n");

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
            int num = (currentPage - 1) * pageSize + i + 1;
            String maskedDisplayName = getMaskedDisplayName(displayName);
            sb.append(num).append(". ")
                    .append(maskedDisplayName)
                    .append("\n")
                    .append("所属区域: ").append(item.getRegionName())
                    .append(" | ").append("架构: ").append(item.getArchitecture())
                    .append(" | ").append("状态: ").append(BootInstanceStatusEnum.getStatus(item.getStatus()).getName())
                    .append("\n")
                    .append("开始日期: ").append(item.getCreateAtStr()).append("\n")
                    .append("总计次数: ").append(item.getAddCount())
                    .append("  昨日: ").append(item.getYesterdayAttemptCount())
                    .append("  今日: ").append(item.getCurrentAttemptCount())
                    .append("  成功: ").append(item.getSuccessCount())
                    .append("  天数: ").append(daysBetweenCurrent(item.getCreateAtStr()))
                    .append("\n——— ——— ——— ——— ——— ——— ———\n");
        }

        InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
        List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

        List<InlineKeyboardButton> navRow = new ArrayList<>();
        if (bootPage.hasPrevious()) {
            InlineKeyboardButton prev = new InlineKeyboardButton();
            prev.setText(BTN_LAST_PAGE);
            prev.setCallbackData("boot_log_page_" + (currentPage - 1));
            navRow.add(prev);
        }
        if (bootPage.hasNext()) {
            InlineKeyboardButton next = new InlineKeyboardButton();
            next.setText(BTN_NEXT_PAGE);
            next.setCallbackData("boot_log_page_" + (currentPage + 1));
            navRow.add(next);
        }
        if (!navRow.isEmpty()) keyboard.add(navRow);

        // 返回主菜单
        InlineKeyboardButton backBtn = new InlineKeyboardButton();
        backBtn.setText(BTN_BACK_MAIN);
        backBtn.setCallbackData("back_to_main");

        List<InlineKeyboardButton> backRow = new ArrayList<>();
        backRow.add(backBtn);
        keyboard.add(backRow);

        markup.setKeyboard(keyboard);

        // 5. 发送消息
        SendMessage msg = SendMessage.builder()
                .chatId(chatId.toString())
                .text(sb.toString())
                .replyMarkup(markup)
                .parseMode("HTML")
                .build();

        try {
            execute(msg);
        } catch (Exception e) {
            log.error("发送开机日志分页失败,reason:{}", e.getMessage());
        }
    }

    private void showUpgradeMenu(Long chatId) {
        try {
            VersionCheckTask versionCheckTask = getVersionCheckTask();

            versionCheckTask.checkVersion();

            AppVersion version = versionCheckTask.getVersion();
            String current = version.getCurrentVersion();
            String latest = version.getLatestVersion();
            boolean needUpdate = version.needUpdate();

            StringBuilder sb = new StringBuilder();
            sb.append("🛠 <b>系统版本状态</b>\n\n");
            sb.append("当前版本：").append(current).append("\n");
            sb.append("最新版本：").append(latest).append("\n\n");

            if (!needUpdate) {
                sb.append("🎉 <b>您已是最新版本！</b>\n");
            } else {
                sb.append("⚠️ <b>可执行升级操作！</b>\n");
            }

            // —— 构建按钮 ——
            InlineKeyboardMarkup markup = new InlineKeyboardMarkup();
            List<List<InlineKeyboardButton>> keyboard = new ArrayList<>();

            // 需要升级才显示
            if (needUpdate) {
                InlineKeyboardButton upgradeBtn = new InlineKeyboardButton();
                upgradeBtn.setText("⬆️ 立即升级");
                upgradeBtn.setCallbackData("do_upgrade");
                keyboard.add(Collections.singletonList(upgradeBtn)); // Java8 支持
            }

            // 返回按钮
            InlineKeyboardButton backBtn = new InlineKeyboardButton();
            backBtn.setText(BTN_BACK_MAIN);
            backBtn.setCallbackData("back_to_main");
            keyboard.add(Collections.singletonList(backBtn));  // Java8 支持

            markup.setKeyboard(keyboard);

            SendMessage message = SendMessage.builder()
                    .chatId(chatId)
                    .text(sb.toString())
                    .parseMode("HTML")
                    .replyMarkup(markup)
                    .build();

            execute(message);

        } catch (Exception e) {
            log.error("展示升级菜单失败: {}", e.getMessage());
            sendTextMessage(chatId, "获取版本信息失败，请稍后重试。");
        }
    }

    private void handleUpdateInstances(Long chatId, Long regionId) {
        try {
            sendTextMessage(chatId, "正在同步实例信息，请稍候...");

            getTenantService().syncOci(regionId);

            sendTextMessage(chatId, "✅ 同步完成！");

            showRegionInfo(chatId, regionId);

        } catch (Exception e) {
            log.error("同步实例失败: {}", e.getMessage());
            sendTextMessage(chatId, "❌ 同步失败：" + e.getMessage());
        }
    }

    // 剧透处理

}