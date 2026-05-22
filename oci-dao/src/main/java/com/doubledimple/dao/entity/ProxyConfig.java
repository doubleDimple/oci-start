package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
* @Description:  反向代理配置
* @Param:
* @return:
* @Author: doubleDimple
* @Date: 11/1/25 1:36 PM
*/
@Data
@Entity
@Table(name = "proxy_config")
public class ProxyConfig {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "domain", nullable = false, unique = true)
    private String domain;

    @Column(name = "target_host", nullable = false)
    private String targetHost;

    @Column(name = "target_port", nullable = false)
    private Integer targetPort;

    @Column(name = "protocol")
    private String protocol = "http";

    @Column(name = "enable_ssl")
    private Boolean enableSsl = false;

    @Column(name = "enable_websocket")
    private Boolean enableWebSocket = false;

    @Column(name = "ssl_certificate_id")
    private Long sslCertificateId;

    @Column(name = "config_status")
    @Enumerated(EnumType.STRING)
    private ConfigStatus configStatus = ConfigStatus.PENDING;

    @Column(name = "ssl_status")
    @Enumerated(EnumType.STRING)
    private SslStatus sslStatus = SslStatus.NOT_CONFIGURED;

    // 新增字段
    @Column(name = "custom_config", columnDefinition = "TEXT")
    private String customConfig;

    @Column(name = "remark")
    private String remark;

    @Column(name = "load_balance_type")
    private String loadBalanceType;

    @Column(name = "enable_health_check")
    private Boolean enableHealthCheck = false;

    @Column(name = "health_check_path")
    private String healthCheckPath;

    @Column(name = "health_check_interval")
    private Integer healthCheckInterval;

    @Column(name = "enable_rate_limit")
    private Boolean enableRateLimit = false;

    @Column(name = "rate_limit")
    private Integer rateLimit;

    @Column(name = "enable_cache")
    private Boolean enableCache = false;

    @Column(name = "cache_time")
    private Integer cacheTime;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    @PrePersist
    protected void onCreate() {
        createTime = LocalDateTime.now();
        updateTime = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updateTime = LocalDateTime.now();
    }

    public enum ConfigStatus {
        PENDING, APPLIED, ERROR, DISABLED
    }

    public enum SslStatus {
        NOT_CONFIGURED, CONFIGURED, PENDING, ERROR
    }
}
