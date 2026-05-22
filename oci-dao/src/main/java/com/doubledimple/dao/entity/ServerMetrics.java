package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import javax.persistence.Transient;
import java.time.Duration;
import java.time.LocalDateTime;

/**
 * @author doubleDimple
 * @date 2024:11:16日 23:13
 */
@Data
@Entity
@Table(name = "server_metrics")
public class ServerMetrics {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String serverId;
    private String serverIp;
    private Double cpuUsage;
    private Double memoryUsage;
    private Double diskUsage;
    private Double uploadTraffic;
    private Double downloadTraffic;
    private LocalDateTime lastConnectionTime;

    private Integer cpuCores;     // CPU核心数
    private Double totalMemory;   // 总内存(GB)
    private Double totalDisk;     // 总磁盘空间(GB)

    @Transient  // 不持久化到数据库
    private boolean isOnline;

    private String totalUploadTraffic;
    private String totalDownloadTraffic;

    public boolean isOnline() {
        if (lastConnectionTime == null) return false;
        return Duration.between(lastConnectionTime, LocalDateTime.now()).toMinutes() < 5; // 5分钟内有心跳则认为在线
    }
}
