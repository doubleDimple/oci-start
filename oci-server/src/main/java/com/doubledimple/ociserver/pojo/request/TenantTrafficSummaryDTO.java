package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * 租户流量汇总DTO
 */
@Data
public class TenantTrafficSummaryDTO {
    private String tenantId;
    private String tenantName;
    private long inboundTraffic;
    private long outboundTraffic;
    private long totalTraffic;
}
