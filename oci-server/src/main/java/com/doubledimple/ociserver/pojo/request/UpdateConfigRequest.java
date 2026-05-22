package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName UpdateConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-25 12:44
 */
@Data
public class UpdateConfigRequest {
    private String instanceId;
    private Integer cpu;
    private Integer memory;
}
