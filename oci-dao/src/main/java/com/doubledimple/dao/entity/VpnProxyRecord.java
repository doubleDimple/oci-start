package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import javax.persistence.Transient;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName AppVersion
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "vpn_proxy_record")
@Slf4j
public class VpnProxyRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 代理类型（HTTP、HTTPS、SOCKS5）
     */
    @Column(name = "proxy_type", length = 20, nullable = false)
    private String proxyType;

    /**
     * 代理地址（主机/IP）
     */
    @Column(name = "proxy_host", length = 128, nullable = false)
    private String proxyHost;

    /**
     * 代理端口
     */
    @Column(name = "proxy_port", nullable = false)
    private Integer proxyPort;

    /**
     * 代理用户名（可选）
     */
    @Column(name = "proxy_username", length = 64)
    private String proxyUsername;

    /**
     * 代理密码（可选）
     */
    @Column(name = "proxy_password", length = 128)
    private String proxyPassword;

    /**
     * 可用状态（1 = 可用，0 = 不可用）
     */
    @Column(name = "available_status", nullable = false)
    private Integer availableStatus = 1;

    /**
     * 是否强制代理（1 = 强制：探测失败则拒绝请求；0 = 非强制：失败可直连）
     */
    @Column(name = "force_proxy", nullable = false)
    private Integer forceProxy = 0;

    /**
     * 绑定的父租户 ID（兼容旧数据；正式绑定以 vpn_proxy_tenant_bind 为准。
     * null 且无 bind 记录 = 全局共享代理）
     */
    @Column(name = "tenant_id")
    private Long tenantId;

    /**
     * 自定义名称（可选，仅展示）
     */
    @Column(name = "custom_name", length = 128)
    private String customName;

    /**
     * 绑定租户展示名（非持久化，列表接口填充；多租户时逗号拼接）
     */
    @Transient
    private String tenantName;

    /**
     * 绑定的父租户 ID 列表（非持久化，列表/编辑接口填充）
     */
    @Transient
    private List<Long> tenantIds = new ArrayList<>();

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    @Column(name = "create_time")
    private LocalDateTime createTime;
}
