package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

@Data
public class UpdateOciUserStateRequest {
    @NotBlank(message = "租户 ID 不能为空")
    private String tenantId;
    @NotBlank(message = "用户 ID 不能为空")
    private String userId;
    @NotNull(message = "必须明确指定启用或禁用")
    private Boolean active;
}
