package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 *
 */
@Data
public class InstanceTrafficVO {
    private String instanceId;
    private String region;
    private Double ingressBytes;
    private Double egressBytes;
    private Double totalBytes;
    private Double threshold;
    private Boolean autoShutdown;

    private LocalDate startDate;
    private LocalDate endDate;
    private String tenancyName;

    private LocalDateTime timePoint;

    private String period;
/*
    private String providerTenantId;  // 用于存储OCI的OCID
*/
    private LocalDateTime lastUpdated;

    private String displayName;
    private String publicIp;
    private String privateIp;
    private String state;
    private String tenancy;
    private String publicIps;
    private String instanceName;
}
