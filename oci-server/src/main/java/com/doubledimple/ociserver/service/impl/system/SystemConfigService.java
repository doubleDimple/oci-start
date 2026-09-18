package com.doubledimple.ociserver.service.impl.system;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.JschUtils;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfig;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfigRequest;
import com.doubledimple.ociserver.pojo.request.CloudflareConfig;
import com.doubledimple.ociserver.pojo.request.CloudflareConfigRequest;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfig;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfigRequest;
import com.doubledimple.ociserver.pojo.request.FeishuConfig;
import com.doubledimple.ociserver.pojo.request.FeishuConfigRequest;
import com.doubledimple.ociserver.pojo.request.GoogleConfig;
import com.doubledimple.ociserver.pojo.request.GoogleConfigRequest;
import com.doubledimple.ociserver.pojo.request.MfaConfig;
import com.doubledimple.ociserver.pojo.request.MfaConfigRequest;
import com.doubledimple.ociserver.pojo.request.ProxyConfig;
import com.doubledimple.ociserver.pojo.request.ProxyConfigRequest;
import com.doubledimple.ociserver.pojo.response.ApiTokenResponse;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.message.NotificationTestSender;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.BarkConfigRequest;
import com.doubledimple.ociserver.pojo.request.DingTalkConfig;
import com.doubledimple.ociserver.pojo.request.DingTalkConfigRequest;
import com.doubledimple.ociserver.pojo.request.GithubConfig;
import com.doubledimple.ociserver.pojo.request.GithubConfigRequest;
import com.doubledimple.ociserver.pojo.request.IpCheckConfig;
import com.doubledimple.ociserver.pojo.request.IpCheckConfigRequest;
import com.doubledimple.ociserver.pojo.request.TaskConfig;
import com.doubledimple.ociserver.pojo.request.TaskConfigRequest;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfigRequest;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.pojo.request.TurnstileConfigRequest;
import com.doubledimple.ociserver.pojo.request.VPSConfig;
import com.doubledimple.ociserver.pojo.request.VPSConfigRequest;
import com.doubledimple.ociserver.config.task.DynamicIpCheckTask;
import com.doubledimple.ociserver.service.mfa.QRCodeService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.security.MessageDigest;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName SystemConfigService
 * @Description TODO
 * @Author
 * @Date 2024-11-21 12:58
 */
@Service
@Transactional
@Slf4j
public class SystemConfigService {

    @Resource
    @Lazy
    private SystemConfigRepository systemConfigRepository;

    @Resource
    @Lazy
    private MessageFactory messageFactory;

    @Resource
    private NotificationTestSender notificationTestSender;

    @Resource
    @Lazy
    DynamicIpCheckTask dynamicIpCheckTask;

    @Resource
    @Lazy
    private QRCodeService qrCodeService;

    private static final String REMEMBER_ME_KEY_CONFIG = "security.remember.me.key";


    // Telegram配置相关
    public TelegramConfig getTelegramConfig() {
        TelegramConfig config = new TelegramConfig();

        Optional<SystemConfig> botToken = systemConfigRepository.findByKey("telegram.bot.token");
        Optional<SystemConfig> chatId = systemConfigRepository.findByKey("telegram.chat.id");
        Optional<SystemConfig> chatName = systemConfigRepository.findByKey("telegram.chat.chatName");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("telegram.enabled");

        config.setBotToken(botToken.map(SystemConfig::getValue).orElse(""));
        config.setChatId(chatId.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));
        config.setChatName(chatName.map(SystemConfig::getValue).orElse(""));

