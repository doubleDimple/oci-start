package com.doubledimple.ociserver.controller;

import cn.dev33.satoken.stp.StpUtil;
import com.doubledimple.ociserver.pojo.request.GithubConfig;
import com.doubledimple.ociserver.pojo.request.TaskConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.pojo.request.ProxyConfig;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.DingTalkConfig;
import com.doubledimple.ociserver.pojo.request.FeishuConfig;
import com.doubledimple.ociserver.pojo.request.GoogleConfig;
import com.doubledimple.ociserver.pojo.request.MfaConfig;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfigRequest;
import com.doubledimple.ociserver.pojo.request.CloudflareConfigRequest;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfigRequest;
import com.doubledimple.ociserver.pojo.request.FeishuConfigRequest;
import com.doubledimple.ociserver.pojo.request.GoogleConfigRequest;
import com.doubledimple.ociserver.pojo.request.MfaConfigRequest;
import com.doubledimple.ociserver.pojo.request.ProxyConfigRequest;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.pojo.request.BarkConfigRequest;
import com.doubledimple.ociserver.pojo.request.DingTalkConfigRequest;
import com.doubledimple.ociserver.pojo.request.GithubConfigRequest;
import com.doubledimple.ociserver.pojo.request.IpCheckConfigRequest;
import com.doubledimple.ociserver.pojo.request.PasswordUpdateRequest;
import com.doubledimple.ociserver.pojo.request.TaskConfigRequest;
import com.doubledimple.ociserver.pojo.request.TelegramConfigRequest;
import com.doubledimple.ociserver.pojo.request.TurnstileConfigRequest;
import com.doubledimple.ociserver.config.context.UserContext;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.impl.system.ApiTokenManagementService;
import com.doubledimple.ociserver.third.dns.CloudflareService;
import com.doubledimple.ociserver.utils.EdgeUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.net.URI;
import java.net.URISyntaxException;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName SystemSettingsApiController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 12:55
 */
import com.doubledimple.ociserver.config.annotations.AuditLog;

@RestController
@RequestMapping("/api/system")
@Slf4j
@AuditLog(title = "系统安全设置")
public class SystemSettingsApiController  extends BaseController{

    @Resource
    private LoginUserService loginUserService;

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private ApiTokenManagementService apiTokenManagementService;

    @Resource
    private CloudflareService cloudflareService;

    @PostMapping("/updatePassword")
    public ResponseEntity<?> updatePassword(@RequestBody PasswordUpdateRequest request, HttpServletRequest httpServletRequest) {
        guardSecurityWrite(httpServletRequest);
        boolean changed;
        String oldLoginId = StpUtil.getLoginIdAsString();
        try {
            // The transactional service commits before revoking the previous username's sessions.
            changed = loginUserService.updatePassword(request, httpServletRequest);
        } catch (LoginUserService.AccountValidationException e) {
            Map<String, Object> failure = new HashMap<>();
            failure.put("success", false);
            failure.put("errorKey", e.getErrorKey());
            failure.put("writeAttempted", false);
            failure.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(failure);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("账号更新未确认完成，请重新登录后确认");
        }
        if (changed) {
            try {
                StpUtil.logout(oldLoginId);
            } catch (Exception e) {
                // The database has already committed. Do not claim that the account update rolled back.
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body("账号已更新，但旧会话撤销未确认完成，请重新登录");
            }
        }
        Map<String, Object> data = new HashMap<>();
        data.put("needRelogin", changed);
        return ResponseEntity.ok(successBody(data));
    }

