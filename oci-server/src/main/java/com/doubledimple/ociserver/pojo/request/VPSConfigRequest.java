package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName VPSConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-05 10:07
 */
@Data
public class VPSConfigRequest {
    private String type; // telecom, unicom, mobile
    private boolean enabled;
    private String serverIp;
    private String username;
    private String password;
    private int sshPort;
}
