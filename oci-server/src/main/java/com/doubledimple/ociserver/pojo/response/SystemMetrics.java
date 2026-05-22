package com.doubledimple.ociserver.pojo.response;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * @author doubleDimple
 * @date 2024:11:28日 22:33
 */
@Data
@Builder
public class SystemMetrics {
    // CPU信息
    private Double cpuUsage;           // CPU使用率
    private Double cpuTemperature;     // CPU温度
    private Integer cpuPhysicalCount;  // CPU物理核心数
    private Integer cpuLogicalCount;   // CPU逻辑核心数
    private String cpuModel;           // CPU型号
    private Double cpuFrequency;       // CPU频率

    // 内存信息
    private Double memoryUsage;        // 内存使用率
    private Long totalMemory;          // 总内存
    private Long availableMemory;      // 可用内存
    private Long usedMemory;           // 已用内存
    private Double swapUsage;          // 交换空间使用率
    private Long swapTotal;            // 交换空间总量
    private Long swapUsed;             // 已用交换空间

    // 磁盘信息
    private Double diskUsage;          // 磁盘使用率
    private Long diskTotal;            // 总磁盘空间
    private Long diskUsed;             // 已用磁盘空间
    private Long diskFree;             // 可用磁盘空间

    // 网络信息
    private Double uploadSpeed;        // 上传速度
    private Double downloadSpeed;      // 下载速度
    private Long lastUploadBytes;      // 上次上传字节数
    private Long lastDownloadBytes;    // 上次下载字节数
    private Long lastUpdateTime;       // 上次更新时间

    // 系统信息
    private Integer totalProcesses;    // 总进程数
    private Integer threadCount;       // 总线程数
    private Long systemUptime;         // 系统运行时间
    private String osName;             // 操作系统名称
    private String osArch;             // 系统架构
    private String hostname;           // 主机名

    private LocalDateTime timestamp;   // 时间戳

    private Long totalUploadBytes;   // 总上传字节数
    private Long totalDownloadBytes; // 总下载字节数
}
