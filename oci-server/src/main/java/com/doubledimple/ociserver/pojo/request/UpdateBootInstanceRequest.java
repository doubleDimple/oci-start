package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName UpdateBootInstanceRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-30 07:47
 */
@Data
public class UpdateBootInstanceRequest {
    private String id;
    private Integer ocpu;
    private Integer memory;
    private Integer disk;
    private Integer loopTime;
    private String rootPassword;

    private String dayGap;
}
