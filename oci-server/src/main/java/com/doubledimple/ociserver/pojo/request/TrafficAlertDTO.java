package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 *
 */
@Data
public class TrafficAlertDTO {
    private Long tenantId;
    private Double threshold;
    private Boolean autoShutdown;
    /*private String email;*/

    private Boolean enabled;

    private Boolean statisticsEnabled;

}
