package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.persistence.Column;

/**
 * @version 1.0.0
 * @ClassName VpnProxyRecordRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-01 13:48
 */
@Data
public class VpnProxyRecordRequest extends BaseRequest{

    private Long id;

    private String proxyType;

    /**
     * 代理地址（主机/IP）
     */
    private String proxyHost;

    /**
     * 代理端口
     */
    private Integer proxyPort;

    /**
     * 代理用户名（可选）
     */
    private String proxyUsername;

    /**
     * 代理密码（可选）
     */
    private String proxyPassword;

    /**
     * 可用状态（1 = 可用，0 = 不可用）
     */
    private Integer availableStatus = 1;

    /**
     * 是否强制代理（1 = 强制，0 = 非强制）
     */
    private Integer forceProxy = 0;

    /**
     * 绑定的父租户 ID（null / 不传 = 全局共享）
     */
    private Long tenantId;
}
