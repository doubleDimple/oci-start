package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import java.util.Date;

/**
 * 小时流量DTO
 */
@Data
public class HourlyTrafficDTO {
    private Date timestamp;
    private long inboundBytes;
    private long outboundBytes;
    private long totalBytes;
}
