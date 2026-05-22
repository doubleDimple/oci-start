package com.doubledimple.ociserver.config.init;

import cn.hutool.crypto.digest.DigestUtil;
import cn.hutool.http.HttpRequest;
import cn.hutool.json.JSONUtil;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.AppVersionRepository;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.service.SystemKVStoreService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.net.NetworkInterface;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * @version 1.0.0
 * @ClassName Init
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-12 15:14
 */
@Component
@Slf4j
public class Init implements CommandLineRunner {

    public static String turnstileBypassToken = "";

    @Resource
    private AppVersionRepository versionRepository;

    @Resource
    private SystemKVStoreService systemKVStoreService;

    @Resource
    private SystemConfigRepository systemConfigRepository;

    /** 本地调试时设为 true，启动即强制禁用 Turnstile，无需手动改数据库 */
    @Value("${turnstile.local.bypass:false}")
    private boolean turnstileLocalBypass;

    //  CF Worker 域名
    @Value("${cf.worker.domain:https://oci-api-worker.lovele-cn.workers.dev}")
    private String cfDomain;

    // 定义存在本地 KV 里的 Token 的 Key
    private static final String DEVICE_TOKEN_KEY = "SYSTEM_DEVICE_API_TOKEN";

    @Value("${oci.version}")
    private String dockerVersion;

    @Value("${oci.ssh-version}")
    private String sshVersion;

    @Override
    public void run(String... args) throws Exception {
        //disableTurnstileIfLocalBypass();
        checkAppVersion();
        initDeviceRegistration();
        checkAndLogTurnstileBypass();
    }

    /**
     * 本地调试专用：当 turnstile.local.bypass=true 时，强制将 Turnstile 置为禁用状态。
     * 仅修改数据库标志位，不删除已配置的 siteKey / secretKey，重新部署生产环境后恢复正常。
     */
    private void disableTurnstileIfLocalBypass() {
        if (!turnstileLocalBypass) {
            return;
        }
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

    private void checkAppVersion() {
        try {
            AppVersion version = versionRepository.findFirstByOrderByIdAsc()
                    .orElseThrow(() -> new RuntimeException("未找到版本信息"));
            //库里更新的最新版本
            String latestVersion = version.getLatestVersion();
            //已经更新的最新版本
            String currentVersion = version.getCurrentVersion();
            //比对库里的最新版本和当前配置文件的最新版本是否一致,不一致则更新
            log.debug("获取到的配置文件版本:dockerVersion:{}", dockerVersion);
            log.debug("获取到的配置文件版本:sshVersion:{}", sshVersion);

            log.info("版本已更新到: {}", version.getCurrentVersion());
        } catch (RuntimeException e) {
            log.warn("未找到版本信息");
        }
    }

    /**
     * 设备注册核心逻辑
     */
    private void initDeviceRegistration() {
        try {
            // 1. 查本地有没有 Token
            String token = systemKVStoreService.getValue(DEVICE_TOKEN_KEY);
            if (StringUtils.isNotEmpty(token)) {
                log.debug("当前设备已注册，加载本地 Token 成功。");
                return;
            }
            // 2. 生成设备指纹 (MAC地址 + OS版本)
            String fingerprint = generateDeviceFingerprint();
            log.debug("当前设备指纹: {}", fingerprint);

            // 3. 封装请求体
            Map<String, String> bodyMap = new HashMap<>();
            bodyMap.put("fingerprint", fingerprint);

            String responseBody = HttpRequest.post(cfDomain + "/api/register")
                    .timeout(5000)
                    .header("Content-Type", "application/json")
                    .body(JSONUtil.toJsonStr(bodyMap))
                    .execute()
                    .body();

            // 5. 解析返回值并保存 Token
            if (StringUtils.isNotEmpty(responseBody)) {
                JSONObject jsonObject = JSON.parseObject(responseBody);
                if (jsonObject != null && jsonObject.getInteger("code") == 200) {
                    String newToken = jsonObject.getString("token");
                    systemKVStoreService.saveOrUpdate(DEVICE_TOKEN_KEY, newToken, "Device API Token");
                    log.debug("设备注册成功");
                } else {
                    log.error("设备注册失败: {}", responseBody);
                }
            }
        } catch (Exception e) {
            log.error("设备注册过程发生异常，请检查网络或 CF Worker 状态: {}", e.getMessage());
        }
    }

    /**
     * 获取设备硬件指纹 (这里以取物理网卡 MAC 地址 + 操作系统名为例，进行 MD5 哈希)
     */
    private String generateDeviceFingerprint() {
        StringBuilder macBuilder = new StringBuilder();
        try {
            Enumeration<NetworkInterface> networkInterfaces = NetworkInterface.getNetworkInterfaces();
            while (networkInterfaces.hasMoreElements()) {
                NetworkInterface ni = networkInterfaces.nextElement();
                byte[] hardwareAddress = ni.getHardwareAddress();
                if (hardwareAddress != null && !ni.isLoopback() && !ni.isVirtual() && ni.isUp()) {
                    for (int i = 0; i < hardwareAddress.length; i++) {
                        macBuilder.append(String.format("%02X%s", hardwareAddress[i], (i < hardwareAddress.length - 1) ? "-" : ""));
                    }
                    break;
                }
            }
        } catch (Exception e) {
            log.warn("无法获取 MAC 地址，将使用备用指纹生成策略");
        }
        String osName = System.getProperty("os.name");
        String userDir = System.getProperty("user.dir");
        String rawFingerprint = macBuilder.toString() + "-" + osName + "-" + userDir;
        return DigestUtil.md5Hex(rawFingerprint);
    }

    /**
     * 检查 Turnstile 状态，如果开启则生成急救 Token 并打印日志
     */
    private void checkAndLogTurnstileBypass() {
        try {
            // 从数据库查询 Turnstile 的配置状态 (请根据你实际的键名和实体类字段调整)
            SystemConfig config = systemConfigRepository.findByKey("turnstile.enabled").orElse(null);

            boolean isEnabled = config != null && config.isEnabled();

            if (isEnabled) {
                turnstileBypassToken = UUID.randomUUID().toString().replace("-", "").substring(0, 16);
                log.info("========================  安全提示 / SECURITY NOTICE  ========================");
                log.info("检测到系统已开启 Turnstile 人机验证。");
                log.info("Turnstile CAPTCHA verification is currently enabled.");
                log.info("--------------------------------------------------------------------------------");
                log.info("如果由于配置错误(如 SiteKey 填错)导致无法登录，你可以调用以下急救接口强制禁用：");
                log.info("If misconfiguration (e.g., wrong SiteKey) prevents login, use the emergency API below to disable it:");
                log.info("GET  /api/disTurnstile?token={}", turnstileBypassToken);
                log.info("--------------------------------------------------------------------------------");
                log.info("安全注意: 该 Token 仅本次启动有效，且使用一次后即失效！");
                log.info("WARNING: This Token is valid for the current startup only and expires after a single use!");
                log.info("================================================================================================");
            }
        } catch (Exception e) {
            log.error("检查 Turnstile 状态并生成 Bypass Token 时异常", e);
        }
    }
}