    /**
     * 聚合返回通知渠道配置（Mac / 原生客户端加载表单用）
     */
    @GetMapping("/notifyConfigs")
    public ResponseEntity<?> notifyConfigs(@RequestParam(defaultValue = "false") boolean redacted,
                                           HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        if (redacted) guardSecurityWrite(httpRequest);
        try {
            Map<String, Object> data = new HashMap<>();
            if (redacted) {
                TaskConfig task = systemConfigService.getTaskConfig();
                Map<String, Object> safeTask = new HashMap<>();
                safeTask.put("enabled", task.isEnabled());
                safeTask.put("executeHour", task.getExecuteHour());
                safeTask.put("enableAccountCheck", task.isEnableAccountCheck());
                safeTask.put("enableBootLog", task.isEnableBootLog());
                safeTask.put("enableCostCheck", task.isEnableCostCheck());
                safeTask.put("hasNotificationSecret", hasStoredNotificationSecret(task.getNotificationSecret()));
                data.put("task", safeTask);

                TelegramConfig telegram = systemConfigService.getTelegramConfig();
                Map<String, Object> safeTelegram = new HashMap<>();
                safeTelegram.put("enabled", telegram.isEnabled());
                safeTelegram.put("chatId", telegram.getChatId());
                safeTelegram.put("chatName", telegram.getChatName());
                safeTelegram.put("hasBotToken", hasStoredNotificationSecret(telegram.getBotToken()));
                data.put("telegram", safeTelegram);

                ProxyConfig proxy = systemConfigService.getProxyConfig();
                Map<String, Object> safeProxy = new HashMap<>();
                safeProxy.put("enabled", proxy.isEnabled());
                safeProxy.put("type", proxy.getType());
                safeProxy.put("host", proxy.getHost());
                safeProxy.put("port", proxy.getPort());
                safeProxy.put("username", proxy.getUsername());
                safeProxy.put("hasPassword", hasStoredNotificationSecret(proxy.getPassword()));
                data.put("proxy", safeProxy);

                BarkConfig bark = systemConfigService.getBarkConfig();
                Map<String, Object> safeBark = new HashMap<>();
                safeBark.put("enabled", bark.isEnabled());
                safeBark.put("url", bark.getUrl());
                safeBark.put("hasDeviceKey", hasStoredNotificationSecret(bark.getDeviceKey()));
                data.put("bark", safeBark);

                DingTalkConfig dingTalk = systemConfigService.getDingTalkConfig();
                Map<String, Object> safeDingTalk = new HashMap<>();
                safeDingTalk.put("enabled", dingTalk.isEnabled());
                safeDingTalk.put("hasWebhook", hasStoredNotificationSecret(dingTalk.getWebhook()));
                safeDingTalk.put("hasSecret", hasStoredNotificationSecret(dingTalk.getSecret()));
                data.put("dingTalk", safeDingTalk);

                FeishuConfig feishu = systemConfigService.getFeishuConfig();
                Map<String, Object> safeFeishu = new HashMap<>();
                safeFeishu.put("enabled", feishu.isEnabled());
                safeFeishu.put("hasWebhook", hasStoredNotificationSecret(feishu.getWebhook()));
                safeFeishu.put("hasSecret", hasStoredNotificationSecret(feishu.getSecret()));
                data.put("feishu", safeFeishu);
                data.put("serverTimeZone", ZoneId.systemDefault().toString());
            } else {
                // Preserve the full existing native-client response; Vue explicitly opts into redaction.
                data.put("task", systemConfigService.getTaskConfig());
                data.put("telegram", systemConfigService.getTelegramConfig());
                data.put("proxy", systemConfigService.getProxyConfig());
                data.put("dingTalk", systemConfigService.getDingTalkConfig());
                data.put("bark", systemConfigService.getBarkConfig());
                data.put("feishu", systemConfigService.getFeishuConfig());
            }
            Map<String, Object> body = new HashMap<>();
            body.put("success", true);
            body.put("data", data);
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("通知配置读取失败");
        }
    }

