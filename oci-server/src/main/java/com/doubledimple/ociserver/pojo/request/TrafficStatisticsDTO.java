package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import java.util.List;

/**
 * 流量统计DTO
 */
@Data
public class TrafficStatisticsDTO {
    private List<InstanceTrafficDTO> instanceTraffics;
    private long totalTraffic;
    private long todayTraffic;
}
