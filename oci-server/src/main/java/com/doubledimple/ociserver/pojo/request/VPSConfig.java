package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName VPSConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-05 10:07
 */
@Data
public class VPSConfig {
    private boolean enabled;
    private String serverIp;
    private String username;
    private String password;
    private int sshPort;

    /**
    * 运营商类型
    */
    private String type;
}
