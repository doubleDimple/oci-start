package com.doubledimple.ocimonitor.service;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.monitor.MonitorReportDTO;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.env.Environment;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;
import org.springframework.util.StreamUtils;
import com.doubledimple.ocicommon.param.monitor.MonitorAlert;

import javax.annotation.Resource;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;
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
        String serverPort = environment.getProperty("server.port", "9856");
        String serverUrl = String.format("http://%s:%s", getPublicIp2(), serverPort);
        try {
            ClassPathResource resource = new ClassPathResource("scripts/monitor_agent.sh");
            String content = StreamUtils.copyToString(resource.getInputStream(), StandardCharsets.UTF_8);
            String reportUrl = serverUrl + "/api/monitor/report";
            return content.replace("{{SERVER_URL}}", reportUrl)
                    .replace("{{TOKEN}}", token)
                    .replace("{{INTERVAL}}", String.valueOf(interval));
        } catch (Exception e) {
            log.error("生成监控脚本失败", e);
            return "# Error: 生成脚本失败, 请检查后端日志";
        }
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
