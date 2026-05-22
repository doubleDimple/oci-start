package com.doubledimple.dao.entity;

import com.doubledimple.ocicommon.enums.ProviderType;
import com.doubledimple.ocicommon.enums.RecordStatus;
import com.doubledimple.ocicommon.enums.RecordType;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import javax.persistence.Transient;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName DnsRecord
 * @Description DNS记录实体类，支持多种域名服务商
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "dns_record", indexes = {
        @Index(name = "idx_provider_type", columnList = "provider_type"),
        @Index(name = "idx_domain_name", columnList = "domain_name"),
        @Index(name = "idx_record_name", columnList = "record_name"),
        @Index(name = "idx_record_type", columnList = "record_type")
})
@Slf4j
public class DnsRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 域名服务商类型
     */
    @Column(name = "provider_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private ProviderType providerType;

    /**
     * 域名
     */
    @Column(name = "domain_name", nullable = false, length = 255)
    private String domainName;

    /**
     * 记录名称（子域名）
     */
    @Column(name = "record_name", nullable = false, length = 255)
    private String recordName;

    /**
     * 记录类型（A、AAAA、CNAME、MX等）
     */
    @Column(name = "record_type", nullable = false, length = 32)
    @Enumerated(EnumType.STRING)
    private RecordType recordType;

    /**
     * 记录值（IP地址或目标域名）
     */
    @Column(name = "record_value", nullable = false, length = 500)
    private String recordValue;


    /**
     * 这里是需要更新的新的ip（IP地址或目标域名）
     */
    @Transient
    private String newRecordValue;

    /**
     * TTL值
     */
    @Column(name = "ttl")
    private Integer ttl;

    /**
     * 优先级（用于MX记录等）
     */
    @Column(name = "priority")
    private Integer priority;

    /**
     * 服务商侧的记录ID
     */
    @Column(name = "provider_record_id", length = 100)
    private String providerRecordId;

    /**
     * Zone ID（Cloudflare专用）
     */
    @Column(name = "zone_id", length = 100)
    private String zoneId;

    /**
     * 是否启用代理（Cloudflare专用）
     */
    @Column(name = "proxied")
    private Boolean proxied;

    /**
     * 记录状态
     */
    @Column(name = "status")
    @Enumerated(EnumType.STRING)
    private RecordStatus status;

    /**
     * 备注信息
     */
    @Column(name = "remark", length = 500)
    private String remark;

    /**
     * 扩展字段（JSON格式，存储不同服务商的特殊字段）
     */
    @Column(name = "extra_data", columnDefinition = "TEXT")
    private String extraData;

    /**
     * 创建时间
     */
    @Column(name = "create_time", nullable = false)
    private LocalDateTime createTime;

    /**
     * 更新时间
     */
    @Column(name = "update_time", nullable = false)
    private LocalDateTime updateTime;

    /**
     * 最后同步时间
     */
    @Column(name = "last_sync_time")
    private LocalDateTime lastSyncTime;

    /**
     * 权重（用于负载均衡，主要用于EdgeOne等支持权重的DNS服务商）
     * 取值范围通常为0-100，0表示不解析，null表示不设置权重
     */
    @Column(name = "weight")
    private Integer weight;

    /**
     * 类型标识（1=本站代理，0=非本站代理）
     */
    @Column(name = "type", nullable = false, columnDefinition = "int default 1")
    private Integer type = 1;


    /**
     * 获取完整的记录名称
     */
    public String getFullRecordName() {
        if ("@".equals(recordName) || recordName.equals(domainName)) {
            return domainName;
        }
        return recordName + "." + domainName;
    }

    /**
     * 判断是否为根域名记录
     */
    public boolean isRootRecord() {
        return "@".equals(recordName) || recordName.equals(domainName);
    }

    /**
     * 判断是否为Cloudflare记录
     */
    public boolean isCloudflareRecord() {
        return ProviderType.CLOUDFLARE.equals(providerType);
    }

    /**
     * 设置创建和更新时间
     */
    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        this.createTime = now;
        this.updateTime = now;
    }

    /**
     * 更新时间
     */
    @PreUpdate
    protected void onUpdate() {
        this.updateTime = LocalDateTime.now();
    }

    /**
     * 日志输出格式
     */
    @Override
    public String toString() {
        return String.format("DnsRecord{id=%d, provider=%s, domain=%s, name=%s, type=%s, value=%s}",
                id, providerType, domainName, recordName, recordType, recordValue);
    }
}
