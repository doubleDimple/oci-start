package com.doubledimple.ociserver.utils.oracle.notify;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.NotificationSetting;
import com.oracle.bmc.identitydomains.model.NotificationSettings;
import com.oracle.bmc.identitydomains.requests.GetNotificationSettingRequest;
import com.oracle.bmc.identitydomains.requests.ListNotificationSettingsRequest;
import com.oracle.bmc.identitydomains.requests.PutNotificationSettingRequest;
import com.oracle.bmc.identitydomains.responses.GetNotificationSettingResponse;
import com.oracle.bmc.identitydomains.responses.ListNotificationSettingsResponse;
import com.oracle.bmc.identitydomains.responses.PutNotificationSettingResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils.initIdentityDomainsClient;

/**
 * 域通知设置管理工具类
 * 管理 Identity Domain 的通知收件人配置
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Slf4j
public class NotificationUtils {

    // SCIM Schema 常量
    private static final String NOTIFICATION_SETTINGS_SCHEMA = "urn:ietf:params:scim:schemas:oracle:idcs:NotificationSettings";

    // 默认设置ID
    private static final String NOTIFICATION_SETTINGS_ID = "NotificationSettings";

    // 邮箱验证正则表达式
    private static final Pattern EMAIL_PATTERN = Pattern.compile(
            "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
    );

    /**
     * 获取当前域通知设置
     *
     * @param tenant 租户信息
     * @return 当前通知设置
     */
    public static Map<String, Object> getCurrentNotificationSettings(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            GetNotificationSettingRequest request = GetNotificationSettingRequest.builder()
                    .notificationSettingId(NOTIFICATION_SETTINGS_ID)
                    .build();

            GetNotificationSettingResponse getResponse = identityDomainsClient.getNotificationSetting(request);
            NotificationSetting settings = getResponse.getNotificationSetting();

            Map<String, Object> settingsInfo = new HashMap<>();
            settingsInfo.put("id", settings.getId());
            settingsInfo.put("ocid", settings.getOcid());
            settingsInfo.put("notificationEnabled", settings.getNotificationEnabled());
            settingsInfo.put("testModeEnabled", settings.getTestModeEnabled());
            settingsInfo.put("testRecipients", settings.getTestRecipients());
            settingsInfo.put("sendNotificationsToSecondaryEmail", settings.getSendNotificationsToSecondaryEmail());

            // 提取发件人信息
            if (settings.getFromEmailAddress() != null) {
                Map<String, Object> fromEmailInfo = new HashMap<>();
                fromEmailInfo.put("value", settings.getFromEmailAddress().getValue());
                fromEmailInfo.put("validationStatus", settings.getFromEmailAddress().getValidationStatus());
                settingsInfo.put("fromEmailAddress", fromEmailInfo);
            }

            response.put("success", true);
            response.put("settings", settingsInfo);
            response.put("message", "通知设置获取成功");

            log.debug("租户 [{}] 的通知设置已获取，当前测试收件人: {}",
                    tenant.getTenancyName(), settings.getTestRecipients());

        } catch (Exception e) {
            log.error("获取通知设置失败: {}", e.getMessage(), e);
            response.put("message", "获取通知设置失败");
        } finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 更新单个通知收件人邮箱
     *
     * @param tenant 租户信息
     * @param newEmailAddress 新的收件人邮箱
     * @return 操作结果
     */
    public static Map<String, Object> updateNotificationRecipient(Tenant tenant, String newEmailAddress) {
        return updateNotificationRecipients(tenant, Collections.singletonList(newEmailAddress));
    }

    /**
     * 更新多个通知收件人邮箱（替换所有现有邮箱）
     *
     * @param tenant 租户信息
     * @param emailAddresses 新的收件人邮箱列表
     * @return 操作结果
     */
    public static Map<String, Object> updateNotificationRecipients(Tenant tenant, List<String> emailAddresses) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            // 验证邮箱格式
            List<String> validEmails = new ArrayList<>();
            List<String> invalidEmails = new ArrayList<>();

            for (String email : emailAddresses) {
                if (StringUtils.isBlank(email)){
                    continue;
                }
                if (isValidEmail(email)) {
                    validEmails.add(email.trim().toLowerCase());
                } else {
                    invalidEmails.add(email);
                }
            }

            if (!invalidEmails.isEmpty()) {
                response.put("message", "邮箱格式无效: " + String.join(", ", invalidEmails));
                return response;
            }

            if (validEmails.isEmpty()) {
                response.put("message", "没有有效的邮箱地址");
                return response;
            }

            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取当前设置
            GetNotificationSettingRequest getRequest = GetNotificationSettingRequest.builder()
                    .notificationSettingId(NOTIFICATION_SETTINGS_ID)
                    .build();

            GetNotificationSettingResponse getResponse = identityDomainsClient.getNotificationSetting(getRequest);
            NotificationSetting currentSettings = getResponse.getNotificationSetting();

            // 备份当前收件人
            List<String> previousRecipients = currentSettings.getTestRecipients();
            if (previousRecipients == null) {
                previousRecipients = new ArrayList<>();
            }

            log.info("当前收件人: {}", previousRecipients);

            // 构建更新的设置对象
            NotificationSetting updatedSettings = NotificationSetting.builder()
                    .copy(currentSettings)
                    .testRecipients(validEmails)
                    .testModeEnabled(true)
                    .schemas(Collections.singletonList(NOTIFICATION_SETTINGS_SCHEMA))
                    .build();

            // 执行更新
            PutNotificationSettingRequest putRequest = PutNotificationSettingRequest.builder()
                    .notificationSettingId(NOTIFICATION_SETTINGS_ID)
                    .notificationSetting(updatedSettings)
                    .build();

            PutNotificationSettingResponse putResponse = identityDomainsClient.putNotificationSetting(putRequest);

            response.put("success", true);
            response.put("previousRecipients", previousRecipients);
            response.put("newRecipients", validEmails);
            response.put("recipientCount", validEmails.size());
            response.put("message", String.format("通知收件人已成功更新为: %s", String.join(", ", validEmails)));

            log.info("租户 [{}] 的通知收件人已从 {} 更新为: {}",
                    tenant.getTenancyName(), previousRecipients, validEmails);

        } catch (Exception e) {
            log.error("更新通知收件人失败: {}", e.getMessage(), e);
            response.put("message", "更新通知收件人失败: " + e.getMessage());
        } finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 添加收件人（不覆盖现有收件人）
     *
     * @param tenant 租户信息
     * @param emailAddresses 要添加的收件人邮箱列表
     * @return 操作结果
     */
    public static Map<String, Object> addNotificationRecipients(Tenant tenant, List<String> emailAddresses) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            // 获取当前收件人
            Map<String, Object> currentResult = getCurrentNotificationSettings(tenant);
            if (!(Boolean) currentResult.get("success")) {
                response.put("message", "获取当前设置失败: " + currentResult.get("message"));
                return response;
            }

            @SuppressWarnings("unchecked")
            Map<String, Object> settings = (Map<String, Object>) currentResult.get("settings");
            @SuppressWarnings("unchecked")
            List<String> currentRecipients = (List<String>) settings.get("testRecipients");
            if (currentRecipients == null) {
                currentRecipients = new ArrayList<>();
            }

            // 验证并过滤新邮箱
            List<String> validNewEmails = new ArrayList<>();
            List<String> duplicateEmails = new ArrayList<>();
            List<String> invalidEmails = new ArrayList<>();

            for (String email : emailAddresses) {
                String cleanEmail = email.trim().toLowerCase();
                if (!isValidEmail(cleanEmail)) {
                    invalidEmails.add(email);
                } else if (currentRecipients.contains(cleanEmail)) {
                    duplicateEmails.add(cleanEmail);
                } else {
                    validNewEmails.add(cleanEmail);
                }
            }

            if (!invalidEmails.isEmpty()) {
                response.put("message", "邮箱格式无效: " + String.join(", ", invalidEmails));
                return response;
            }

            if (validNewEmails.isEmpty()) {
                response.put("success", true);
                response.put("message", "所有邮箱都已存在，无需添加");
                response.put("duplicateEmails", duplicateEmails);
                response.put("currentRecipients", currentRecipients);
                return response;
            }

            // 合并收件人列表
            List<String> mergedRecipients = new ArrayList<>(currentRecipients);
            mergedRecipients.addAll(validNewEmails);

            // 执行更新
            Map<String, Object> updateResult = updateNotificationRecipients(tenant, mergedRecipients);

            if ((Boolean) updateResult.get("success")) {
                response.put("success", true);
                response.put("addedRecipients", validNewEmails);
                response.put("duplicateEmails", duplicateEmails);
                response.put("totalRecipients", mergedRecipients.size());
                response.put("message", String.format("成功添加 %d 个收件人", validNewEmails.size()));
            } else {
                response.put("message", "添加收件人失败: " + updateResult.get("message"));
            }

        } catch (Exception e) {
            log.error("添加通知收件人失败: {}", e.getMessage(), e);
            response.put("message", "添加通知收件人失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 移除特定收件人
     *
     * @param tenant 租户信息
     * @param emailAddresses 要移除的收件人邮箱列表
     * @return 操作结果
     */
    public static Map<String, Object> removeNotificationRecipients(Tenant tenant, List<String> emailAddresses) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            // 获取当前收件人
            Map<String, Object> currentResult = getCurrentNotificationSettings(tenant);
            if (!(Boolean) currentResult.get("success")) {
                response.put("message", "获取当前设置失败: " + currentResult.get("message"));
                return response;
            }

            @SuppressWarnings("unchecked")
            Map<String, Object> settings = (Map<String, Object>) currentResult.get("settings");
            @SuppressWarnings("unchecked")
            List<String> currentRecipients = (List<String>) settings.get("testRecipients");
            if (currentRecipients == null) {
                currentRecipients = new ArrayList<>();
            }

            // 格式化移除的邮箱地址
            List<String> emailsToRemove = emailAddresses.stream()
                    .map(email -> email.trim().toLowerCase())
                    .collect(Collectors.toList());

            // 获取移除后的收件人列表
            List<String> remainingRecipients = currentRecipients.stream()
                    .filter(email -> !emailsToRemove.contains(email))
                    .collect(Collectors.toList());

            List<String> actuallyRemoved = currentRecipients.stream()
                    .filter(emailsToRemove::contains)
                    .collect(Collectors.toList());

            List<String> finalCurrentRecipients = currentRecipients;
            List<String> notFound = emailsToRemove.stream()
                    .filter(email -> !finalCurrentRecipients.contains(email))
                    .collect(Collectors.toList());

            if (actuallyRemoved.isEmpty()) {
                response.put("success", true);
                response.put("message", "没有找到要移除的收件人");
                response.put("notFound", notFound);
                response.put("currentRecipients", currentRecipients);
                return response;
            }

            // 检查是否会移除所有收件人
            if (remainingRecipients.isEmpty()) {
                response.put("message", "不能移除所有收件人，至少需要保留一个");
                return response;
            }

            // 执行更新
            Map<String, Object> updateResult = updateNotificationRecipients(tenant, remainingRecipients);

            if ((Boolean) updateResult.get("success")) {
                response.put("success", true);
                response.put("removedRecipients", actuallyRemoved);
                response.put("notFound", notFound);
                response.put("remainingRecipients", remainingRecipients);
                response.put("message", String.format("成功移除 %d 个收件人", actuallyRemoved.size()));
            } else {
                response.put("message", "移除收件人失败: " + updateResult.get("message"));
            }

        } catch (Exception e) {
            log.error("移除通知收件人失败: {}", e.getMessage(), e);
            response.put("message", "移除通知收件人失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 启用或禁用测试模式
     *
     * @param tenant 租户信息
     * @param enableTestMode 是否启用测试模式
     * @return 操作结果
     */
    public static Map<String, Object> updateTestMode(Tenant tenant, boolean enableTestMode) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取当前设置
            GetNotificationSettingRequest getRequest = GetNotificationSettingRequest.builder()
                    .notificationSettingId(NOTIFICATION_SETTINGS_ID)
                    .build();

            GetNotificationSettingResponse getResponse = identityDomainsClient.getNotificationSetting(getRequest);
            NotificationSetting currentSettings = getResponse.getNotificationSetting();

            // 保持现有收件人列表
            List<String> currentRecipients = currentSettings.getTestRecipients();
            if (currentRecipients == null) {
                currentRecipients = new ArrayList<>();
            }

            // 构建更新的设置对象
            NotificationSetting updatedSettings = NotificationSetting.builder()
                    .copy(currentSettings)
                    .testModeEnabled(enableTestMode)
                    .schemas(Arrays.asList(NOTIFICATION_SETTINGS_SCHEMA))
                    .build();

            // 执行更新
            PutNotificationSettingRequest putRequest = PutNotificationSettingRequest.builder()
                    .notificationSettingId(NOTIFICATION_SETTINGS_ID)
                    .notificationSetting(updatedSettings)
                    .build();

            identityDomainsClient.putNotificationSetting(putRequest);

            response.put("success", true);
            response.put("testMode", enableTestMode);
            response.put("recipients", currentRecipients);
            response.put("message", String.format("测试模式已%s", enableTestMode ? "启用" : "禁用"));

            log.info("租户 [{}] 的通知测试模式已{}", tenant.getTenancyName(), enableTestMode ? "启用" : "禁用");

        } catch (Exception e) {
            log.error("更新测试模式失败: {}", e.getMessage(), e);
            response.put("message", "更新测试模式失败: " + e.getMessage());
        } finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 获取当前所有收件人
     *
     * @param tenant 租户信息
     * @return 收件人列表
     */
    public static Map<String, Object> getCurrentRecipients(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            Map<String, Object> settingsResult = getCurrentNotificationSettings(tenant);

            if ((Boolean) settingsResult.get("success")) {
                @SuppressWarnings("unchecked")
                Map<String, Object> settings = (Map<String, Object>) settingsResult.get("settings");
                @SuppressWarnings("unchecked")
                List<String> recipients = (List<String>) settings.get("testRecipients");

                response.put("success", true);
                response.put("recipients", recipients != null ? recipients : new ArrayList<>());
                response.put("totalCount", recipients != null ? recipients.size() : 0);
                response.put("message", "收件人列表获取成功");
            } else {
                response.put("message", "获取收件人列表失败: " + settingsResult.get("message"));
            }

        } catch (Exception e) {
            log.error("获取收件人列表失败: {}", e.getMessage(), e);
            response.put("message", "获取收件人列表失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 列出所有通知设置（用于调试和验证）
     *
     * @param tenant 租户信息
     * @return 所有通知设置
     */
    public static Map<String, Object> listAllNotificationSettings(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            ListNotificationSettingsRequest request = ListNotificationSettingsRequest.builder()
                    .limit(100)
                    .build();

            ListNotificationSettingsResponse listResponse = identityDomainsClient.listNotificationSettings(request);
            NotificationSettings notificationSettings = listResponse.getNotificationSettings();

            List<Map<String, Object>> settingsList = new ArrayList<>();
            if (notificationSettings.getResources() != null) {
                for (NotificationSetting setting : notificationSettings.getResources()) {
                    Map<String, Object> settingInfo = new HashMap<>();
                    settingInfo.put("id", setting.getId());
                    settingInfo.put("ocid", setting.getOcid());
                    settingInfo.put("notificationEnabled", setting.getNotificationEnabled());
                    settingInfo.put("testModeEnabled", setting.getTestModeEnabled());
                    settingInfo.put("testRecipients", setting.getTestRecipients());
                    settingsList.add(settingInfo);
                }
            }

            response.put("success", true);
            response.put("schemas", notificationSettings.getSchemas());
            response.put("totalResults", notificationSettings.getTotalResults());
            response.put("Resources", settingsList);
            response.put("message", "通知设置列表获取成功");

            log.info("租户 [{}] 的通知设置列表已获取，共 {} 个设置",
                    tenant.getTenancyName(), settingsList.size());

        } catch (Exception e) {
            log.error("获取通知设置列表失败: {}", e.getMessage(), e);
            response.put("message", "获取通知设置列表失败: " + e.getMessage());
        } finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 获取收件人统计信息
     *
     * @param tenant 租户信息
     * @return 统计信息
     */
    public static Map<String, Object> getRecipientsStatistics(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            Map<String, Object> recipientsResult = getCurrentRecipients(tenant);

            if ((Boolean) recipientsResult.get("success")) {
                @SuppressWarnings("unchecked")
                List<String> recipients = (List<String>) recipientsResult.get("recipients");

                Map<String, Object> statistics = new HashMap<>();
                statistics.put("totalRecipients", recipients.size());
                statistics.put("recipients", recipients);

                // 按域名统计
                if (!recipients.isEmpty()) {
                    Map<String, Long> domainCount = recipients.stream()
                            .filter(email -> email.contains("@"))
                            .collect(Collectors.groupingBy(
                                    email -> email.substring(email.lastIndexOf("@") + 1).toLowerCase(),
                                    Collectors.counting()
                            ));
                    statistics.put("domainStatistics", domainCount);
                }

                response.put("success", true);
                response.put("statistics", statistics);
                response.put("message", "统计信息获取成功");
            } else {
                response.put("message", "获取统计信息失败: " + recipientsResult.get("message"));
            }

        } catch (Exception e) {
            log.error("获取收件人统计信息失败: {}", e.getMessage(), e);
            response.put("message", "获取统计信息失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 验证邮箱格式
     */
    private static boolean isValidEmail(String email) {
        if (StringUtils.isBlank(email)) {
            return false;
        }
        return EMAIL_PATTERN.matcher(email.trim()).matches();
    }
}
