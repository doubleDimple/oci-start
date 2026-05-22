package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * 实例流量DTO
 */
@Data
public class InstanceTrafficDTO {
    private Long dailyTrafficStatisticsId;
    private Long tenantId;
    private String tenantName;
    private long inboundBytes;
    private long outboundBytes;
    private long totalBytes;
    private long todayBytes;
}
