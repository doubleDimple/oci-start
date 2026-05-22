package com.doubledimple.ociserver.pojo.response;

import lombok.Builder;
import lombok.Data;

import java.util.List;

@Data
@Builder
public class MultipartUploadRecordVO {

    private Long id;
    private String uploadId;
    private String objectName;
    private String bucketName;
    private String namespace;
    private Long totalSize;
    private Long chunkSize;
    private Integer totalParts;
    private Integer completedPartCount;
    /** 已完成分片详情，前端用来跳过已上传的 part */
    private List<PartDetail> completedParts;
    private String createTime;

    @Data
    @Builder
    public static class PartDetail {
        private Integer partNum;
        private String etag;
    }
}
