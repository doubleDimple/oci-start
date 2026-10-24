package com.doubledimple.ocimonitor.service;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.monitor.MonitorReportDTO;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.env.Environment;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;
import org.springframework.util.StreamUtils;
import com.doubledimple.ocicommon.param.monitor.MonitorAlert;

import javax.annotation.Resource;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.LinkedHashMap;
import java.util.Base64;
import java.util.concurrent.ConcurrentHashMap;

import static com.doubledimple.ocicommon.utils.IpUtils.getPublicIp2;

/**
 * @version 1.0.0
 * @ClassName MonitorCoreService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-05 13:36
 */
@Slf4j
@Service
public class MonitorCoreService {

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private Environment environment;

    private final Map<String, Date> HEARTBEAT_BUFFER = new ConcurrentHashMap<>();

    private final Map<String, Long> ALERT_COOLDOWN = new ConcurrentHashMap<>();

    public String generateInstallScript(String token, int interval) {
        return generateResourceScript(token, interval, getPublicServerUrl());
    }

    /** Anonymous resource-script download never issues or embeds network credentials. */
    private String generateResourceScript(String token, int interval, String serverUrl) {
        if (token == null || token.length() > 4096 || interval < 1 || interval > 3600) {
            throw new IllegalArgumentException("监控脚本参数无效");
        }
        try {
            String content = readScript("scripts/monitor_agent.sh");
            String reportUrl = serverUrl + "/api/monitor/report";
            return content.replace("{{SERVER_URL}}", shellQuote(reportUrl))
                    .replace("{{TOKEN}}", shellQuote(token))
                    .replace("{{INTERVAL}}", String.valueOf(interval));
        } catch (Exception e) {
            log.error("生成监控脚本失败", e);
            throw new IllegalStateException("生成监控脚本失败，请检查后端日志", e);
        }
    }

    /** Only the authenticated install service supplies the one-time random credential. */
    public String generateNetworkInstallScript(String instanceToken, String credential, int interval) {
        if (credential == null || !credential.matches("[A-Za-z0-9_-]{32,256}")) {
            throw new IllegalArgumentException("网络探针凭据无效");
        }
        try {
            String serverUrl = getPublicServerUrl();
            Map<String, Object> config = new LinkedHashMap<>();
            config.put("serverUrl", serverUrl);
            config.put("credential", credential);
            Map<String, String> bundle = new LinkedHashMap<>();
            bundle.put("monitor.sh", Base64.getEncoder().encodeToString(generateResourceScript(instanceToken, interval, serverUrl).getBytes(StandardCharsets.UTF_8)));
            bundle.put("network_probe.py", Base64.getEncoder().encodeToString(readScript("scripts/network_probe.py").getBytes(StandardCharsets.UTF_8)));
            bundle.put("config.json", Base64.getEncoder().encodeToString(new ObjectMapper().writeValueAsBytes(config)));
            String encodedBundle = new ObjectMapper().writeValueAsString(bundle);
            // The complete installer is sent over SSH stdin, never as shell arguments or logs.
            return "#!/bin/bash\nset -eu\numask 077\n" +
                    "[ \"$(id -u)\" -eq 0 ] || { echo '安装监控探针需要 root 权限。' >&2; exit 1; }\n" +
                    "command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] || { echo '安装监控探针需要运行中的 systemd。' >&2; exit 1; }\n" +
                    "command -v python3 >/dev/null 2>&1 || { echo '网络探针需要 Python 3，请先安装后重试。' >&2; exit 1; }\n" +
                    "python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' || { echo '网络探针需要 Python 3.6 或更新版本。' >&2; exit 1; }\n" +
                    "VPS_INSTALL_DIR=$(mktemp -d /tmp/vps-agent-install.XXXXXX)\n" +
                    "trap 'rm -rf -- \"$VPS_INSTALL_DIR\"' EXIT\n" +
                    "python3 - \"$VPS_INSTALL_DIR\" <<'VPS_NETWORK_BUNDLE'\n" +
                    "import base64, json, os, sys\n" +
                    "bundle = json.loads('" + encodedBundle + "')\n" +
                    "for name, content in bundle.items():\n" +
                    "    path = os.path.join(sys.argv[1], name)\n" +
                    "    with open(path, 'wb') as output:\n" +
                    "        output.write(base64.b64decode(content, validate=True))\n" +
                    "    os.chmod(path, 0o600 if name == 'config.json' else 0o700)\n" +
                    "VPS_NETWORK_BUNDLE\n" +
                    "python3 \"$VPS_INSTALL_DIR/network_probe.py\" --check \"$VPS_INSTALL_DIR/config.json\"\n" +
                    "[ ! -L /etc/vps-network-agent ] || { echo '网络探针配置目录不能是符号链接。' >&2; exit 1; }\n" +
                    "mkdir -p /etc/vps-network-agent\nchown 0:0 /etc/vps-network-agent\nchmod 700 /etc/vps-network-agent\n" +
                    "install -m 700 \"$VPS_INSTALL_DIR/network_probe.py\" /usr/local/bin/vps-network-agent.py\n" +
                    "install -m 600 \"$VPS_INSTALL_DIR/config.json\" /etc/vps-network-agent/config.json\n" +
                    "cat > /etc/systemd/system/vps-network-agent.service <<'VPS_NETWORK_SERVICE'\n" +
                    "[Unit]\nDescription=VPS Network Quality Agent\nAfter=network-online.target\nWants=network-online.target\nStartLimitIntervalSec=60\nStartLimitBurst=3\n\n" +
                    "[Service]\nType=notify\nNotifyAccess=main\nExecStart=/usr/bin/env python3 /usr/local/bin/vps-network-agent.py /etc/vps-network-agent/config.json\n" +
                    "Restart=on-failure\nRestartSec=10\nTimeoutStartSec=15\nTimeoutStopSec=15\nKillMode=control-group\nUMask=0077\nUser=root\n\n" +
                    "[Install]\nWantedBy=multi-user.target\nVPS_NETWORK_SERVICE\n" +
                    "bash \"$VPS_INSTALL_DIR/monitor.sh\" install\n" +
                    "systemctl daemon-reload\nsystemctl enable vps-network-agent.service\nsystemctl restart vps-network-agent.service\n" +
                    "systemctl is-enabled --quiet vps-agent.service\nsystemctl is-active --quiet vps-agent.service\n" +
                    "systemctl is-enabled --quiet vps-network-agent.service\nsystemctl is-active --quiet vps-network-agent.service\n" +
                    "echo '资源与网络探针已启动，请等待真实数据上报。'\n";
        } catch (Exception e) {
            // Never include the generated script or credential in the exception or logs.
            log.error("生成网络探针安装包失败: {}", e.getClass().getSimpleName());
            throw new IllegalStateException("生成网络探针安装包失败");
        }
    }

