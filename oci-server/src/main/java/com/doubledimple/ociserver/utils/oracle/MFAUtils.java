package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.AuthenticationFactorSetting;
import com.oracle.bmc.identitydomains.model.Group;
import com.oracle.bmc.identitydomains.model.MyDevice;
import com.oracle.bmc.identitydomains.requests.GetAuthenticationFactorSettingRequest;
import com.oracle.bmc.identitydomains.requests.ListAuthenticationFactorSettingsRequest;
import com.oracle.bmc.identitydomains.requests.ListMyDevicesRequest;
import com.oracle.bmc.identitydomains.requests.PutAuthenticationFactorSettingRequest;
import com.oracle.bmc.identitydomains.responses.GetAuthenticationFactorSettingResponse;
import com.oracle.bmc.identitydomains.responses.ListAuthenticationFactorSettingsResponse;
import com.oracle.bmc.identitydomains.responses.ListMyDevicesResponse;
import com.oracle.bmc.identitydomains.responses.PutAuthenticationFactorSettingResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.util.CollectionUtils;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils.RULE_CONSOLE_ADMIN_ID;
import static com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils.addGroupsToSignOnRule;
import static com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils.getGroups;
import static com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils.initIdentityDomainsClient;
import static com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils.updateSignOnRuleEmailLoginPatch;

/**
 * MFA 邮箱验证码工具类
 * 提供启用邮箱 MFA、发送验证码、验证验证码等功能
 *
 * @author doubleDimple
 * @date 2025-08-25
 */
@Slf4j
public class MFAUtils {

    public static final String SETTINGS_ID = "AuthenticationFactorSettings";
    public static final String DEFAULT_GROUP_ID_KEY_NAME = "OCI_Administrators";

    /**
     * 启用邮箱作为 MFA 验证因子
     *
     * @param tenant 租户信息
     * @param enableEmail 邮箱启用禁用
     * @return 操作结果
     */
    public static Map<String, Object> enableEmailMFA(Tenant tenant,Boolean enableEmail,List<String> groupIds) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            GetAuthenticationFactorSettingResponse getResponse =
                    identityDomainsClient.getAuthenticationFactorSetting(GetAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .build());

            AuthenticationFactorSetting currentSettings = getResponse.getAuthenticationFactorSetting();

            // 第一步:mfa配置邮箱验证
            AuthenticationFactorSetting updatedSettings = AuthenticationFactorSetting.builder()
                    .copy(currentSettings)
                    .emailEnabled(enableEmail)
                    .build();

            PutAuthenticationFactorSettingRequest putRequest = PutAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .authenticationFactorSetting(updatedSettings)
                            .build();

            if (enableEmail){
                identityDomainsClient.putAuthenticationFactorSetting(putRequest);
                updateSignOnRuleEmailLoginPatch(identityDomainsClient,tenant, RULE_CONSOLE_ADMIN_ID, enableEmail);
            }else{
                Map<String, Object> stringObjectMap = updateSignOnRuleEmailLoginPatch(identityDomainsClient,tenant, RULE_CONSOLE_ADMIN_ID, enableEmail);
                if (stringObjectMap.get("success").equals(true)){
                    identityDomainsClient.putAuthenticationFactorSetting(putRequest);
                }
            }

            //第三步: 为登录规则配置 组
            if (enableEmail){
                if (CollectionUtils.isEmpty(groupIds)){
                    List<Group> groups = getGroups(tenant, identityDomainsClient,DEFAULT_GROUP_ID_KEY_NAME);
                    if (!CollectionUtils.isEmpty(groups)){
                        groupIds = groups.stream().map(Group::getId).collect(Collectors.toList());
                    }else {
                        log.warn("未找到默认的组，请手动指定组");
                        throw new RuntimeException("未找group");
                    }
                }
                addGroupsToSignOnRule(identityDomainsClient,tenant, RULE_CONSOLE_ADMIN_ID, groupIds);
            }


            //第四步:为mfa启用或者禁用邮箱
            HashMap<String, Boolean> stringBooleanHashMap = new HashMap<>();
            stringBooleanHashMap.put("emailEnabled", enableEmail);
            updateMFASettings(identityDomainsClient,tenant,stringBooleanHashMap);

