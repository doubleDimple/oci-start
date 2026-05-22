package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.template.MessageTemplate;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.doubledimple.ociserver.service.message.TelegramMessageService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.response.AccountNotify;
import com.doubledimple.ociserver.pojo.response.DashboardStats;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.service.TenantService;
import com.oracle.bmc.ospgateway.model.Subscription;
import com.oracle.bmc.usageapi.model.UsageSummary;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.stereotype.Component;
import org.springframework.util.CollectionUtils;
import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.tg.TgUtils.getMaskedDisplayName;
import static com.doubledimple.ocicommon.utils.BigDecimalUtils.toCost;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.isWithinTimeRangeSimple;
import static com.doubledimple.ociserver.utils.oracle.CostUtils.queryCurrentMonthCostSimple;


/**
 * @version 1.0.0
 * @ClassName 执行账号测活的通知
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-01-03 21:00
 */
@Component
@EnableScheduling
@Slf4j
public class DynamicDailyTask {

    @Resource
    private MessageFactory messageFactory;

    @Resource
    private SystemConfigRepository systemConfigRepository;

    @Resource
    private TenantService tenantService;

    @Resource
    private BootTotalInstanceService bootTotalInstanceService;

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    TelegramMessageService telegramMessageService;

    @Resource
    private BootInstanceService bootInstanceService;

    @Resource
    RegisterDetailRepository registerDetailRepository;


    // 默认配置
    private static final int DEFAULT_HOUR = 9;
    private static final boolean DEFAULT_ENABLED = false;
    private static final String HOUR_CONFIG_KEY = "task.execute.hour";
    private static final String ENABLED_CONFIG_KEY = "task.enabled";

    private static final String ENABLE_ACCOUNT_CHECK_KEY = "task.enable.account-check";
    private static final String ENABLE_BOOT_LOG_KEY = "task.enable.boot-log";

    //花费统计
    private static final String ENABLE_COST_STATISTICS_KEY = "task.enable.cost-check";


    public void checkAndExecuteTask() {

        int hour = getConfigValue(HOUR_CONFIG_KEY, DEFAULT_HOUR);
        boolean enabled = getConfigEnabled(ENABLED_CONFIG_KEY, DEFAULT_ENABLED);

        if (!enabled) {
            log.debug("通知定时任务已禁用，不执行任何自动任务");
            return;
        }

        // 检查是否到达指定执行时间
        if (!isWithinTimeRangeSimple(hour)) {
            log.debug("当前时间不在指定时间范围内，不执行自动任务");
            return;
        }

        log.info("到达执行时间，开始执行自动任务...");

        boolean enableAccountCheck = getConfigValueAsBoolean(ENABLE_ACCOUNT_CHECK_KEY);
        boolean enableBootLog = getConfigValueAsBoolean(ENABLE_BOOT_LOG_KEY);
        boolean enableCostCheck = getConfigValueAsBoolean(ENABLE_COST_STATISTICS_KEY);
        //账号测活开关
        if (enableAccountCheck) {
            try {
                log.info("执行账号测活任务...");
                doNotifyAccountAccounts();
            } catch (Exception e) {
                log.error("账号测活任务执行失败,原因为:{}", e.getMessage());
            }
        }

        //抢机日志通知开关
        if (enableBootLog) {
            try {
                log.info("执行抢机日志任务...");
                doNotifyOpenBootCount();
            } catch (Exception e) {
                log.error("抢机日志任务执行失败,原因为:{}", e.getMessage());
            }
        }


        //花费统计开关
        if (enableCostCheck) {
            try {
                log.info("执行花费统计任务...");
                doNotifyCostCheck();
            } catch (Exception e) {
                log.error("花费统计任务执行失败,原因为:{}", e.getMessage());
            }
        }
    }

