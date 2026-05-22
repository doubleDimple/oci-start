package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName OciIpRange
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-18 16:35
 */
@Data
public class OciIpRange {

    private String region;
    private String cidr;
    private LocalDateTime lastUpdated;
}
