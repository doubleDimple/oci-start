package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName UpdateRemarkRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-16 10:53
 */
@Data
public class UpdateRemarkRequest {
    private Long instanceId;
    private String remark;
}
