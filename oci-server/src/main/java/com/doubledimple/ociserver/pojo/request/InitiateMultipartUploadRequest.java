package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

@Data
public class InitiateMultipartUploadRequest {

    @NotNull(message = "租户ID不能为空")
    private Long tenantId;

    @NotBlank(message = "命名空间不能为空")
    private String namespace;

    @NotBlank(message = "存储桶名称不能为空")
    private String bucketName;

    @NotBlank(message = "对象名称不能为空")
    private String objectName;

    private String contentType;

    /** 文件总大小（字节），用于记录表 */
    private Long totalSize;

    /** 分片大小（字节），用于记录表 */
    private Long chunkSize;
}
