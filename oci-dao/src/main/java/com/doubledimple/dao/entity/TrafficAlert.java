package com.doubledimple.dao.entity;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName InstanceTraffic
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-10 09:15
 */
@Entity
@Table(name = "traffic_alert")
@Data
public class TrafficAlert {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tenant_id", nullable = false)
    private Long tenantId;

    @Column(name = "tenancy", length = 500, nullable = false)
    private String tenancy;

    // 流量阈值(GB)
    @Column(name = "threshold", nullable = false)
    private Double threshold;

    // 是否自动关机
    @Column(name = "auto_shutdown", nullable = false)
    private Boolean autoShutdown = false;

    // 通知邮箱
    @Column(name = "notification_email")
    private String notificationEmail;

    // 是否启用
    @Column(name = "enabled", nullable = false)
    private Boolean enabled;

    // 最后通知时间
    @Column(name = "last_notification")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime lastNotification;

    // 创建时间
    @Column(name = "created_at", nullable = false, updatable = false)
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;

    // 更新时间
    @Column(name = "updated_at")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime updatedAt;

    // 统计是否开启
    @Column(name = "statistics_enabled", nullable = false)
    private Boolean statisticsEnabled = false;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
