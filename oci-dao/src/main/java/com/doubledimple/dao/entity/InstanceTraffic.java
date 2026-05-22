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
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName InstanceTraffic
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-10 09:15
 */
@Entity
@Table(name = "instance_traffic")
@Data
public class InstanceTraffic {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(length = 500)  // 增加字段长度
    private String instanceId;

    //tenant表主键
    @Column(name = "tenant_id")
    private Long tenantId;  // 保持为Long类型

    @Column(name = "tenancy", length = 500)
    private String tenancy;  // 用于存储OCI的OCID

    // 入站流量(bytes)
    private Double ingressBytes = 0.0;

    // 出站流量(bytes)
    private Double egressBytes = 0.0;

    // 统计日期
    @Column(name = "stats_date")
    private LocalDate statsDate;

    // 最后更新时间
    @Column(name = "last_updated")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime lastUpdated;

    // 实例所在区域
    private String region;

    // 流量阈值(GB)
    @Column(name = "threshold")
    private Double threshold;

    // 超过阈值自动关机
    @Column(name = "auto_shutdown")
    private Boolean autoShutdown;

    // 创建时间
    @Column(name = "created_at")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    @Column(name = "alert_sent", columnDefinition = "BOOLEAN DEFAULT false")
    private Boolean alertSent = false;

    public InstanceTraffic() {

    }

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        lastUpdated = LocalDateTime.now();

        // 确保流量字段有默认值
        if (ingressBytes == null) {
            ingressBytes = 0.0;
        }
        if (egressBytes == null) {
            egressBytes = 0.0;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        lastUpdated = LocalDateTime.now();
    }

    public InstanceTraffic(String instanceId, Long tenantId, String tenancy,
                           Double ingressBytes, Double egressBytes,
                           LocalDate statsDate) {
        this.instanceId = instanceId;
        this.tenantId = tenantId;
        this.tenancy = tenancy;
        this.ingressBytes = ingressBytes;
        this.egressBytes = egressBytes;
        this.statsDate = statsDate;
    }
}
