package com.doubledimple.ociserver.pojo.request;


import lombok.Data;

import javax.validation.constraints.NotNull;
import javax.validation.constraints.Size;

@Data
public class UpdateCustomNameRequest {

    @NotNull(message = "租户ID不能为空")
    private String tenantId;

    @Size(max = 100, message = "自定义名称长度不能超过100个字符")
    private String defName;

    private String accountCost;
}
