package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * 租户本月流量统计结果
 *
 * @Author doubleDimple
 */
@Data
public class TenantTrafficStats {

    private Long tenantId;
    private String tenancy;
    private String tenancyName;
    private String displayName;
    private String region;

    /** 本月总出站流量（GB） */
    private double totalEgressGB;

    /** 流量预警阈值（GB），可能为空 */
    private Double thresholdGB;

    /** 是否启用流量统计 */
    private Boolean statisticsEnabled;

    /** 是否启用自动关机 */
    private Boolean autoShutdown;

    /** 本月统计起始时间（UTC） */
    private LocalDateTime startTime;

    /** 本月统计结束时间（UTC） */
    private LocalDateTime endTime;

    /** 实例流量明细 */
    private List<InstanceTraffic> instances = new ArrayList<>();

    /** 查询是否成功 */
    private boolean success = true;

    /** 失败原因或额外说明 */
    private String message;

    @Data
    public static class InstanceTraffic {
        private String instanceId;
        private String instanceName;
        private String publicIp;
        private int vnicCount;
        private double egressGB;
    }
}
