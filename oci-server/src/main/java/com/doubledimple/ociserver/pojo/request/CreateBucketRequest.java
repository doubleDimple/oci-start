package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

@Data
public class CreateBucketRequest {

    @NotNull(message = "租户ID不能为空")
    private Long tenantId;

    @NotBlank(message = "存储桶名称不能为空")
    private String bucketName;

    /** NoPublicAccess | ObjectRead | ObjectReadWithoutList */
    private String publicAccessType = "NoPublicAccess";
}