        return config;
    }

    public void updateTelegramConfig(TelegramConfigRequest request) {
        String token = Boolean.TRUE.equals(request.getKeepBotToken())
                ? getTelegramConfig().getBotToken() : request.getBotToken();
        if (request.isEnabled() && (StringUtils.isBlank(token) || StringUtils.isBlank(request.getChatId()))) {
            throw new IllegalArgumentException("启用 Telegram 需要完整配置");
        }
        if (!Boolean.TRUE.equals(request.getKeepBotToken())) saveOrUpdateConfig("telegram.bot.token", token);
        saveOrUpdateConfig("telegram.chat.id", request.getChatId());
        saveOrUpdateConfig("telegram.chat.chatName", request.getChatName());

        SystemConfig enabled = systemConfigRepository.findByKey("telegram.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("telegram.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    // GitHub配置相关
    public GithubConfig getGithubConfig() {
        GithubConfig config = new GithubConfig();

        Optional<SystemConfig> clientId = systemConfigRepository.findByKey("github.client.id");
        Optional<SystemConfig> clientSecret = systemConfigRepository.findByKey("github.client.secret");
        Optional<SystemConfig> redirectUri = systemConfigRepository.findByKey("github.redirect.uri");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("github.enabled");
        Optional<SystemConfig> userName = systemConfigRepository.findByKey("github.myself.userName");
        Optional<SystemConfig> githubId = systemConfigRepository.findByKey("github.myself.githubId");

        config.setClientId(clientId.map(SystemConfig::getValue).orElse(""));
        config.setClientSecret(clientSecret.map(SystemConfig::getValue).orElse(""));
        config.setRedirectUri(redirectUri.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));
        config.setUserName(userName.map(SystemConfig::getValue).orElse(""));
        config.setGithubId(githubId.map(SystemConfig::getValue).orElse(""));
        return config;
    }

    public void updateGithubConfig(GithubConfigRequest request) {
        String secret = Boolean.TRUE.equals(request.getKeepSecret())
                ? getGithubConfig().getClientSecret() : request.getClientSecret();
        if (request.isEnabled() && (StringUtils.isBlank(request.getGithubId())
                || StringUtils.isBlank(request.getClientId()) || StringUtils.isBlank(secret)
                || StringUtils.isBlank(request.getRedirectUri()))) {
            throw new IllegalArgumentException("启用 GitHub 时，用户 ID、Client ID、Client Secret 和回调地址不能为空");
        }
        saveOrUpdateConfig("github.client.id", request.getClientId());
        if (!Boolean.TRUE.equals(request.getKeepSecret())) {
            saveOrUpdateConfig("github.client.secret", secret);
        }
        saveOrUpdateConfig("github.redirect.uri", request.getRedirectUri());
        saveOrUpdateConfig("github.myself.githubId", request.getGithubId());
        saveOrUpdateConfig("github.myself.userName", request.getUserName());

        SystemConfig enabled = systemConfigRepository.findByKey("github.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("github.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    public void updateDingTalkConfig(DingTalkConfigRequest request) {
        DingTalkConfig current = getDingTalkConfig();
        String webhook = Boolean.TRUE.equals(request.getKeepWebhook()) ? current.getWebhook() : request.getWebhook();
        String secret = Boolean.TRUE.equals(request.getKeepSecret()) ? current.getSecret() : request.getSecret();
        if (request.isEnabled() && (StringUtils.isBlank(webhook) || StringUtils.isBlank(secret))) {
            throw new IllegalArgumentException("启用钉钉需要完整配置");
        }
        if (!Boolean.TRUE.equals(request.getKeepWebhook())) saveOrUpdateConfig("dingtalk.webhook", webhook);
        if (!Boolean.TRUE.equals(request.getKeepSecret())) saveOrUpdateConfig("dingtalk.secret", secret);

        SystemConfig enabled = systemConfigRepository.findByKey("dingtalk.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("dingtalk.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    // 通用配置保存方法
    private void saveOrUpdateConfig(String key, String value) {
        SystemConfig config = systemConfigRepository.findByKey(key)
                .orElse(new SystemConfig());
        config.setKey(key);
        config.setValue(value);
        systemConfigRepository.save(config);
    }

    private void saveOrUpdateConfig(String key, String value, boolean isEnabled) {
        SystemConfig config = systemConfigRepository.findByKey(key)
                .orElse(new SystemConfig());
        config.setKey(key);
        if (value != null) {
            config.setValue(value);
        }
        config.setEnabled(isEnabled);
        systemConfigRepository.save(config);
    }

    public DingTalkConfig getDingTalkConfig() {
        DingTalkConfig config = new DingTalkConfig();

        Optional<SystemConfig> webhook = systemConfigRepository.findByKey("dingtalk.webhook");
        Optional<SystemConfig> secret = systemConfigRepository.findByKey("dingtalk.secret");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("dingtalk.enabled");

        config.setWebhook(webhook.map(SystemConfig::getValue).orElse(""));
        config.setSecret(secret.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }

    public void sendDingTalkMessage(String s) {
        notificationTestSender.dingTalk(getDingTalkConfig(), s);
    }

    public void testTgTalk(String s) {
        notificationTestSender.telegram(getTelegramConfig(), s);
    }

    public TaskConfig getTaskConfig() {
        TaskConfig config = new TaskConfig();

        // 获取enabled状态
        SystemConfig enabled = systemConfigRepository.findByKey("task.enabled")
                .orElse(new SystemConfig());
        config.setEnabled(enabled.isEnabled());

        // 获取执行时间
        SystemConfig executeHour = systemConfigRepository.findByKey("task.execute.hour")
                .orElse(new SystemConfig());
        config.setExecuteHour(executeHour.getValue() != null ?
                Integer.parseInt(executeHour.getValue()) : 9);

        // 获取通知秘钥
        SystemConfig notificationSecret = systemConfigRepository.findByKey("task.notification.secret")
                .orElse(new SystemConfig());
        config.setNotificationSecret(notificationSecret.getValue());

        // ===== 账号测活任务开关 =====
        SystemConfig accountCheck = systemConfigRepository.findByKey("task.enable.account-check")
                .orElse(new SystemConfig());
        config.setEnableAccountCheck("1".equals(accountCheck.getValue()));

        // ===== 抢机日志任务开关 =====
        SystemConfig bootLog = systemConfigRepository.findByKey("task.enable.boot-log")
                .orElse(new SystemConfig());
        config.setEnableBootLog("1".equals(bootLog.getValue()));

        //===== 花费检测开关
        SystemConfig costCheck = systemConfigRepository.findByKey("task.enable.cost-check")
                .orElse(new SystemConfig());
        config.setEnableCostCheck("1".equals(costCheck.getValue()));

        return config;
    }

    public void updateTaskConfig(TaskConfigRequest request) {
        // 验证时间范围
        if (request.getExecuteHour() < 0 || request.getExecuteHour() > 23) {
            throw new IllegalArgumentException("执行时间必须在0-23之间");
        }
        if (Boolean.TRUE.equals(request.getKeepNotificationSecret()) && Boolean.TRUE.equals(request.getClearNotificationSecret())) {
            throw new IllegalArgumentException("不能同时保留和清除通知密钥");
        }

        // 保存enabled状态
        SystemConfig enabled = systemConfigRepository.findByKey("task.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("task.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);

        // 保存执行时间
        saveOrUpdateConfig("task.execute.hour", String.valueOf(request.getExecuteHour()));

        // 保存通知秘钥
        if (!Boolean.TRUE.equals(request.getKeepNotificationSecret())) {
            if (Boolean.TRUE.equals(request.getClearNotificationSecret())) {
                saveOrUpdateConfig("task.notification.secret", "");
            } else if (request.getNotificationSecret() != null && !request.getNotificationSecret().trim().isEmpty()) {
                saveOrUpdateConfig("task.notification.secret", request.getNotificationSecret().trim());
            }
        }
        //保存是否启用账号测活
        saveOrUpdateConfig("task.enable.account-check", request.isEnableAccountCheck() ? "1" : "0");

        //保存是否启用抢机日志统计
        saveOrUpdateConfig("task.enable.boot-log", request.isEnableBootLog() ? "1" : "0");

        //保存是否启用花费检测
        saveOrUpdateConfig("task.enable.cost-check", request.isEnableCostCheck() ? "1" : "0");
    }

    public void updateIpCheckConfig(IpCheckConfigRequest request) {
        // 验证检测间隔范围
        if (request.getCheckInterval() <= 0 || request.getCheckInterval() > 24) {
            throw new IllegalArgumentException("检测间隔必须在1-24之间");
        }

        // 保存enabled状态
        SystemConfig enabled = systemConfigRepository.findByKey("ipcheck.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("ipcheck.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);

        // 保存检测间隔
        saveOrUpdateConfig("ipcheck.interval", String.valueOf(request.getCheckInterval()));

        // 保存VPS登录信息
        saveOrUpdateConfig("ipcheck.vps.username", request.getVpsUsername());
        saveOrUpdateConfig("ipcheck.vps.password", request.getVpsPassword());
        saveOrUpdateConfig("ipcheck.ssh.port", String.valueOf(request.getSshPort()));

        // 如果有动态调度任务，更新它
        if (dynamicIpCheckTask != null) {
            dynamicIpCheckTask.updateCheckInterval(request.getCheckInterval(), request.isEnabled());
        }
    }

    public IpCheckConfig getIpCheckConfig() {
        IpCheckConfig config = new IpCheckConfig();

        // 获取启用状态
        SystemConfig enabledConfig = systemConfigRepository.findByKey("ipcheck.enabled")
                .orElse(new SystemConfig());
        config.setEnabled(enabledConfig.isEnabled());

        // 获取检测间隔
        SystemConfig intervalConfig = systemConfigRepository.findByKey("ipcheck.interval")
                .orElse(new SystemConfig());

        // 设置检测间隔，默认为6小时
        String intervalStr = intervalConfig.getValue();
        int interval = 6; // 默认值
        if (intervalStr != null && !intervalStr.isEmpty()) {
            try {
                interval = Integer.parseInt(intervalStr);
            } catch (NumberFormatException e) {
                log.warn("无法解析检测间隔值：{}", intervalStr);
            }
        }
        config.setCheckInterval(interval);

        // 获取VPS用户名
        SystemConfig usernameConfig = systemConfigRepository.findByKey("ipcheck.vps.username")
                .orElse(new SystemConfig());
        config.setVpsUsername(usernameConfig.getValue() != null ? usernameConfig.getValue() : "root");

        // 获取VPS密码
        SystemConfig passwordConfig = systemConfigRepository.findByKey("ipcheck.vps.password")
                .orElse(new SystemConfig());
        config.setVpsPassword(passwordConfig.getValue());

        // 获取SSH端口
        SystemConfig portConfig = systemConfigRepository.findByKey("ipcheck.ssh.port")
                .orElse(new SystemConfig());
        String portStr = portConfig.getValue();
        int port = 22; // 默认值
        if (portStr != null && !portStr.isEmpty()) {
            try {
                port = Integer.parseInt(portStr);
            } catch (NumberFormatException e) {
                log.warn("无法解析SSH端口值：{}", portStr);
            }
        }
        config.setSshPort(port);

        return config;
    }

    public VPSConfig getVPSConfig(String type) {
        VPSConfig config = new VPSConfig();
        String prefix = "vps." + type + ".";

        // 获取启用状态
        SystemConfig enabledConfig = systemConfigRepository.findByKey(prefix + "enabled")
                .orElse(new SystemConfig());
        config.setEnabled(enabledConfig.isEnabled());

        // 获取服务器IP
        SystemConfig ipConfig = systemConfigRepository.findByKey(prefix + "ip")
                .orElse(new SystemConfig());
        config.setServerIp(ipConfig.getValue());

        // 获取用户名
        SystemConfig usernameConfig = systemConfigRepository.findByKey(prefix + "username")
                .orElse(new SystemConfig());
        config.setUsername(usernameConfig.getValue() != null ? usernameConfig.getValue() : "root");

        // 获取密码
        SystemConfig passwordConfig = systemConfigRepository.findByKey(prefix + "password")
                .orElse(new SystemConfig());
        config.setPassword(passwordConfig.getValue());

        // 获取SSH端口
        SystemConfig portConfig = systemConfigRepository.findByKey(prefix + "ssh.port")
                .orElse(new SystemConfig());
        String portStr = portConfig.getValue();
        int port = 22; // 默认值
        if (portStr != null && !portStr.isEmpty()) {
            try {
                port = Integer.parseInt(portStr);
            } catch (NumberFormatException e) {
                log.warn("无法解析SSH端口值：{}", portStr);
            }
        }
        config.setSshPort(port);

        return config;
    }

    public void updateVPSConfig(VPSConfigRequest request) {
        String prefix = "vps." + request.getType() + ".";

        // 验证类型
        if (!Arrays.asList("telecom", "unicom", "mobile").contains(request.getType())) {
            throw new IllegalArgumentException("无效的VPS类型");
        }

        // 验证端口范围
        if (request.getSshPort() <= 0 || request.getSshPort() > 65535) {
            throw new IllegalArgumentException("SSH端口必须在1-65535之间");
        }

        // 如果启用，验证必填字段
        if (request.isEnabled()) {
            if (StringUtils.isEmpty(request.getServerIp())) {
                throw new IllegalArgumentException("服务器IP不能为空");
            }
            if (StringUtils.isEmpty(request.getUsername())) {
                throw new IllegalArgumentException("用户名不能为空");
            }
            if (StringUtils.isEmpty(request.getPassword())) {
                throw new IllegalArgumentException("密码不能为空");
            }
        }

        // 保存配置
        saveOrUpdateConfig(prefix + "enabled", null, request.isEnabled());
        saveOrUpdateConfig(prefix + "ip", request.getServerIp(), false);
        saveOrUpdateConfig(prefix + "username", request.getUsername(), false);
        saveOrUpdateConfig(prefix + "password", request.getPassword(), false);
        saveOrUpdateConfig(prefix + "ssh.port", String.valueOf(request.getSshPort()), false);
    }

    public boolean testSSHConnection(VPSConfigRequest request) {
        try {
            ScriptResult scriptResult = JschUtils.executeScriptJsch(request.getServerIp(), request.getUsername(), request.getPassword(),request.getSshPort(), "echo 'Hello, World!'");
            String error = scriptResult.getError();
            if (StringUtils.isNotBlank(error)){
                return false;
            }
            return true;
        } catch (Exception e) {
            log.error("SSH连接测试失败: {}", e.getMessage());
            return false;
        }
    }

    public BarkConfig getBarkConfig() {
        BarkConfig config = new BarkConfig();

        Optional<SystemConfig> url = systemConfigRepository.findByKey("bark.url");
        Optional<SystemConfig> deviceKey = systemConfigRepository.findByKey("bark.device.key");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("bark.enabled");

        config.setUrl(url.map(SystemConfig::getValue).orElse(""));
        config.setDeviceKey(deviceKey.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }

    public void updateBarkConfig(BarkConfigRequest request) {
        String key = Boolean.TRUE.equals(request.getKeepDeviceKey()) ? getBarkConfig().getDeviceKey() : request.getDeviceKey();
        if (request.isEnabled() && (StringUtils.isBlank(request.getUrl()) || StringUtils.isBlank(key))) {
            throw new IllegalArgumentException("启用 Bark 需要完整配置");
        }
        saveOrUpdateConfig("bark.url", request.getUrl());
        if (!Boolean.TRUE.equals(request.getKeepDeviceKey())) saveOrUpdateConfig("bark.device.key", key);

        SystemConfig enabled = systemConfigRepository.findByKey("bark.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("bark.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    public void testBark(String message) {
        notificationTestSender.bark(getBarkConfig(), message);
    }

    public CloudflareConfig getCloudflareConfig() {
        CloudflareConfig config = new CloudflareConfig();

        Optional<SystemConfig> apiToken = systemConfigRepository.findByKey("cloudflare.api.token");
        Optional<SystemConfig> zoneId = systemConfigRepository.findByKey("cloudflare.zone.id");
        Optional<SystemConfig> email = systemConfigRepository.findByKey("cloudflare.email");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("cloudflare.enabled");

        config.setApiToken(apiToken.map(SystemConfig::getValue).orElse(""));
        config.setZoneId(zoneId.map(SystemConfig::getValue).orElse(""));
        config.setEmail(email.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }

    public void updateCloudflareConfig(CloudflareConfigRequest request) {
        // 验证必填项
        if (request.isEnabled() && StringUtils.isEmpty(request.getApiToken())) {
            throw new IllegalArgumentException("启用Cloudflare时API Token为必填项");
        }

        // 保存配置
        saveOrUpdateConfig("cloudflare.api.token", request.getApiToken());
        saveOrUpdateConfig("cloudflare.zone.id", request.getZoneId());
        saveOrUpdateConfig("cloudflare.email", request.getEmail());

        SystemConfig enabled = systemConfigRepository.findByKey("cloudflare.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("cloudflare.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    public EdgeOneConfig getEdgeOneConfig() {
        EdgeOneConfig config = new EdgeOneConfig();

        Optional<SystemConfig> secretId = systemConfigRepository.findByKey("edgeone.secret.id");
        Optional<SystemConfig> secretKey = systemConfigRepository.findByKey("edgeone.secret.key");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("edgeone.enabled");
        Optional<SystemConfig> region = systemConfigRepository.findByKey("edgeone.secret.region");

        config.setSecretId(secretId.map(SystemConfig::getValue).orElse(""));
        config.setSecretKey(secretKey.map(SystemConfig::getValue).orElse(""));
        config.setRegion(region.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }

    public void updateEdgeOneConfig(EdgeOneConfigRequest request) {
        // 验证必填项
        if (request.isEnabled()) {
            if (StringUtils.isEmpty(request.getSecretId())) {
                throw new IllegalArgumentException("启用腾讯云EdgeOne时SecretId为必填项");
            }
            if (StringUtils.isEmpty(request.getSecretKey())) {
                throw new IllegalArgumentException("启用腾讯云EdgeOne时SecretKey为必填项");
            }
        }

        // 保存配置
        saveOrUpdateConfig("edgeone.secret.id", request.getSecretId());
        saveOrUpdateConfig("edgeone.secret.key", request.getSecretKey());
        saveOrUpdateConfig("edgeone.secret.region", request.getRegion());

        SystemConfig enabled = systemConfigRepository.findByKey("edgeone.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("edgeone.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }



    public MfaConfig getMfaConfig() {
        MfaConfig config = new MfaConfig();

        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("mfa.enabled");
        Optional<SystemConfig> issuer = systemConfigRepository.findByKey("mfa.issuer");
        Optional<SystemConfig> secretKey = systemConfigRepository.findByKey("mfa.secret.key");
        Optional<SystemConfig> qrCode = systemConfigRepository.findByKey("mfa.qr.code");

        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));
        config.setIssuer(issuer.map(SystemConfig::getValue).orElse("OCI-Start Verify"));
        config.setSecretKey(secretKey.map(SystemConfig::getValue).orElse(null));
        config.setQrCode(qrCode.map(SystemConfig::getValue).orElse(null));

        return config;
    }

    public void updateMfaConfig(MfaConfigRequest request) {
        MfaConfig mfaConfig = getMfaConfig();
        String issuer = normalizeMfaIssuer(request.getIssuer());
        saveOrUpdateConfig("mfa.issuer", issuer);
        if (StringUtils.isNotBlank(mfaConfig.getSecretKey())) {
            // Changing the label must never invalidate already enrolled authenticators.
            if (!issuer.equals(mfaConfig.getIssuer()) || StringUtils.isBlank(mfaConfig.getQrCode())) {
                saveOrUpdateConfig("mfa.qr.code", generateMfaQr(issuer, mfaConfig.getSecretKey()));
            }
        } else if (request.isEnabled()) {
            generateMfaSecretAndQR(issuer);
        }

        // 保存启用状态
        SystemConfig enabled = systemConfigRepository.findByKey("mfa.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("mfa.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    public void regenerateMfaSecret() {
        // 获取当前配置
        MfaConfig config = getMfaConfig();
        /*if (!config.isEnabled()) {
            throw new IllegalStateException("MFA未启用");
        }*/

        // 重新生成密钥和二维码
        generateMfaSecretAndQR(config.getIssuer());
    }

    private void generateMfaSecretAndQR(String issuer) {
        String secretKey = generateRandomSecretKey();
        String qrCodeBase64 = generateMfaQr(normalizeMfaIssuer(issuer), secretKey);
        saveOrUpdateConfig("mfa.secret.key", secretKey);
        saveOrUpdateConfig("mfa.qr.code", qrCodeBase64);
    }

    private String normalizeMfaIssuer(String issuer) {
        return StringUtils.isBlank(issuer) ? "OCI-Start Verify" : issuer.trim();
    }

    private String generateMfaQr(String issuer, String secretKey) {
        try {
            String label = URLEncoder.encode(issuer + ":admin", StandardCharsets.UTF_8.name()).replace("+", "%20");
            String encodedIssuer = URLEncoder.encode(issuer, StandardCharsets.UTF_8.name()).replace("+", "%20");
            String encodedSecret = URLEncoder.encode(secretKey, StandardCharsets.UTF_8.name()).replace("+", "%20");
            return qrCodeService.generateQRCodeImage("otpauth://totp/" + label
                    + "?secret=" + encodedSecret + "&issuer=" + encodedIssuer);
        } catch (Exception e) {
            // A QR exception may contain its input URI; never attach credential-bearing causes.
            log.error("生成MFA二维码失败");
            throw new RuntimeException("生成MFA配置失败");
        }
    }

    private String generateRandomSecretKey() {
        // 生成32位随机Base32密钥
        SecureRandom random = new SecureRandom();
        byte[] bytes = new byte[20]; // 160 bits
        random.nextBytes(bytes);
        return new org.apache.commons.codec.binary.Base32().encodeAsString(bytes);
    }


    @Transactional
    public void deleteMfaConfig() {
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("mfa.enabled");
        Optional<SystemConfig> issuer = systemConfigRepository.findByKey("mfa.issuer");
        Optional<SystemConfig> secretKey = systemConfigRepository.findByKey("mfa.secret.key");
        Optional<SystemConfig> qrCode = systemConfigRepository.findByKey("mfa.qr.code");

        enabled.ifPresent(systemConfig -> systemConfigRepository.delete(systemConfig));
        issuer.ifPresent(systemConfig -> systemConfigRepository.delete(systemConfig));
        secretKey.ifPresent(systemConfig -> systemConfigRepository.delete(systemConfig));
        qrCode.ifPresent(systemConfig -> systemConfigRepository.delete(systemConfig));
    }

    public FeishuConfig getFeishuConfig() {
        FeishuConfig config = new FeishuConfig();

        Optional<SystemConfig> webhook = systemConfigRepository.findByKey("feishu.webhook");
        Optional<SystemConfig> secret = systemConfigRepository.findByKey("feishu.secret");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("feishu.enabled");

        config.setWebhook(webhook.map(SystemConfig::getValue).orElse(""));
        config.setSecret(secret.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }

    public void updateFeishuConfig(FeishuConfigRequest request) {
        FeishuConfig current = getFeishuConfig();
        String webhook = Boolean.TRUE.equals(request.getKeepWebhook()) ? current.getWebhook() : request.getWebhook();
        if (request.isEnabled() && StringUtils.isBlank(webhook)) {
            throw new IllegalArgumentException("启用飞书需要 Webhook");
        }
        if (!Boolean.TRUE.equals(request.getKeepWebhook())) saveOrUpdateConfig("feishu.webhook", webhook);
        if (!Boolean.TRUE.equals(request.getKeepSecret())) saveOrUpdateConfig("feishu.secret", request.getSecret());

        SystemConfig enabled = systemConfigRepository.findByKey("feishu.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("feishu.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    public void sendFeishuMessage(String message) {
        notificationTestSender.feishu(getFeishuConfig(), message);
    }

    /**
     * 获取代理配置
     */
    public ProxyConfig getProxyConfig() {
        ProxyConfig config = new ProxyConfig();

        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("proxy.enabled");
        Optional<SystemConfig> type = systemConfigRepository.findByKey("proxy.type");
        Optional<SystemConfig> host = systemConfigRepository.findByKey("proxy.host");
        Optional<SystemConfig> port = systemConfigRepository.findByKey("proxy.port");
        Optional<SystemConfig> username = systemConfigRepository.findByKey("proxy.username");
        Optional<SystemConfig> password = systemConfigRepository.findByKey("proxy.password");

        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));
        config.setType(type.map(SystemConfig::getValue).orElse("HTTP"));
        config.setHost(host.map(SystemConfig::getValue).orElse("127.0.0.1"));
        config.setPort(port.map(SystemConfig::getValue)
                .map(Integer::parseInt).orElse(7890));
        config.setUsername(username.map(SystemConfig::getValue).orElse(""));
        config.setPassword(password.map(SystemConfig::getValue).orElse(""));

        return config;
    }

    /**
     * 更新代理配置
     */
    public void updateProxyConfig(ProxyConfigRequest request) {
        // 验证代理类型
        if (!Arrays.asList("HTTP", "SOCKS5").contains(request.getType())) {
            throw new IllegalArgumentException("不支持的代理类型");
        }

        // 验证端口范围
        if (request.getPort() <= 0 || request.getPort() > 65535) {
            throw new IllegalArgumentException("端口必须在1-65535之间");
        }

        // 如果启用代理，验证必填项
        if (request.isEnabled()) {
            if (StringUtils.isEmpty(request.getHost())) {
                throw new IllegalArgumentException("启用代理时，代理地址不能为空");
            }
        }

        // 保存配置
        SystemConfig enabled = systemConfigRepository.findByKey("proxy.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("proxy.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);

        saveOrUpdateConfig("proxy.type", request.getType());
        saveOrUpdateConfig("proxy.host", request.getHost());
        saveOrUpdateConfig("proxy.port", String.valueOf(request.getPort()));
        // username / password 可选,留空也存(代表清除认证)
        saveOrUpdateConfig("proxy.username", request.getUsername() == null ? "" : request.getUsername());
        if (!Boolean.TRUE.equals(request.getKeepPassword())) {
            saveOrUpdateConfig("proxy.password", request.getPassword() == null ? "" : request.getPassword());
        }

        log.info("代理配置已更新: enabled={}, type={}, host={}, port={}, hasAuth={}",
                request.isEnabled(), request.getType(), request.getHost(), request.getPort(),
                StringUtils.isNotEmpty(request.getUsername()));
    }

    /**
     * 测试代理连接
     */
    public boolean testProxyConnection(ProxyConfigRequest request) {
        if (StringUtils.isBlank(request.getHost()) || request.getPort() < 1 || request.getPort() > 65535) {
            return false;
        }
        try (java.net.Socket socket = new java.net.Socket()) {
            // Only TCP reachability, not proxy protocol, authentication or destination access.
            socket.connect(new java.net.InetSocketAddress(request.getHost(), request.getPort()), 5000);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 获取或生成 Remember Me 密钥
     */
    public String getOrCreateRememberMeKey() {
        Optional<SystemConfig> config = systemConfigRepository.findByKey(REMEMBER_ME_KEY_CONFIG);

        if (config.isPresent()) {
            return config.get().getValue();
        }

        // 生成新的安全密钥
        String newKey = generateSecureKey();

        // 保存到数据库
        saveOrUpdateConfig(REMEMBER_ME_KEY_CONFIG, newKey);

        log.info("Generated new Remember Me key and saved to database");
        return newKey;
    }

    /**
     * 生成安全的随机密钥
     */
    private String generateSecureKey() {
        SecureRandom random = new SecureRandom();
        byte[] keyBytes = new byte[32];
        random.nextBytes(keyBytes);

        // 转换为Base64字符串，确保密钥复杂度
        return Base64.getEncoder().encodeToString(keyBytes);
    }

    /**
     * 获取API Token配置
     */
    public ApiTokenConfig getApiTokenConfig() {
        return apiTokenConfigFrom(systemConfigRepository.findAllByKeyStartingWith("api.token."));
    }

    /** Decode one database snapshot, avoiding independently committed configuration reads. */
    public static ApiTokenConfig apiTokenConfigFrom(List<SystemConfig> rows) {
        ApiTokenConfig config = new ApiTokenConfig();
        Map<String, SystemConfig> values = new HashMap<>();
        for (SystemConfig row : rows) values.put(row.getKey(), row);
        Optional<SystemConfig> enabled = Optional.ofNullable(values.get("api.token.enabled"));
        Optional<SystemConfig> tokenName = Optional.ofNullable(values.get("api.token.name"));
        Optional<SystemConfig> tokenValue = Optional.ofNullable(values.get("api.token.value"));
        Optional<SystemConfig> expirationDays = Optional.ofNullable(values.get("api.token.expiration.days"));
        Optional<SystemConfig> description = Optional.ofNullable(values.get("api.token.description"));
        Optional<SystemConfig> createdAt = Optional.ofNullable(values.get("api.token.created.at"));
        Optional<SystemConfig> expiresAt = Optional.ofNullable(values.get("api.token.expires.at"));
        Optional<SystemConfig> allowSwagger = Optional.ofNullable(values.get("api.token.allow.swagger"));

        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));
        config.setTokenName(tokenName.map(SystemConfig::getValue).orElse(""));
        config.setTokenValue(tokenValue.map(SystemConfig::getValue).orElse(""));
        config.setExpirationDays(expirationDays.map(SystemConfig::getValue)
                .map(Integer::parseInt).orElse(30));
        config.setDescription(description.map(SystemConfig::getValue).orElse(""));
        config.setAllowSwaggerAccess(allowSwagger.map(SystemConfig::isEnabled).orElse(true));

        // 解析时间字段
        if (createdAt.isPresent() && StringUtils.isNotEmpty(createdAt.get().getValue())) {
            config.setCreatedAt(LocalDateTime.parse(createdAt.get().getValue()));
        }
        if (expiresAt.isPresent() && StringUtils.isNotEmpty(expiresAt.get().getValue())) {
            config.setExpiresAt(LocalDateTime.parse(expiresAt.get().getValue()));
        }

        return config;
    }

    /**
     * 更新API Token配置
     */
    public ApiTokenResponse updateApiTokenConfig(ApiTokenConfigRequest request) {
        // 验证Token名称
        if (request.isEnabled() && StringUtils.isEmpty(request.getTokenName())) {
            throw new IllegalArgumentException("Token名称不能为空");
        }

        // 验证过期天数
        if (request.getExpirationDays() <= 0 || request.getExpirationDays() > 365) {
            throw new IllegalArgumentException("过期天数必须在1-365之间");
        }

        // 确保密钥存在
        getOrCreateApiSecretKey();

        // 生成新的Token值
        String tokenValue = generateApiToken();
        LocalDateTime createdAt = LocalDateTime.now();
        LocalDateTime expiresAt = createdAt.plusDays(request.getExpirationDays());

        // 保存配置（保持原有逻辑）
        SystemConfig enabled = systemConfigRepository.findByKey("api.token.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("api.token.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);

        saveOrUpdateConfig("api.token.name", request.getTokenName());
        saveOrUpdateConfig("api.token.value", tokenValue);
        saveOrUpdateConfig("api.token.expiration.days", String.valueOf(request.getExpirationDays()));
        saveOrUpdateConfig("api.token.description", request.getDescription());
        saveOrUpdateConfig("api.token.created.at", createdAt.toString());
        saveOrUpdateConfig("api.token.expires.at", expiresAt.toString());

        SystemConfig allowSwagger = systemConfigRepository.findByKey("api.token.allow.swagger")
                .orElse(new SystemConfig());
        allowSwagger.setKey("api.token.allow.swagger");
        allowSwagger.setEnabled(request.isAllowSwaggerAccess());
        systemConfigRepository.save(allowSwagger);

        // 构建响应
        ApiTokenResponse response = new ApiTokenResponse();
        response.setTokenName(request.getTokenName());
        response.setTokenValue(tokenValue);
        response.setDescription(request.getDescription());
        response.setCreatedAt(createdAt);
        response.setExpiresAt(expiresAt);
        response.setEnabled(request.isEnabled());
        response.setAllowSwaggerAccess(request.isAllowSwaggerAccess());
        response.setDaysUntilExpiration(request.getExpirationDays());

        log.info("API Token配置已更新");

        return response;
    }

    /**
     * 验证API Token
     */
    public boolean validateApiToken(String token) {
        if (StringUtils.isEmpty(token) || token.length() > 1000 || !token.startsWith("oci-start_api_")) {
            return false;
        }

        try {
            ApiTokenConfig config = getApiTokenConfig();
            if (!config.isEnabled()) {
                return false;
            }

            if (StringUtils.isEmpty(config.getTokenValue()) || !MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8),
                    config.getTokenValue().getBytes(StandardCharsets.UTF_8))) {
                return false;
            }

            // 验证签名
            String tokenBody = token.substring(14); // 移除 "oci-start_api_"
            String[] parts = tokenBody.split("\\.", -1);
            if (parts.length != 2) {
                return false;
            }

            String payloadBase64 = parts[0];
            String providedSignature = parts[1];

            // 重新计算签名
            String secretKey = systemConfigRepository.findByKey("api.token.secret.key").map(SystemConfig::getValue).orElse("");
            if (StringUtils.isEmpty(secretKey)) return false;
            String payload = new String(Base64.getUrlDecoder().decode(payloadBase64), StandardCharsets.UTF_8);

            Mac mac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKeySpec = new SecretKeySpec(secretKey.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
            mac.init(secretKeySpec);

            byte[] expectedSignature = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            String expectedSignatureBase64 = Base64.getUrlEncoder().withoutPadding().encodeToString(expectedSignature);

            if (!MessageDigest.isEqual(expectedSignatureBase64.getBytes(StandardCharsets.US_ASCII),
                    providedSignature.getBytes(StandardCharsets.US_ASCII))) {
                return false;
            }

            // 检查配置过期时间
            if (config.getExpiresAt() == null || !config.getExpiresAt().atZone(java.time.ZoneId.systemDefault()).toInstant().isAfter(java.time.Instant.now())) {
                return false;
            }

            return true;

        } catch (Exception e) {
            log.warn("Token 验证失败");
            return false;
        }
    }

    /**
     * 撤销API Token
     */
    public void revokeApiToken() {
        SystemConfig enabled = systemConfigRepository.findByKey("api.token.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("api.token.enabled");
        enabled.setEnabled(false);
        systemConfigRepository.save(enabled);

        // 清空Token值
        saveOrUpdateConfig("api.token.value", "");

        log.info("API Token已撤销");
    }

    /**
     * 生成安全的API Token
     */
    private String generateApiToken() {
        try {
            // 生成随机部分
            SecureRandom secureRandom = new SecureRandom();
            byte[] randomBytes = new byte[24];
            secureRandom.nextBytes(randomBytes);
            String randomPart = Base64.getUrlEncoder().withoutPadding().encodeToString(randomBytes);

            // 时间戳
            long timestamp = System.currentTimeMillis();
            String payload = timestamp + ":" + randomPart;

            // HMAC 签名
            String secretKey = getOrCreateApiSecretKey();
            Mac mac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKeySpec = new SecretKeySpec(secretKey.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
            mac.init(secretKeySpec);

            byte[] signature = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            String signatureBase64 = Base64.getUrlEncoder().withoutPadding().encodeToString(signature);

            return "oci-start_api_" + Base64.getUrlEncoder().withoutPadding().encodeToString(payload.getBytes(StandardCharsets.UTF_8)) + "." + signatureBase64;

        } catch (Exception e) {
            log.error("生成 API Token 失败");
            throw new RuntimeException("Token 生成失败");
        }
    }


    /**
     * 获取Token状态信息
     */
    public Map<String, Object> getApiTokenStatus() {
        ApiTokenConfig config = getApiTokenConfig();
        Map<String, Object> status = new HashMap<>();

        status.put("enabled", config.isEnabled());
        status.put("tokenName", config.getTokenName());
        status.put("hasToken", !StringUtils.isEmpty(config.getTokenValue()));
        status.put("description", config.getDescription());
        status.put("allowSwaggerAccess", config.isAllowSwaggerAccess());

        if (config.getExpiresAt() != null) {
            status.put("expiresAt", config.getExpiresAt());
            status.put("isExpired", config.getExpiresAt().isBefore(LocalDateTime.now()));

            long daysUntilExpiration = java.time.temporal.ChronoUnit.DAYS.between(
                    LocalDateTime.now(), config.getExpiresAt());
            status.put("daysUntilExpiration", Math.max(0, daysUntilExpiration));
        }

        if (config.getCreatedAt() != null) {
            status.put("createdAt", config.getCreatedAt());
        }

        return status;
    }

    private String getOrCreateApiSecretKey() {
        // 从系统配置获取密钥
        Optional<SystemConfig> secretKeyConfig = systemConfigRepository.findByKey("api.token.secret.key");

        if (secretKeyConfig.isPresent() && StringUtils.isNotEmpty(secretKeyConfig.get().getValue())) {
            return secretKeyConfig.get().getValue();
        }

        // 如果没有密钥，生成新的并保存
        SecureRandom secureRandom = new SecureRandom();
        byte[] keyBytes = new byte[32]; // 256 bits
        secureRandom.nextBytes(keyBytes);
        String secretKey = Base64.getEncoder().encodeToString(keyBytes);

        // 保存密钥到配置
        saveOrUpdateConfig("api.token.secret.key", secretKey);

        log.info("生成新的 API Token 密钥");
        return secretKey;
    }

    public GoogleConfig getGoogleConfig() {
        GoogleConfig config = new GoogleConfig();

        Optional<SystemConfig> clientId = systemConfigRepository.findByKey("google.client.id");
        Optional<SystemConfig> email = systemConfigRepository.findByKey("google.client.email");
        Optional<SystemConfig> clientSecret = systemConfigRepository.findByKey("google.client.secret");
        Optional<SystemConfig> redirectUri = systemConfigRepository.findByKey("google.redirect.uri");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("google.enabled");

        config.setClientId(clientId.map(SystemConfig::getValue).orElse(""));
        config.setClientSecret(clientSecret.map(SystemConfig::getValue).orElse(""));
        config.setRedirectUri(redirectUri.map(SystemConfig::getValue).orElse(""));
        config.setEmail(email.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }

    public void updateGoogleConfig(GoogleConfigRequest request) {
        String secret = Boolean.TRUE.equals(request.getKeepSecret())
                ? getGoogleConfig().getClientSecret() : request.getClientSecret();
        if (request.isEnabled() && (StringUtils.isBlank(request.getEmail())
                || StringUtils.isBlank(request.getClientId()) || StringUtils.isBlank(secret)
                || StringUtils.isBlank(request.getRedirectUri()))) {
            throw new IllegalArgumentException("启用 Google 时，邮箱、Client ID、Client Secret 和回调地址不能为空");
        }
        saveOrUpdateConfig("google.client.id", request.getClientId());
        saveOrUpdateConfig("google.client.email", request.getEmail());
        if (!Boolean.TRUE.equals(request.getKeepSecret())) {
            saveOrUpdateConfig("google.client.secret", secret);
        }
        saveOrUpdateConfig("google.redirect.uri", request.getRedirectUri());
        SystemConfig enabled = systemConfigRepository.findByKey("google.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("google.enabled");
        enabled.setEnabled(request.isEnabled());
        if (enabled.getValue() == null) {
            enabled.setValue("true");
        }
        systemConfigRepository.save(enabled);
    }

    public String getSiteLogoName() {
        return systemConfigRepository.findByKey("system.site.logo")
                .map(SystemConfig::getValue)
                .orElse("OCI-START");
    }

    /**
     * 获取 Turnstile 配置
     */
    public TurnstileConfig getTurnstileConfig() {
        TurnstileConfig config = new TurnstileConfig();

        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("turnstile.enabled");
        Optional<SystemConfig> siteKey = systemConfigRepository.findByKey("turnstile.site.key");
        Optional<SystemConfig> secretKey = systemConfigRepository.findByKey("turnstile.secret.key");

        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));
        config.setSiteKey(siteKey.map(SystemConfig::getValue).orElse(""));
        config.setSecretKey(secretKey.map(SystemConfig::getValue).orElse(""));

        return config;
    }

    /**
     * 更新 Turnstile 配置
     */
    public void updateTurnstileConfig(TurnstileConfigRequest request) {
        String secret = Boolean.TRUE.equals(request.getKeepSecret())
                ? getTurnstileConfig().getSecretKey() : request.getSecretKey();
        if (request.isEnabled()) {
            if (StringUtils.isBlank(request.getSiteKey())) {
                throw new IllegalArgumentException("启用 Turnstile 时，Site Key 不能为空");
            }
            if (StringUtils.isBlank(secret)) {
                throw new IllegalArgumentException("启用 Turnstile 时，Secret Key 不能为空");
            }
        }

        saveOrUpdateConfig("turnstile.site.key", request.getSiteKey() != null ? request.getSiteKey() : "");
        if (!Boolean.TRUE.equals(request.getKeepSecret())) {
            saveOrUpdateConfig("turnstile.secret.key", secret != null ? secret : "");
        }

        SystemConfig enabled = systemConfigRepository.findByKey("turnstile.enabled")
                .orElse(new SystemConfig());
        enabled.setKey("turnstile.enabled");
        enabled.setEnabled(request.isEnabled());
        systemConfigRepository.save(enabled);
    }

    /**
     * 更新 Logo 名称配置
     */
    public void updateSiteLogoName(String logoName) {
        if (StringUtils.isBlank(logoName)) {
            throw new IllegalArgumentException("Logo名称不能为空");
        }
        if (logoName.trim().length() > 15) {
            throw new IllegalArgumentException("Logo名称过长");
        }
        saveOrUpdateConfig("system.site.logo", logoName.trim());
    }

    public boolean getChannelNotifyEnabled() {
        Optional<SystemConfig> config = systemConfigRepository.findByKey("channel.notify.enabled");
        return config.map(SystemConfig::isEnabled).orElse(true);
    }

    public void updateChannelNotifyConfig(boolean enabled) {
        SystemConfig config = systemConfigRepository.findByKey("channel.notify.enabled")
                .orElse(new SystemConfig());
        config.setKey("channel.notify.enabled");
        config.setEnabled(enabled);
        systemConfigRepository.save(config);
    }

    public void disTurnstile() {
        try {
            SystemConfig config = systemConfigRepository.findByKey("turnstile.enabled")
                    .orElse(new SystemConfig());
            config.setKey("turnstile.enabled");
            config.setEnabled(false);
            systemConfigRepository.save(config);
            log.warn("[LocalBypass] Turnstile 已被强制禁用（turnstile.local.bypass=true）");
        } catch (Exception e) {
            log.error("[LocalBypass] 禁用 Turnstile 失败: {}", e.getMessage());
        }
    }
}
