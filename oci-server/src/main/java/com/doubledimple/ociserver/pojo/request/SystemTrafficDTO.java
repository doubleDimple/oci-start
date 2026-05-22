package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import java.util.Date;
import java.util.Map;

/**
 * 系统流量DTO
 */
@Data
public class SystemTrafficDTO {
    private Date startDate;
    private Date endDate;
    private long totalTraffic;
    private Map<Date, Long> dailyTraffic;
}
