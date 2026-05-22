package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.dao.entity.ServerMetrics;
import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Duration;
import java.time.LocalDateTime;

/**
 * @author doubleDimple
 * @date 2024:11:16日 23:23
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ServerMetricsDTO {
    // 基本信息
    private String serverId;
    private String serverIp;

    // 资源使用率
    private Double cpuUsage;
    private Double memoryUsage;
    private Double diskUsage;

    // 网络流量
    private String uploadTraffic;
    private String downloadTraffic;

    // 运行时间信息
    private String uptime;
    private String bootTime;

    // 状态信息
    private boolean isOnline;
    private String offlineDuration;

    private Integer cpuCores;     // CPU核心数
    private Double totalMemory;   // 总内存(GB)
    private Double totalDisk;     // 总磁盘空间(GB)

    // 时间信息
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime lastCheckTime;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime lastConnectionTime;

    private String totalUploadTraffic;
    private String totalDownloadTraffic;

    // 警告阈值
    public static final double CPU_WARNING_THRESHOLD = 80.0;
    public static final double MEMORY_WARNING_THRESHOLD = 85.0;
    public static final double DISK_WARNING_THRESHOLD = 90.0;

    // CPU状态评估
    public String getCpuStatus() {
        if (cpuUsage == null) return "UNKNOWN";
        if (cpuUsage >= CPU_WARNING_THRESHOLD) return "CRITICAL";
        if (cpuUsage >= CPU_WARNING_THRESHOLD * 0.8) return "WARNING";
        return "NORMAL";
    }

    // 内存状态评估
    public String getMemoryStatus() {
        if (memoryUsage == null) return "UNKNOWN";
        if (memoryUsage >= MEMORY_WARNING_THRESHOLD) return "CRITICAL";
        if (memoryUsage >= MEMORY_WARNING_THRESHOLD * 0.8) return "WARNING";
        return "NORMAL";
    }

    // 磁盘状态评估
    public String getDiskStatus() {
        if (diskUsage == null) return "UNKNOWN";
        if (diskUsage >= DISK_WARNING_THRESHOLD) return "CRITICAL";
        if (diskUsage >= DISK_WARNING_THRESHOLD * 0.8) return "WARNING";
        return "NORMAL";
    }

    // 整体状态评估
    public String getOverallStatus() {
        if (!isOnline) return "OFFLINE";

        String cpuStatus = getCpuStatus();
        String memoryStatus = getMemoryStatus();
        String diskStatus = getDiskStatus();

        if (cpuStatus.equals("CRITICAL") ||
                memoryStatus.equals("CRITICAL") ||
                diskStatus.equals("CRITICAL")) {
            return "CRITICAL";
        }

        if (cpuStatus.equals("WARNING") ||
                memoryStatus.equals("WARNING") ||
                diskStatus.equals("WARNING")) {
            return "WARNING";
        }

        return "NORMAL";
    }

    // 计算离线时长
    public void calculateOfflineDuration() {
        if (isOnline || lastConnectionTime == null) {
            this.offlineDuration = null;
            return;
        }

        Duration duration = Duration.between(lastConnectionTime, LocalDateTime.now());
        long days = duration.toDays();
        long hours = duration.toHours();
        long minutes = duration.toMinutes();

        StringBuilder sb = new StringBuilder();
        if (days > 0) sb.append(days).append("天");
        if (hours > 0) sb.append(hours).append("小时");
        if (minutes > 0) sb.append(minutes).append("分钟");

        this.offlineDuration = sb.toString();
    }

    // 格式化网络流量
    public static String formatTraffic(double trafficInBytes) {
        if (trafficInBytes < 1024) {
            return String.format("%.2f B/s", trafficInBytes);
        } else if (trafficInBytes < 1024 * 1024) {
            return String.format("%.2f KB/s", trafficInBytes / 1024);
        } else if (trafficInBytes < 1024 * 1024 * 1024) {
            return String.format("%.2f MB/s", trafficInBytes / (1024 * 1024));
        } else {
            return String.format("%.2f GB/s", trafficInBytes / (1024 * 1024 * 1024));
        }
    }

    // 转换实体到DTO
    public static ServerMetricsDTO fromEntity(ServerMetrics entity) {
        return ServerMetricsDTO.builder()
                .serverId(entity.getServerId())
                .serverIp(entity.getServerIp())
                .cpuUsage(entity.getCpuUsage())
                .memoryUsage(entity.getMemoryUsage())
                .diskUsage(entity.getDiskUsage())
                .uploadTraffic(formatTraffic(entity.getUploadTraffic() == null ? 0d : entity.getUploadTraffic()))
                .downloadTraffic(formatTraffic(entity.getDownloadTraffic() == null ? 0d : entity.getDownloadTraffic()))
                .isOnline(entity.isOnline())
                .lastConnectionTime(entity.getLastConnectionTime())
                .lastCheckTime(entity.getLastConnectionTime())
                .cpuCores(entity.getCpuCores())
                .totalMemory(entity.getTotalMemory())
                .totalDisk(entity.getTotalDisk())
                .totalUploadTraffic(entity.getTotalUploadTraffic())
                .totalDownloadTraffic(entity.getTotalDownloadTraffic())
                .build();
    }

    // 数据验证
    public boolean isValid() {
        return serverId != null &&
                cpuUsage != null && cpuUsage >= 0 && cpuUsage <= 100 &&
                memoryUsage != null && memoryUsage >= 0 && memoryUsage <= 100 &&
                diskUsage != null && diskUsage >= 0 && diskUsage <= 100;
    }

    // 检查是否需要告警
    public boolean needsAlert() {
        return getOverallStatus().equals("CRITICAL") ||
                (!isOnline && lastConnectionTime != null &&
                        Duration.between(lastConnectionTime, LocalDateTime.now()).toMinutes() > 5);
    }
}
