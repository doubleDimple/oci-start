package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName IpCheckConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-04 14:40
 */
@Data
public class IpCheckConfig {
    private boolean enabled;
    private int checkInterval;

    private String vpsUsername;
    private String vpsPassword;
    private int sshPort;

}
