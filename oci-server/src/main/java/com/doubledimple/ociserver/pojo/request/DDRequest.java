package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName DDRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-25 10:47
 */
@Data
public class DDRequest {

    private String instanceId;
    private String osType;
    private String osVersion;
    private String ddPassword;
}
