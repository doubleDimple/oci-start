package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import javax.persistence.UniqueConstraint;

/**
 * 代理 ↔ 父租户 多对多绑定（一个代理可绑多个租户；一个租户仅绑一个代理）。
 */
@Data
@Entity
@Table(name = "vpn_proxy_tenant_bind",
        uniqueConstraints = @UniqueConstraint(name = "uk_vpn_proxy_tenant", columnNames = "tenant_id"))
public class VpnProxyTenantBind {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "proxy_id", nullable = false)
    private Long proxyId;

    /**
     * 绑定的父租户主键（唯一：一租户只能绑一条代理）
     */
    @Column(name = "tenant_id", nullable = false)
    private Long tenantId;
}
