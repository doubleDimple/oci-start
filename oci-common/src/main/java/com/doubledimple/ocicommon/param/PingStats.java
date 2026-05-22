package com.doubledimple.ocicommon.param;

import lombok.Data;

import java.util.List;

@Data
public class PingStats {
    private int successCount;
    private int totalCount;
    private double successRate;
    private List<Long> responseTimes;
    private long avgResponseTime;
    private long minResponseTime;
    private long maxResponseTime;

}