    public void doNotifyCostCheck() {

        Page<Tenant> allTenants = tenantService.findParentTenant(1,0,1000);
        if (allTenants == null || CollectionUtils.isEmpty(allTenants.getContent())) {
            log.warn("没有获取到租户信息");
            return;
        }

        List<Tenant> all = allTenants.getContent();
        StringBuilder sb = new StringBuilder();
        int i = 0;
        for (Tenant tenant : all) {
            Optional<RegisterDetail> byTenantId = registerDetailRepository.findByTenantId(String.valueOf(tenant.getTenantId()));
            if (byTenantId.isPresent()){
                RegisterDetail registerDetail = byTenantId.get();
                Subscription.PlanType planType = registerDetail.getPlanType();
                if (planType.equals(Subscription.PlanType.Payg)){
                    //查询当月花费
                    List<UsageSummary> summaries = queryCurrentMonthCostSimple(tenant);
                    //过滤币种不为空的记录
                    List<UsageSummary> usageSummaries = summaries.stream().filter(usageSummary -> StringUtils.isNotBlank(usageSummary.getCurrency())).collect(Collectors.toList());
                    if (!CollectionUtils.isEmpty(usageSummaries)){
                        UsageSummary usageSummary = usageSummaries.get(0);
                        String attributedCost = usageSummary.getAttributedCost();
                        String currency = usageSummary.getCurrency();
                        Date timeUsageStarted = usageSummary.getTimeUsageStarted();
                        Date timeUsageEnded = usageSummary.getTimeUsageEnded();
                        String displayName;
                        final String defName = tenant.getDefName();
                        if (StringUtils.isEmpty(defName) || "未设置".equals(defName)){
                            displayName = tenant.getTenancyName();
                        }else{
                            displayName = tenant.getDefName();
                        }
                        int num = i + 1;
                        sb.append(num).append(". ")
                                .append(getMaskedDisplayName(displayName))
                                .append(" | ")
                                .append(RegionEnum.getNameCh(tenant.getRegion()))
                                .append("\n")
                                .append("本月花费: ").append("\n")
                                .append("金额: ").append(toCost(attributedCost))
                                .append("  币种: ").append(currency)
                                .append("\n——— ——— ——— ——— ——— ———\n");
                        i++;
                    }
                }
            }
        }

        final String message = sb.toString();
        if (!StringUtils.isEmpty(message)){
            try {
                telegramMessageService.sendMessageTemplateText(message);
            } catch (Exception e) {
                log.warn("发送消息失败，错误:{}", e.getMessage());
            }
        }
    }

    private boolean getConfigValueAsBoolean(String key) {
        try {
            SystemConfig config = systemConfigRepository.findByKey(key).orElse(null);
            if (config != null && config.getValue() != null) {
                return "1".equals(config.getValue().trim());
            }
        } catch (Exception e) {
            log.warn("读取布尔配置失败 key={} error={}", key, e.getMessage());
        }
        return false;
    }


    /**
    * @Description: 所有账号前一天抢机次数推送
    * @Param: []
    * @return: void
    * @Author: doubleDimple
    * @Date: 11/22/25 12:13 PM
    */
    public void doNotifyOpenBootCount() {
        messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(getOpenCount());
    }

    /**
    * @Description: 获取抢机详情
    * @Param: []
    * @return: java.lang.String
    * @Author: doubleDimple
    * @Date: 11/22/25 1:21 PM
    */
    public String getOpenCount(){
        String msg = StringUtils.EMPTY;
        Page<BootInstanceRes> bootPage = bootInstanceService.getAllBoots(0, 1000);
        if (bootPage != null && !CollectionUtils.isEmpty(bootPage.getContent())) {
            List<BootInstanceRes> content = bootPage.getContent();
            StringBuilder sb = new StringBuilder();
            sb.append("昨日预开机统计\n\n");
            int index = 1;
            for (BootInstanceRes item : content) {
                sb.append(index).append(". ")
                        .append(getMaskedDisplayName(item.getTenancyName()))
                        .append(" | ").append(item.getRegionName()).append("\n")
                        .append("总次数: ").append(item.getTotalCount())
                        .append("  昨日: ").append(item.getYesterdayAttemptCount())
                        .append("  成功: ").append(item.getSuccessCount())
                        .append("\n");

                index++;
            }
            msg = sb.toString();
        }
        return msg;
    }

    private void doNotifyAccountAccounts() {
        log.debug("执行通知任务开始...");
        try {
            //账号检测通知
            AccountNotify accountNotify = checkBatchAccounts();
            //账号总计通知
            DashboardStats dashboardStats = bootTotalInstanceService.count();

            if (dashboardStats != null && accountNotify != null) {
                //账号数
                long totalApiCalls = dashboardStats.getTotalApiCalls();
                //抢机数量
                long totalAttempts = dashboardStats.getTotalAttempts();
                //成功数
                long successfulAttempts = dashboardStats.getSuccessfulAttempts();

                String message = MessageTemplate.getMessage(
                        accountNotify.getTotalAccount(),
                        accountNotify.getInActiveAccount(),
                        accountNotify.getInActiveAccountNames(),
                        totalApiCalls,
                        totalAttempts,
                        successfulAttempts
                );

                try {
                    telegramMessageService.sendMessageTemplate(message);
                } catch (Exception e) {
                    log.warn("发送消息失败，错误:{}", e.getMessage());
                }

            }
        } catch (Exception e) {
            log.error("执行通知任务出现失败,原因为:{}", e.getMessage(), e);
        }
    }

