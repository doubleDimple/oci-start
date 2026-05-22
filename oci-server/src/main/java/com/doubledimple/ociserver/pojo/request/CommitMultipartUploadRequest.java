package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotEmpty;
import javax.validation.constraints.NotNull;
import java.util.List;

@Data
public class CommitMultipartUploadRequest {

    @NotNull(message = "租户ID不能为空")
    private Long tenantId;

    @NotBlank(message = "命名空间不能为空")
    private String namespace;

    @NotBlank(message = "存储桶名称不能为空")
    private String bucketName;

    @NotBlank(message = "对象名称不能为空")
    private String objectName;

    @NotBlank(message = "uploadId不能为空")
    private String uploadId;

    @NotEmpty(message = "分片列表不能为空")
    private List<PartSummary> parts;

    @Data
    public static class PartSummary {
        private Integer partNum;
        private String etag;
    }
}
