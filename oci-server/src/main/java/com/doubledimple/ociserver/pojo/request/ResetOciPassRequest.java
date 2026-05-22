package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * @version 1.0.0
 * @ClassName ResetOcipassRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-07 09:07
 */
@Data
public class ResetOciPassRequest {

    @NotBlank(message = "租户ID不能为空")
    private String tenantId;
    @NotBlank(message = "用户ID不能为空")
    private String userId;

    @NotBlank(message = "用户名称不能为空")
    private String userName;
}
