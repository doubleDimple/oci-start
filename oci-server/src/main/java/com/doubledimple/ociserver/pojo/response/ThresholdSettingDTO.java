package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

@Data
public class ThresholdSettingDTO {
    private String instanceId;
    private Double threshold;
    private Boolean autoShutdown;
}
