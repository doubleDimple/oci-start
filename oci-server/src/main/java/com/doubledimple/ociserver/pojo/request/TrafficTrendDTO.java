package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import java.time.ZonedDateTime;

/**
 * @version 1.0.0
 * @ClassName TrafficTrendDTO
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-16 15:00
 */
@Data
public class TrafficTrendDTO {
    private ZonedDateTime timestamp;
    private long inbound;
    private long outbound;
}
