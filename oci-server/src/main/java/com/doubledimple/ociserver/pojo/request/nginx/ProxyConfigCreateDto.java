package com.doubledimple.ociserver.pojo.request.nginx;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

/**
 * @version 1.0.0
 * @ClassName ProxyConfigCreateDto
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-23 14:23
 */
@Data
public class ProxyConfigCreateDto {
    @NotBlank(message = "域名不能为空")
    private String domain;

    @NotBlank(message = "目标主机不能为空")
    private String targetHost;

    @NotNull(message = "目标端口不能为空")
    private Integer targetPort;

    private String protocol = "http";

    private Boolean enableSsl = false;

    private Boolean enableWebSocket = false;

    // 新增字段：证书ID（用于关联已有证书）
    private Long sslCertificateId;

    // 新增字段：自定义配置
    private String customConfig;

    // 新增字段：备注
    private String remark;

    // 新增字段：负载均衡配置
    private String loadBalanceType; // round_robin, ip_hash, least_conn

    // 新增字段：健康检查
    private Boolean enableHealthCheck = false;

    private String healthCheckPath;

    private Integer healthCheckInterval; // 秒

    // 新增字段：限流配置
    private Boolean enableRateLimit = false;

    private Integer rateLimit; // 每秒请求数

    // 新增字段：缓存配置
    private Boolean enableCache = false;

    private Integer cacheTime; // 缓存时间（秒）
}
