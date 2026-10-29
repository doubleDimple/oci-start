package com.doubledimple.ociserver.config.init;

import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.AppVersionRepository;
import com.doubledimple.dao.repository.SystemConfigRepository;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
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
    private SystemConfigRepository systemConfigRepository;

    /** 本地调试时设为 true，启动即强制禁用 Turnstile，无需手动改数据库 */
    @Value("${turnstile.local.bypass:false}")
    private boolean turnstileLocalBypass;

    @Value("${oci.version}")
    private String dockerVersion;

    @Value("${oci.ssh-version}")
    private String sshVersion;

    @Override
    public void run(String... args) throws Exception {
        //disableTurnstileIfLocalBypass();
        checkAppVersion();
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
            String runtimeVersion = version.getDeployType() == AppVersion.DeployType.DOCKER ? dockerVersion : sshVersion;

            log.debug("获取到的配置文件版本:dockerVersion:{}", dockerVersion);
            log.debug("获取到的配置文件版本:sshVersion:{}", sshVersion);

            if (StringUtils.isNotBlank(runtimeVersion)) {
                boolean changed = false;
                if (!StringUtils.equals(runtimeVersion, version.getCurrentVersion())) {
                    log.info("检测到当前运行版本变化, 数据库版本:{} -> 运行版本:{}",
                            version.getCurrentVersion(), runtimeVersion);
                    version.setCurrentVersion(runtimeVersion);
                    changed = true;
                }
                if (StringUtils.isBlank(version.getLatestVersion())
                        || compareVersion(runtimeVersion, version.getLatestVersion()) >= 0) {
                    version.setLatestVersion(runtimeVersion);
                    changed = true;
                }
                if (changed) {
                    versionRepository.save(version);
                }
            }

            log.info("版本已更新到: {}", version.getCurrentVersion());
        } catch (RuntimeException e) {
            log.warn("未找到版本信息");
        }
    }

    private int compareVersion(String left, String right) {
        String[] leftParts = normalizeVersion(left).split("\\.");
        String[] rightParts = normalizeVersion(right).split("\\.");
        int length = Math.max(leftParts.length, rightParts.length);
        for (int i = 0; i < length; i++) {
            int leftValue = i < leftParts.length ? parseVersionPart(leftParts[i]) : 0;
            int rightValue = i < rightParts.length ? parseVersionPart(rightParts[i]) : 0;
            if (leftValue != rightValue) {
                return Integer.compare(leftValue, rightValue);
            }
        }
        return 0;
    }

    private String normalizeVersion(String version) {
        if (version == null) {
            return "";
        }
        return version.trim().replaceFirst("^[vV][-_]?", "");
    }

    private int parseVersionPart(String part) {
        if (part == null) {
            return 0;
        }
        String digits = part.replaceAll("[^0-9].*$", "");
        if (digits.isEmpty()) {
            return 0;
        }
        return Integer.parseInt(digits);
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