            log.info("租户 [{}] 的邮箱 MFA 已更新", tenant.getTenancyName());
            response.put("success", true);
            response.put("message", "邮箱 MFA 功能已成功更新");

        } catch (Exception e) {
            log.error("更新邮箱 MFA 失败: {}", e.getMessage(), e);
            response.put("message", "更新邮箱 MFA 失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 启用多个 MFA 因子（邮箱、短信、移动应用等）
     *
     * @param tenant 租户信息
     * @param enableEmail 是否启用邮箱验证
     * @param enableSms 是否启用短信验证
     * @param enableTotpEnabled 是否启用 TOTP（移动应用）验证
     * @param enableTrustedDevice 是否启用设备信任
     * @return 操作结果
     */
    public static Map<String, Object> configureAllMFAFactors(Tenant tenant,
                                                             Boolean enableEmail,
                                                             Boolean enableSms,
                                                             Boolean enableTotpEnabled,
                                                             Boolean enableTrustedDevice) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;
        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取当前设置
            GetAuthenticationFactorSettingRequest getRequest =
                    GetAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .build();

            GetAuthenticationFactorSettingResponse getResponse =
                    identityDomainsClient.getAuthenticationFactorSetting(getRequest);

            AuthenticationFactorSetting currentSettings = getResponse.getAuthenticationFactorSetting();

            // 构建更新的设置
            AuthenticationFactorSetting.Builder settingsBuilder = AuthenticationFactorSetting.builder()
                    .copy(currentSettings);

            if (enableEmail != null) {
                settingsBuilder.emailEnabled(enableEmail);
            }
            if (enableSms != null) {
                settingsBuilder.smsEnabled(enableSms);
            }
            if (enableTotpEnabled != null) {
                settingsBuilder.totpEnabled(enableTotpEnabled);
            }
            // 注意：设备信任可能需要其他配置，这里先预留

            AuthenticationFactorSetting updatedSettings = settingsBuilder.build();

            // 更新设置
            PutAuthenticationFactorSettingRequest putRequest =
                    PutAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .authenticationFactorSetting(updatedSettings)
                            .build();

            identityDomainsClient.putAuthenticationFactorSetting(putRequest);

            log.info("租户 [{}] 的 MFA 配置已更新 - 邮箱: {}, 短信: {}, TOTP: {}",
                    tenant.getTenancyName(), enableEmail, enableSms, enableTotpEnabled);

            response.put("success", true);
            response.put("message", "MFA 配置已成功更新");
            response.put("emailEnabled", enableEmail);
            response.put("smsEnabled", enableSms);
            response.put("totpEnabled", enableTotpEnabled);

        } catch (Exception e) {
            log.error("配置 MFA 失败: {}", e.getMessage(), e);
            response.put("message", "配置 MFA 失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 获取当前的 MFA 配置状态
     *
     * @param tenant 租户信息
     * @return MFA 配置信息
     */
    public static Map<String, Object> getMFAConfiguration(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        IdentityDomainsClient identityDomainsClient = null;

        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取 MFA 设置
            GetAuthenticationFactorSettingRequest getRequest =
                    GetAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .build();

            GetAuthenticationFactorSettingResponse getResponse =
                    identityDomainsClient.getAuthenticationFactorSetting(getRequest);

            AuthenticationFactorSetting settings = getResponse.getAuthenticationFactorSetting();

            response.put("success", true);
            response.put("emailEnabled", settings.getEmailEnabled());
            response.put("smsEnabled", settings.getSmsEnabled());
            response.put("totpEnabled", settings.getTotpEnabled());
            response.put("pushEnabled", settings.getSmsEnabled());
            response.put("securityQuestionsEnabled", settings.getSecurityQuestionsEnabled());
            response.put("message", "获取 MFA 配置成功");

            log.debug("租户 [{}] MFA 配置 - 邮箱: {}, 短信: {}, TOTP: {}",
                    tenant.getTenancyName(),
                    settings.getEmailEnabled(),
                    settings.getSmsEnabled(),
                    settings.getTotpEnabled());

        } catch (Exception e) {
            log.error("获取 MFA 配置失败: {}", e.getMessage(), e);
            response.put("message", "获取 MFA 配置失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 配置邮箱 MFA 的详细设置（验证码长度、有效期等）
     *
     * @param tenant 租户信息
     * @param passcodeLength 验证码长度（默认6位）
     * @param validityMinutes 验证码有效期（分钟，默认5分钟）
     * @return 操作结果
     */
    public static Map<String, Object> configureEmailMFASettings(Tenant tenant,
                                                                Integer passcodeLength,
                                                                Integer validityMinutes) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取当前设置
            GetAuthenticationFactorSettingRequest getRequest =
                    GetAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .build();

            GetAuthenticationFactorSettingResponse getResponse =
                    identityDomainsClient.getAuthenticationFactorSetting(getRequest);

            AuthenticationFactorSetting currentSettings = getResponse.getAuthenticationFactorSetting();

            // 配置邮箱设置（这里需要根据实际的 API 结构调整）
            // 注意：具体的邮箱配置字段可能需要查看 AuthenticationFactorSettingsEmailSettings
            AuthenticationFactorSetting.Builder settingsBuilder = AuthenticationFactorSetting.builder()
                    .copy(currentSettings)
                    .emailEnabled(true);

            // 如果 API 支持设置验证码长度和有效期，在这里配置
            // 这可能需要 AuthenticationFactorSettingsEmailSettings 对象

            AuthenticationFactorSetting updatedSettings = settingsBuilder.build();

            // 更新设置
            PutAuthenticationFactorSettingRequest putRequest =
                    PutAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .authenticationFactorSetting(updatedSettings)
                            .build();

            identityDomainsClient.putAuthenticationFactorSetting(putRequest);

            log.info("租户 [{}] 的邮箱 MFA 详细设置已配置", tenant.getTenancyName());
            response.put("success", true);
            response.put("message", "邮箱 MFA 详细设置已成功配置");

        } catch (Exception e) {
            log.error("配置邮箱 MFA 详细设置失败: {}", e.getMessage(), e);
            response.put("message", "配置邮箱 MFA 详细设置失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 完全禁用所有 MFA 验证因子
     *
     * @param tenant 租户信息
     * @return 操作结果
     */
    public static Map<String, Object> disableAllMFA(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        IdentityDomainsClient identityDomainsClient = null;

        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取当前设置
            GetAuthenticationFactorSettingRequest getRequest =
                    GetAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .build();

            GetAuthenticationFactorSettingResponse getResponse =
                    identityDomainsClient.getAuthenticationFactorSetting(getRequest);

            AuthenticationFactorSetting currentSettings = getResponse.getAuthenticationFactorSetting();

            // 禁用所有 MFA 验证因子
            AuthenticationFactorSetting updatedSettings = AuthenticationFactorSetting.builder()
                    .copy(currentSettings)
                    .emailEnabled(false)                    // 禁用邮箱验证
                    .smsEnabled(false)                      // 禁用短信验证
                    .totpEnabled(false)                     // 禁用 TOTP 验证
                    .pushEnabled(false)                     // 禁用推送通知验证
                    .securityQuestionsEnabled(false)       // 禁用安全问题验证
                    .build();

            // 更新设置
            PutAuthenticationFactorSettingRequest putRequest =
                    PutAuthenticationFactorSettingRequest.builder()
                            .authenticationFactorSettingId(SETTINGS_ID)
                            .authenticationFactorSetting(updatedSettings)
                            .build();

            identityDomainsClient.putAuthenticationFactorSetting(putRequest);

            log.info("租户 [{}] 的所有 MFA 验证因子已禁用", tenant.getTenancyName());
            response.put("success", true);
            response.put("message", "所有 MFA 验证因子已成功禁用");
            response.put("disabledFactors", new String[]{"email", "sms", "totp", "push", "securityQuestions"});

        } catch (Exception e) {
            log.error("禁用所有 MFA 失败: {}", e.getMessage(), e);
            response.put("message", "禁用所有 MFA 失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }


    /**
     * 获取用户的MFA设备列表（两步验证）
     *
     * @param tenant 租户信息
     * @param userId 用户ID（可选，为空则获取所有用户的MFA设备）
     * @return MFA设备列表
     */
    public static Map<String, Object> getUserMFADevices(Tenant tenant, String userId) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 构建查询请求
            ListMyDevicesRequest.Builder requestBuilder = ListMyDevicesRequest.builder()
                    .limit(100)
                    .attributes("id,displayName,deviceType,status,authenticationMethod,lastUsedOn");

            // 如果指定了用户ID，则过滤该用户的设备
            if (StringUtils.isNotEmpty(userId)) {
                requestBuilder.filter(String.format("user.value eq \"%s\"", userId));
            }

            ListMyDevicesRequest request = requestBuilder.build();
            ListMyDevicesResponse listResponse = identityDomainsClient.listMyDevices(request);

            List<MyDevice> devices = listResponse.getMyDevices().getResources();

            // 转换为需要的格式
            List<Map<String, Object>> deviceList = devices.stream().map(device -> {
                Map<String, Object> deviceInfo = new HashMap<>();
                deviceInfo.put("id", device.getId());
                deviceInfo.put("displayName", device.getDisplayName());
                deviceInfo.put("deviceType", device.getDeviceType());
                deviceInfo.put("status", device.getStatus());
                deviceInfo.put("authenticationMethod", device.getAuthenticationMethod());
                deviceInfo.put("isCompliant", device.getIsCompliant());
                deviceInfo.put("ocid", device.getOcid());
                return deviceInfo;
            }).collect(Collectors.toList());

            response.put("success", true);
            response.put("devices", deviceList);
            response.put("totalDevices", deviceList.size());
            response.put("message", "MFA设备列表获取成功");

            log.info("租户 [{}] 的MFA设备已获取，共 {} 个设备", tenant.getTenancyName(), deviceList.size());

        } catch (Exception e) {
            log.error("获取MFA设备列表失败: {}", e.getMessage(), e);
            response.put("message", "获取MFA设备列表失败: " + e.getMessage());
        } finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }


    /**
     * 获取MFA认证因子配置
     *
     * @param tenant 租户信息
     * @return MFA认证因子配置
     */
    public static Map<String, Object> getMFAAuthenticationFactors(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取认证因子设置
            ListAuthenticationFactorSettingsRequest request = ListAuthenticationFactorSettingsRequest.builder()
                    .limit(100)
                    .build();

            ListAuthenticationFactorSettingsResponse listResponse = identityDomainsClient.listAuthenticationFactorSettings(request);
            List<AuthenticationFactorSetting> settings = listResponse.getAuthenticationFactorSettings().getResources();

            // 转换为需要的格式
            List<Map<String, Object>> factorList = settings.stream().map(setting -> {
                Map<String, Object> factorInfo = new HashMap<>();
                factorInfo.put("id", setting.getId());
                factorInfo.put("emailEnabled", setting.getEmailEnabled());
                factorInfo.put("smsEnabled", setting.getSmsEnabled());
                factorInfo.put("totpEnabled", setting.getTotpEnabled());
                factorInfo.put("pushEnabled", setting.getPushEnabled());
                factorInfo.put("fidoAuthenticatorEnabled", setting.getFidoAuthenticatorEnabled());
                factorInfo.put("securityQuestionsEnabled", setting.getSecurityQuestionsEnabled());
                factorInfo.put("phoneCallEnabled", setting.getPhoneCallEnabled());
                factorInfo.put("ocid", setting.getOcid());
                return factorInfo;
            }).collect(Collectors.toList());

            response.put("success", true);
            response.put("authenticationFactors", factorList);
            response.put("message", "MFA认证因子配置获取成功");

            log.info("租户 [{}] 的MFA认证因子配置已获取", tenant.getTenancyName());

        } catch (Exception e) {
            log.error("获取MFA认证因子配置失败: {}", e.getMessage(), e);
            response.put("message", "获取MFA认证因子配置失败: " + e.getMessage());
        } finally {
            if (identityDomainsClient != null) {
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
     * 更新MFA认证因子设置
     *
     * @param tenant 租户信息
     * @param mfaConfig MFA配置
     * @return 操作结果
     */
    public static Map<String, Object>   updateMFASettings(IdentityDomainsClient identityDomainsClient,Tenant tenant, Map<String, Boolean> mfaConfig) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        try {
            if (identityDomainsClient == null){
                identityDomainsClient = initIdentityDomainsClient(tenant);
            }

            // 1. 获取当前设置 - 先查看现有的schema
            GetAuthenticationFactorSettingRequest getRequest = GetAuthenticationFactorSettingRequest.builder()
                    .authenticationFactorSettingId(SETTINGS_ID)
                    .build();

            GetAuthenticationFactorSettingResponse getResponse = identityDomainsClient.getAuthenticationFactorSetting(getRequest);
            AuthenticationFactorSetting currentSetting = getResponse.getAuthenticationFactorSetting();

            // 打印当前设置的schema信息，用于调试
            log.debug("当前AuthenticationFactorSetting的schemas: {}", currentSetting.getSchemas());

            // 2. 构建更新的设置对象 - 使用原有的schemas
            AuthenticationFactorSetting.Builder settingBuilder = AuthenticationFactorSetting.builder()
                    .copy(currentSetting);

            // 保持原有的schemas，不要覆盖
            if (currentSetting.getSchemas() != null && !currentSetting.getSchemas().isEmpty()) {
                settingBuilder.schemas(currentSetting.getSchemas());
            }

            // 3. 应用配置更新
            if (mfaConfig.containsKey("emailEnabled")) {
                settingBuilder.emailEnabled(mfaConfig.get("emailEnabled"));
            }
            if (mfaConfig.containsKey("smsEnabled")) {
                settingBuilder.smsEnabled(mfaConfig.get("smsEnabled"));
            }
            if (mfaConfig.containsKey("totpEnabled")) {
                settingBuilder.totpEnabled(mfaConfig.get("totpEnabled"));
            }
            if (mfaConfig.containsKey("pushEnabled")) {
                settingBuilder.pushEnabled(mfaConfig.get("pushEnabled"));
            }
            if (mfaConfig.containsKey("fidoAuthenticatorEnabled")) {
                settingBuilder.fidoAuthenticatorEnabled(mfaConfig.get("fidoAuthenticatorEnabled"));
            }
            if (mfaConfig.containsKey("securityQuestionsEnabled")) {
                settingBuilder.securityQuestionsEnabled(mfaConfig.get("securityQuestionsEnabled"));
            }
            if (mfaConfig.containsKey("phoneCallEnabled")) {
                settingBuilder.phoneCallEnabled(mfaConfig.get("phoneCallEnabled"));
            }

            AuthenticationFactorSetting updatedSetting = settingBuilder.build();

            // 4. 执行更新
            PutAuthenticationFactorSettingRequest putRequest = PutAuthenticationFactorSettingRequest.builder()
                    .authenticationFactorSettingId(SETTINGS_ID)
                    .authenticationFactorSetting(updatedSetting)
                    .build();

            PutAuthenticationFactorSettingResponse putResponse = identityDomainsClient.putAuthenticationFactorSetting(putRequest);

            response.put("success", true);
            response.put("updatedConfig", mfaConfig);
            response.put("message", "MFA认证因子设置更新成功");

            // 返回更新后的设置信息
            AuthenticationFactorSetting result = putResponse.getAuthenticationFactorSetting();
            Map<String, Object> settingInfo = new HashMap<>();
            settingInfo.put("id", result.getId());
            settingInfo.put("emailEnabled", result.getEmailEnabled());
            settingInfo.put("smsEnabled", result.getSmsEnabled());
            settingInfo.put("totpEnabled", result.getTotpEnabled());
            settingInfo.put("pushEnabled", result.getPushEnabled());
            settingInfo.put("fidoAuthenticatorEnabled", result.getFidoAuthenticatorEnabled());
            settingInfo.put("securityQuestionsEnabled", result.getSecurityQuestionsEnabled());
            settingInfo.put("phoneCallEnabled", result.getPhoneCallEnabled());
            response.put("updatedSetting", settingInfo);

            log.info("租户 [{}] MFA设置 已更新: {}", tenant.getTenancyName(), mfaConfig);

        } catch (Exception e) {
            log.error("更新MFA设置失败: {}", e.getMessage(), e);
            response.put("message", "更新MFA设置失败: " + e.getMessage());
        }

        return response;
    }
}
