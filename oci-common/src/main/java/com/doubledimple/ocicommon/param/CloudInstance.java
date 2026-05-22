package com.doubledimple.ocicommon.param;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName CloudInstance
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-10 15:02
 */
@Data
public class CloudInstance {
    private String instancePoolId;
    private String resourceDisplayName;
    private String faultDomain;
    private String resourceId;
    private String availabilityDomain;
    private String imageId;
    private String shape;
    private String dedicatedVmHostId;
    private String region;

    /**
    * 总的流量(输入或者输出的总流量)
    */
    private Double totalTraffic;
}
