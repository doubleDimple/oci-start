package com.doubledimple.ociserver.pojo.request.nginx;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

/**
 * @version 1.0.0
 * @ClassName ProxyConfigUpdateDto
 * @Description
 * @Author doubleDimple
 * @Date 2025-09-23 14:24
 */
@Data
public class ProxyConfigUpdateDto {
    @NotNull(message = "ID不能为空")
    private Long id;

    @NotBlank(message = "域名不能为空")
    private String domain;

    @NotBlank(message = "目标主机不能为空")
    private String targetHost;

    @NotNull(message = "目标端口不能为空")
    private Integer targetPort;

    private String protocol;

    private Boolean enableSsl;

    private Boolean enableWebSocket;

    // 新增字段
    private Long sslCertificateId;

    private String customConfig;

    private String remark;

    private String loadBalanceType;

    private Boolean enableHealthCheck;

    private String healthCheckPath;

    private Integer healthCheckInterval;

    private Boolean enableRateLimit;

    private Integer rateLimit;

    private Boolean enableCache;

    private Integer cacheTime;
}