    private String getPublicServerUrl() {
        String configured = environment.getProperty("oci.monitor.public-url");
        String serverUrl = configured == null || configured.trim().isEmpty()
                ? String.format("http://%s:%s", getPublicIp2(), environment.getProperty("server.port", "9856"))
                : configured.trim();
        while (serverUrl.endsWith("/")) serverUrl = serverUrl.substring(0, serverUrl.length() - 1);
        try {
            URI uri = new URI(serverUrl);
            if (!("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) || uri.getHost() == null
                    || uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
                    || uri.getPort() < -1 || uri.getPort() == 0 || uri.getPort() > 65535) {
                throw new IllegalArgumentException();
            }
            return serverUrl;
        } catch (Exception e) {
            throw new IllegalStateException("oci.monitor.public-url 必须是有效的 HTTP(S) 公网服务地址");
        }
    }

    private String readScript(String path) throws java.io.IOException {
        try (InputStream input = new ClassPathResource(path).getInputStream()) {
            return StreamUtils.copyToString(input, StandardCharsets.UTF_8);
        }
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\"'\"'") + "'";
    }

    /**
     * 处理上报的监控数据
     * @param reportDto 脚本发上来的 JSON 数据
     */
    public ApiResponse processReportData(MonitorReportDTO reportDto) {
        MonitorAlert monitorAlert = null;
        try {
            String instanceId = reportDto.getToken();
            HEARTBEAT_BUFFER.put(instanceId, new Date());
            log.debug("收到上报: Host={}, CPU={}%, MemUsed={}MB",
                    reportDto.getHost().getName(),
                    reportDto.getCpu().getUsage(),
                    reportDto.getMemory().getUsed());
            monitorAlert = checkResourceThresholds(reportDto);
        } catch (NumberFormatException e) {
            log.error("上报 Token 格式错误，非数字 ID: {}", reportDto.getToken());
        } catch (Exception e) {
            log.error("处理监控数据异常", e);
        }
        return ApiResponse.success(monitorAlert);
    }

    /**
     * 检查资源是否超过阈值
     */
    private MonitorAlert checkResourceThresholds(MonitorReportDTO dto) {
        List<String> warningDetails = new ArrayList<>();
        if (dto.getCpu().getUsage() > 80.0) {
            warningDetails.add(String.format("CPU(%.0f%%)", dto.getCpu().getUsage()));
        }
        double memUsage = (double) dto.getMemory().getUsed() / dto.getMemory().getTotal() * 100;
        if (memUsage > 90.0) {
            warningDetails.add(String.format("内存(%.0f%%)", memUsage));
        }
        if (warningDetails.isEmpty()) {
            return null;
        }
        String finalMsg = String.join(" | ", warningDetails);
        return new MonitorAlert(dto.getToken(), "RESOURCE_OVERLOAD", finalMsg);
    }

    /**
     * 触发告警 (带冷却机制)
     */
    private void triggerAlert(String instanceId, String alertType, String message) {
        String key = instanceId + ":" + alertType;
        long now = System.currentTimeMillis();
        long lastAlert = ALERT_COOLDOWN.getOrDefault(key, 0L);
        // 冷却时间 5 分钟 (300000 毫秒)
        if (now - lastAlert > 300000) {
            log.warn("【发送告警】实例ID: {}, 内容: {}", instanceId, message);
            ALERT_COOLDOWN.put(key, now);
        }
    }

    // 2. 定时任务调用：把内存里的时间刷进数据库 (每 15 秒)
    public void flushHeartbeatToDB() {
        if (HEARTBEAT_BUFFER.isEmpty()) return;
        HEARTBEAT_BUFFER.forEach((id, time) -> {
            try {
                oracleInstanceDetailRepository.updateHeartbeat(id, time);
            } catch (Exception e) {
                log.error("更新心跳失败: {}", id);
            }
        });
        HEARTBEAT_BUFFER.clear();
    }

    // 3. 定时任务调用：检查离线 (每 1 分钟)
    public void checkOfflineInstances() {
        Date threshold = new Date(System.currentTimeMillis() - 3 * 60 * 1000);
        List<InstanceDetails> offlineList = oracleInstanceDetailRepository.findOfflineInstances(threshold);

        for (InstanceDetails vm : offlineList) {
            log.warn("机器离线: {}", vm.getDisplayName());
        }
    }
}
