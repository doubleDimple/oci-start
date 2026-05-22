package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

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

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    @Column(name = "create_time")
    private LocalDateTime createTime;
}
