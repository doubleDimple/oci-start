package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName IpCheckConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-04 14:31
 */
@Data
public class IpCheckConfigRequest {

    private boolean enabled;
    private int checkInterval;

    private String vpsUsername;
    private String vpsPassword;
    private int sshPort;
}
