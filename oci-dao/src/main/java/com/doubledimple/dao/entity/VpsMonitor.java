package com.doubledimple.dao.entity;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.Data;
import lombok.ToString;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Lob;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import javax.persistence.Transient;
import javax.persistence.Version;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * VPS监控实体类
 * @author doubleDimple
 * @date 2024:12:09
 */
@Entity
@Table(name = "VPS_MONITOR")
@ToString
@Data
public class VpsMonitor {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Version
    @Column(name = "version", columnDefinition = "BIGINT DEFAULT 0")
    private Long version;

    // =============== 基本信息 ===============
    @Column(name = "vps_id", nullable = false, unique = true)
    private String vpsId;

    @Column(name = "vps_name")
    private String vpsName;

    @Column(name = "provider")
    private String provider; // 服务商名称（如：腾讯云、阿里云、AWS等）

    @Column(name = "instance_type")
    private String instanceType; // 实例规格

    // =============== 硬件配置 ===============
    @Column(name = "cpu_cores")
    private Integer cpuCores;

    @Column(name = "memory_gb")
    private Integer memoryGb;

    @Column(name = "disk_gb")
    private Integer diskGb;

    @Column(name = "bandwidth_mbps")
    private Integer bandwidthMbps; // 带宽

    // =============== 网络信息 ===============
    @Column(name = "public_ip")
    private String publicIp;

    @Column(name = "private_ip")
    private String privateIp;

    @Column(name = "port")
    private Integer port = 22; // SSH端口

    // =============== 地理位置信息 ===============
    @Column(name = "region")
    private String region; // 区域

    @Column(name = "zone")
    private String zone; // 可用区

    @Column(name = "country")
    private String country; // 国家

    @Column(name = "city")
    private String city; // 城市

    @Column(name = "latitude", precision = 10, scale = 6)
    private BigDecimal latitude; // 纬度

    @Column(name = "longitude", precision = 10, scale = 6)
    private BigDecimal longitude; // 经度

    // =============== 监控数据 ===============
    @Column(name = "cpu_usage", precision = 5, scale = 2)
    private BigDecimal cpuUsage; // CPU使用率(%)

    @Column(name = "memory_usage", precision = 5, scale = 2)
    private BigDecimal memoryUsage; // 内存使用率(%)

    @Column(name = "disk_usage", precision = 5, scale = 2)
    private BigDecimal diskUsage; // 磁盘使用率(%)

    @Column(name = "network_in_mbps", precision = 10, scale = 2)
    private BigDecimal networkInMbps; // 网络入流量(Mbps)

    @Column(name = "network_out_mbps", precision = 10, scale = 2)
    private BigDecimal networkOutMbps; // 网络出流量(Mbps)

    @Column(name = "load_average", precision = 5, scale = 2)
    private BigDecimal loadAverage; // 系统负载

    @Column(name = "uptime_hours")
    private Long uptimeHours; // 运行时间(小时)

    // =============== 状态信息 ===============
    @Column(name = "status")
    private Integer status = 0; // 0:离线 1:在线 2:异常 3:维护中

    @Column(name = "last_ping_time")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime lastPingTime; // 最后ping时间

    @Column(name = "response_time_ms")
    private Integer responseTimeMs; // 响应时间(毫秒)

    @Column(name = "is_monitoring_enabled")
    private Boolean isMonitoringEnabled = true; // 是否启用监控

    // =============== 认证信息 ===============
    @Column(name = "username")
    private String username = "root";

    @Column(name = "password")
    private String password;

    @Column(name = "ssh_key")
    @Lob
    private String sshKey; // SSH私钥

    // =============== 其他信息 ===============
    @Column(name = "os_type")
    private String osType; // 操作系统类型

    @Column(name = "os_version")
    private String osVersion; // 操作系统版本

    @Column(name = "architecture")
    private String architecture = "amd64"; // 架构类型

    @Column(name = "monthly_cost", precision = 10, scale = 2)
    private BigDecimal monthlyCost; // 月费用

    @Column(name = "remark", length = 500)
    private String remark; // 备注

    @Column(name = "tags")
    private String tags; // 标签，用逗号分隔

    // =============== 时间字段 ===============
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Column(name = "last_monitor_time")
    private LocalDateTime lastMonitorTime; // 最后监控时间

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    // =============== Getter/Setter 方法 ===============

    // =============== 格式化方法 ===============
    @Transient
    public String getFormattedCreatedAt() {
        if (createdAt == null) return "";
        return createdAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    @Transient
    public String getFormattedUpdatedAt() {
        if (updatedAt == null) return "";
        return updatedAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    @Transient
    public String getFormattedLastMonitorTime() {
        if (lastMonitorTime == null) return "";
        return lastMonitorTime.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    @Transient
    public String getFormattedLastPingTime() {
        if (lastPingTime == null) return "";
        return lastPingTime.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    // =============== 状态转换方法 ===============
    @Transient
    public String getStatusText() {
        switch (status != null ? status : 0) {
            case 1: return "在线";
            case 2: return "异常";
            case 3: return "维护中";
            default: return "离线";
        }
    }

    @Transient
    public String getLocationText() {
        StringBuilder location = new StringBuilder();
        if (country != null) location.append(country);
        if (city != null) {
            if (location.length() > 0) location.append("-");
            location.append(city);
        }
        if (region != null) {
            if (location.length() > 0) location.append("-");
            location.append(region);
        }
        return location.toString();
    }
}
