package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

@Data
public class DeleteObjectRequest {

    @NotNull(message = "租户ID不能为空")
    private Long tenantId;

    @NotBlank(message = "命名空间不能为空")
    private String namespace;

    @NotBlank(message = "存储桶名称不能为空")
    private String bucketName;

    @NotBlank(message = "对象名称不能为空")
    private String objectName;
}