    @PostMapping("/updateTelegramConfig")
    public ResponseEntity<?> updateTelegramConfig(@RequestBody TelegramConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateTelegramConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Telegram 配置保存失败，请重新读取确认");
        }
    }

    @PostMapping("/updateGithubConfig")
    public ResponseEntity<?> updateGithubConfig(@RequestBody GithubConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateGithubConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("GitHub 配置保存失败，请检查必填字段并重新读取确认");
        }
    }

    /**
     * 更新 Google OAuth 配置
     */
    @PostMapping("/updateGoogleConfig")
    public ResponseEntity<?> updateGoogleConfig(@RequestBody GoogleConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateGoogleConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Google 配置保存失败，请检查必填字段并重新读取确认");
        }
    }

    @PostMapping("/updateDingTalkConfig")
    public ResponseEntity<?> updateDingTalkConfig(@RequestBody DingTalkConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateDingTalkConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("钉钉配置保存失败，请重新读取确认");
        }
    }

    /**
     * @Description: 测试钉钉消息发送
     * @Param: []
     * @return: org.springframework.http.ResponseEntity<java.lang.Void>
     * @Author: doubleDimple
     * @Date: 12/14/24 4:10 PM
     */
    @PostMapping("/testDingTalk")
    public ResponseEntity<?> testDingTalk(HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.sendDingTalkMessage("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("通知测试未取得服务商成功回执，请核对接收端后再决定是否重试");
        }
    }

    /**
    * @Description: 测试tg消息发送
    * @Param: []
    * @return: org.springframework.http.ResponseEntity<java.lang.Void>
    * @Author: doubleDimple
    * @Date: 12/14/24 4:10 PM
    */
    @PostMapping("/testTgTalk")
    public ResponseEntity<?> testTgTalk(HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.testTgTalk("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("通知测试未取得服务商成功回执，请核对接收端后再决定是否重试");
        }
    }


    /**
    * @Description: 通知定时任务,账号测活,抢机统计
    * @Param: [int]
    * @return: org.springframework.http.ResponseEntity<java.lang.String>
    * @Author doubleDimple
    * @Date: 1/3/25 9:05 PM
    */
    @PostMapping("/updateTaskConfig")
    public ResponseEntity<?> updateTaskConfig(@RequestBody TaskConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateTaskConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("通知任务配置保存失败，请检查执行小时并重新读取确认");
        }
    }

    /**
     * 聚合返回 IP 质量检测配置（Mac / 原生客户端加载表单用）
     */
    @GetMapping("/ipSettingsConfigs")
    public ResponseEntity<?> ipSettingsConfigs() {
        try {
            Map<String, Object> data = new HashMap<>();
            data.put("ipCheck", systemConfigService.getIpCheckConfig());
            data.put("telecom", systemConfigService.getVPSConfig("telecom"));
            data.put("unicom", systemConfigService.getVPSConfig("unicom"));
            data.put("mobile", systemConfigService.getVPSConfig("mobile"));
            Map<String, Object> body = new HashMap<>();
            body.put("success", true);
            body.put("data", data);
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            log.error("获取 IP 质量检测配置失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(e.getMessage());
        }
    }

    /**
     * 聚合返回安全管理页配置（Mac / 原生客户端加载表单用，对齐 /system/settings）
     */
    @GetMapping("/securitySettingsConfigs")
    public ResponseEntity<?> securitySettingsConfigs(@RequestParam(defaultValue = "false") boolean redacted,
                                                     HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        if (redacted) guardSecurityWrite(httpRequest);
        try {
            Map<String, Object> data = new HashMap<>();
            data.put("currentUsername", UserContext.getUsername());
            data.put("siteLogoName", systemConfigService.getSiteLogoName());
            if (redacted) {
                GithubConfig github = systemConfigService.getGithubConfig();
                Map<String, Object> safeGithub = new HashMap<>();
                safeGithub.put("enabled", github.isEnabled());
                safeGithub.put("userName", github.getUserName());
                safeGithub.put("githubId", github.getGithubId());
                safeGithub.put("clientId", github.getClientId());
                safeGithub.put("redirectUri", github.getRedirectUri());
                safeGithub.put("hasClientSecret", hasSecret(github.getClientSecret()));
                data.put("github", safeGithub);

                GoogleConfig google = systemConfigService.getGoogleConfig();
                Map<String, Object> safeGoogle = new HashMap<>();
                safeGoogle.put("enabled", google.isEnabled());
                safeGoogle.put("email", google.getEmail());
                safeGoogle.put("clientId", google.getClientId());
                safeGoogle.put("redirectUri", google.getRedirectUri());
                safeGoogle.put("hasClientSecret", hasSecret(google.getClientSecret()));
                data.put("google", safeGoogle);

                MfaConfig mfa = systemConfigService.getMfaConfig();
                Map<String, Object> safeMfa = new HashMap<>();
                safeMfa.put("enabled", mfa.isEnabled());
                safeMfa.put("issuer", mfa.getIssuer());
                safeMfa.put("hasSecretKey", hasSecret(mfa.getSecretKey()));
                data.put("mfa", safeMfa);

                TurnstileConfig turnstile = systemConfigService.getTurnstileConfig();
                Map<String, Object> safeTurnstile = new HashMap<>();
                safeTurnstile.put("enabled", turnstile.isEnabled());
                safeTurnstile.put("siteKey", turnstile.getSiteKey());
                safeTurnstile.put("hasSecretKey", hasSecret(turnstile.getSecretKey()));
                data.put("turnstile", safeTurnstile);
            } else {
                // Keep the existing native-client response shape; only the Vue opt-in is redacted.
                data.put("github", systemConfigService.getGithubConfig());
                data.put("google", systemConfigService.getGoogleConfig());
                data.put("mfa", systemConfigService.getMfaConfig());
                data.put("turnstile", systemConfigService.getTurnstileConfig());
            }
            data.put("channelNotifyEnabled", systemConfigService.getChannelNotifyEnabled());
            Map<String, Object> body = new HashMap<>();
            body.put("success", true);
            body.put("data", data);
            return ResponseEntity.ok().header("Cache-Control", "no-store").body(body);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .header("Cache-Control", "no-store").body("无法读取安全管理配置");
        }
    }

    @GetMapping("/mfaMaterial")
    public ResponseEntity<?> mfaMaterial(HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(httpRequest);
        try {
            MfaConfig mfa = systemConfigService.getMfaConfig();
            Map<String, Object> data = new HashMap<>();
            data.put("secretKey", hasSecret(mfa.getSecretKey()) ? mfa.getSecretKey() : null);
            data.put("qrCode", hasSecret(mfa.getQrCode()) ? mfa.getQrCode() : null);
            return ResponseEntity.ok().header("Cache-Control", "no-store").body(successBody(data));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .header("Cache-Control", "no-store").body("无法读取 MFA 配置");
        }
    }

    @GetMapping("/settings/logo")
    public ResponseEntity<?> logoName() {
        try {
            Map<String, Object> data = new HashMap<>();
            data.put("logoName", systemConfigService.getSiteLogoName());
            return ResponseEntity.ok().header("Cache-Control", "no-store").body(successBody(data));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("无法读取品牌名称");
        }
    }

    /**
    * ip质量检测的开关
    */
    @PostMapping("/updateIpCheckConfig")
    public ResponseEntity<?> updateIpCheckConfig(@RequestBody IpCheckConfigRequest request) {
        try {
            systemConfigService.updateIpCheckConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateBarkConfig")
    public ResponseEntity<?> updateBarkConfig(@RequestBody BarkConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateBarkConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Bark 配置保存失败，请重新读取确认");
        }
    }

    @PostMapping("/testBark")
    public ResponseEntity<?> testBark(HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.testBark("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("通知测试未取得服务商成功回执，请核对接收端后再决定是否重试");
        }
    }

    /**
     * 聚合返回域名服务商密钥配置（Mac / 原生客户端加载表单用）
     */
    @GetMapping("/domainProviderConfigs")
    public ResponseEntity<?> domainProviderConfigs() {
        try {
            Map<String, Object> data = new HashMap<>();
            data.put("cloudflare", systemConfigService.getCloudflareConfig());
            data.put("edgeOne", systemConfigService.getEdgeOneConfig());
            Map<String, Object> body = new HashMap<>();
            body.put("success", true);
            body.put("data", data);
            return ResponseEntity.ok(body);
        } catch (Exception e) {
            log.error("获取域名服务商配置失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(e.getMessage());
        }
    }

    @PostMapping("/updateCloudflareConfig")
    public ResponseEntity<?> updateCloudflareConfig(@RequestBody CloudflareConfigRequest request) {
        try {
            systemConfigService.updateCloudflareConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新Cloudflare配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/testCloudflareConnection")
    public ResponseEntity<?> testCloudflareConnection(@RequestBody CloudflareConfigRequest request) {
        try {
            Map<String, Object> result = cloudflareService.testCloudflareConnection(request);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("测试Cloudflare连接失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateEdgeOneConfig")
    public ResponseEntity<?> updateEdgeOneConfig(@RequestBody EdgeOneConfigRequest request) {
        try {
            systemConfigService.updateEdgeOneConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新腾讯云EdgeOne配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/testEdgeOneConnection")
    public ResponseEntity<?> testEdgeOneConnection(@RequestBody EdgeOneConfigRequest request) {
        try {
            Map<String, Object> result = EdgeUtils.testEdgeOneConnection(request);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("测试腾讯云EdgeOne连接失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateMfaConfig")
    public ResponseEntity<?> updateMfaConfig(@RequestBody MfaConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateMfaConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("MFA 配置保存失败，请重新读取确认");
        }
    }

    @PostMapping("/regenerateMfaSecret")
    public ResponseEntity<?> regenerateMfaSecret(HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.regenerateMfaSecret();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("MFA 密钥重生未确认完成，请重新读取确认");
        }
    }

    @DeleteMapping("/deleteMfaConfig")
    public ResponseEntity<?> deleteMfaConfig(HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.deleteMfaConfig();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("MFA 配置删除未确认完成，请重新读取确认");
        }
    }

    @PostMapping("/updateFeishuConfig")
    public ResponseEntity<?> updateFeishuConfig(@RequestBody FeishuConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateFeishuConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("飞书配置保存失败，请重新读取确认");
        }
    }

    @PostMapping("/testFeishu")
    public ResponseEntity<?> testFeishu(HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.sendFeishuMessage("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("通知测试未取得服务商成功回执，请核对接收端后再决定是否重试");
        }
    }

    @PostMapping("/updateProxyConfig")
    public ResponseEntity<?> updateProxyConfig(@RequestBody ProxyConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateProxyConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("通知代理配置保存失败，请重新读取确认");
        }
    }

    @PostMapping("/testProxyConnection")
    public ResponseEntity<?> testProxyConnection(@RequestBody ProxyConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            boolean success = systemConfigService.testProxyConnection(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", success);
            response.put("message", success ? "TCP 端口连接已建立，未验证代理协议或认证" : "本次 TCP 端口连接未建立");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("端口检测未完成");
        }
    }

    /**
     * 生成新的API Token
     */
    @PostMapping("/generateApiToken")
    public ResponseEntity<?> generateApiToken(@RequestBody Map<String, Object> body,
            @RequestHeader(value = "If-Match", required = false) String revision,
            HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(httpRequest);
        try {
            if (body == null || !(body.get("tokenName") instanceof String)
                    || !(body.get("expirationDays") instanceof Integer)
                    || body.get("description") != null && !(body.get("description") instanceof String)) {
                throw new ApiTokenManagementService.TokenFailure("invalidInput", false);
            }
            ApiTokenConfigRequest request = new ApiTokenConfigRequest();
            request.setTokenName((String) body.get("tokenName"));
            request.setExpirationDays((Integer) body.get("expirationDays"));
            request.setDescription((String) body.get("description"));
            return apiTokenSuccess(apiTokenManagementService.generate(request, revision));
        } catch (ApiTokenManagementService.TokenFailure failure) {
            return apiTokenFailure(failure.getErrorKey(), failure.isWriteAttempted());
        } catch (Exception e) {
            return apiTokenFailure("requestFailed", true);
        }
    }

    /**
     * 获取Token状态信息
     */
    @GetMapping("/apiTokenStatus")
    public ResponseEntity<?> getApiTokenStatus(HttpServletRequest request, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(request);
        try {
            return apiTokenSuccess(apiTokenManagementService.metadata());
        } catch (Exception e) {
            return apiTokenFailure("requestFailed", false);
        }
    }

    /**
     * 读取全局 API Token 元数据，不默认下发凭据。
     */
    @GetMapping("/apiTokenConfigs")
    public ResponseEntity<?> apiTokenConfigs(HttpServletRequest request, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(request);
        try {
            return apiTokenSuccess(apiTokenManagementService.metadata());
        } catch (Exception e) {
            return apiTokenFailure("requestFailed", false);
        }
    }

    @GetMapping("/apiTokenMaterial")
    public ResponseEntity<?> apiTokenMaterial(@RequestParam String revision, HttpServletRequest request, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(request);
        try { return apiTokenSuccess(apiTokenManagementService.material(revision)); }
        catch (ApiTokenManagementService.TokenFailure failure) { return apiTokenFailure(failure.getErrorKey(), false); }
        catch (Exception failure) { return apiTokenFailure("requestFailed", false); }
    }

    /**
     * 撤销API Token
     */
    @PostMapping("/revokeApiToken")
    public ResponseEntity<?> revokeApiToken(@RequestHeader(value = "If-Match", required = false) String revision,
            HttpServletRequest request, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(request);
        try {
            return apiTokenSuccess(apiTokenManagementService.revoke(revision));
        } catch (ApiTokenManagementService.TokenFailure failure) {
            return apiTokenFailure(failure.getErrorKey(), failure.isWriteAttempted());
        } catch (Exception e) {
            return apiTokenFailure("requestFailed", true);
        }
    }

    /**
     * 验证API Token
     */
    @PostMapping("/validateApiToken")
    public ResponseEntity<?> validateApiToken(@RequestBody Map<String, String> request,
            HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        guardSecurityWrite(httpRequest);
        try {
            String token = request.get("token");
            boolean isValid = systemConfigService.validateApiToken(token);

            Map<String, Object> response = new HashMap<>();
            response.put("valid", isValid);
            response.put("message", isValid ? "Token有效" : "Token无效或已过期");

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return apiTokenFailure("requestFailed", false);
        }
    }

    private static ResponseEntity<Map<String, Object>> apiTokenSuccess(Object data) {
        Map<String, Object> body = new HashMap<>();
        body.put("success", true); body.put("data", data);
        return ResponseEntity.ok().header("Cache-Control", "no-store").body(body);
    }

    private static ResponseEntity<Map<String, Object>> apiTokenFailure(String errorKey, boolean attempted) {
        Map<String, Object> body = new HashMap<>();
        body.put("success", false); body.put("errorKey", errorKey); body.put("writeAttempted", attempted);
        int status = "invalidInput".equals(errorKey) ? 400 : "notFound".equals(errorKey) ? 404 : "conflict".equals(errorKey) ? 409 : 500;
        return ResponseEntity.status(status).header("Cache-Control", "no-store").body(body);
    }

    @PostMapping("/updateChannelNotifyConfig")
    public ResponseEntity<?> updateChannelNotifyConfig(@RequestBody Map<String, Boolean> request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            Boolean enabled = request.get("enabled");
            if (enabled == null) {
                return ResponseEntity.badRequest().body("enabled参数不能为空");
            }
            systemConfigService.updateChannelNotifyConfig(enabled);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("频道通知配置保存失败，请重新读取确认");
        }
    }

    @PostMapping("/updateTurnstileConfig")
    public ResponseEntity<?> updateTurnstileConfig(@RequestBody TurnstileConfigRequest request, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateTurnstileConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Turnstile 配置保存失败，请检查必填字段并重新读取确认");
        }
    }

    @PostMapping("/settings/logo")
    public ResponseEntity<?> updateLogoName(@RequestParam String logoName, HttpServletRequest httpRequest) {
        guardSecurityWrite(httpRequest);
        try {
            systemConfigService.updateSiteLogoName(logoName);
            Map<String, Object> response = new HashMap<>();
            response.put("code", 200);
            response.put("msg", "success");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("品牌名称保存失败，名称应为 1–15 个字符，请重新读取确认");
        }
    }

    private static boolean hasSecret(String value) {
        return value != null && !value.trim().isEmpty();
    }

    private static boolean hasStoredNotificationSecret(String value) {
        return value != null && !value.isEmpty();
    }

    private static Map<String, Object> successBody(Object data) {
        Map<String, Object> body = new HashMap<>();
        body.put("success", true);
        body.put("data", data);
        return body;
    }

    static void guardSecurityWrite(HttpServletRequest request) {
        // Scoped settings writes/opt-in reads; authenticated native clients remain supported.
        String site = request.getHeader("Sec-Fetch-Site");
        if ("same-origin".equals(site)) return;
        if (site != null && !"none".equals(site)) throw forbiddenSecurityWrite();
        String origin = request.getHeader("Origin");
        if (origin == null) return;
        try {
            URI uri = new URI(origin);
            if (uri.getHost() == null || uri.getScheme() == null || uri.getRawUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null
                    || !"".equals(uri.getRawPath())) throw forbiddenSecurityWrite();
            int port = uri.getPort() < 0 ? ("https".equalsIgnoreCase(uri.getScheme()) ? 443 : 80) : uri.getPort();
            if (!uri.getScheme().equalsIgnoreCase(request.getScheme()) || port != request.getServerPort()
                    || !unbracketHost(uri.getHost()).equalsIgnoreCase(unbracketHost(request.getServerName()))) {
                throw forbiddenSecurityWrite();
            }
        } catch (URISyntaxException e) {
            throw forbiddenSecurityWrite();
        }
    }

    private static String unbracketHost(String host) {
        return host.startsWith("[") && host.endsWith("]") ? host.substring(1, host.length() - 1) : host;
    }

    private static ResponseStatusException forbiddenSecurityWrite() {
        return new ResponseStatusException(HttpStatus.FORBIDDEN, "只允许同源页面修改安全配置");
    }
}