    private AccountNotify checkBatchAccounts() {
        AccountNotify accountNotify = new AccountNotify();
        try {
            //Page<Tenant> allTenants = tenantService.getAllTenants(1, 0, 1000);
            Page<Tenant> allTenants = tenantService.findParentTenant(1,0,1000);
            if (allTenants == null || CollectionUtils.isEmpty(allTenants.getContent())) {
                log.warn("没有获取到租户信息");
                return accountNotify;
            }

            List<Tenant> all = allTenants.getContent();
            int totalAccounts = all.size();
            int activeAccounts = 0;
            int inactiveAccounts = 0;
            List<String> inactiveAccountNames = new ArrayList<>();
            List<Long> inactiveTenantIds = new ArrayList<>();

            for (Tenant tenant : all) {
                try {
                    ResponseEntity<?> responseEntity = oracleInstanceService.checkAccountStatus(tenant.getId());
                    boolean isActive = isStatusSuccess(responseEntity);
                    if (isActive) {
                        activeAccounts++;
                    } else {
                        inactiveAccounts++;
                        inactiveAccountNames.add(tenant.getUserName());
                        inactiveTenantIds.add(tenant.getId());
                    }
                } catch (Exception e) {
                    log.warn("检查账号状态失败，租户ID: {}, 错误: {}", tenant.getId(), e.getMessage());
                    inactiveAccounts++;
                    inactiveAccountNames.add(tenant.getUserName());
                }
            }

            if (!CollectionUtils.isEmpty(inactiveTenantIds)) {
                try {
                    tenantService.batchUpdateStatusToInactive(inactiveTenantIds);
                    log.info("成功批量标记 {} 个失效账号", inactiveTenantIds.size());
                } catch (Exception e) {
                    log.error("批量更新账号失效状态失败", e);
                }
            }

            accountNotify.setTotalAccount(totalAccounts);
            accountNotify.setInActiveAccount(inactiveAccounts);
            accountNotify.setActiveAccount(activeAccounts);
            accountNotify.setInActiveAccountNames(StringUtils.join(inactiveAccountNames, ","));

        } catch (Exception e) {
            log.error("批量检查账号状态失败", e);
        }

        return accountNotify;
    }


    /**
     * 安全获取配置值
     */
    private int getConfigValue(String key, int defaultValue) {
        try {
            SystemConfig config = systemConfigRepository.findByKey(key).orElse(null);
            if (config != null && StringUtils.isNotBlank(config.getValue())) {
                return Integer.parseInt(config.getValue().trim());
            }
        } catch (Exception e) {
            log.warn("获取配置失败，key: {}, 使用默认值: {}, 错误: {}", key, defaultValue, e.getMessage());
        }
        return defaultValue;
    }

    /**
     * 安全获取配置启用状态
     */
    private boolean getConfigEnabled(String key, boolean defaultValue) {
        try {
            SystemConfig config = systemConfigRepository.findByKey(key).orElse(null);
            if (config != null) {
                return config.isEnabled();
            }
        } catch (Exception e) {
            log.warn("获取启用配置失败，key: {}, 使用默认值: {}, 错误: {}", key, defaultValue, e.getMessage());
        }
        return defaultValue;
    }

    private boolean isStatusSuccess(ResponseEntity<?> responseEntity) {
        try {
            if (responseEntity != null && responseEntity.getBody() instanceof Map) {
                Map<String, Object> result = (Map<String, Object>) responseEntity.getBody();
                return "success".equals(result.get("status"));
            }
        } catch (Exception e) {
            log.warn("解析状态响应失败", e);
        }
        return false;
    }

    public Page<BootInstanceRes> getBootList(Pageable pageable) {
        Page<BootInstanceRes> bootPage = bootInstanceService.findAllWithTenantInfo(null,pageable);
        return bootPage;
    }

}
