package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.OciMultipartUploadRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.pojo.response.MultipartUploadRecordVO;
import java.util.List;

public interface OciMultipartUploadService {

    /** 创建上传记录（含 tenancyOcid 冗余字段） */
    OciMultipartUploadRecord create(Long tenantId, String tenancyOcid, String namespace,
                                    String bucketName, String objectName, String uploadId,
                                    Long totalSize, Long chunkSize, Integer totalParts);

    /**
     * 根据记录找回租户：优先用 tenant_id，找不到时用 tenancy_ocid 回退查询，
     * 找到后自动修正记录中的 tenant_id。
     */
    Tenant resolveTenant(OciMultipartUploadRecord record);

    /** 追加已完成分片（partNum + etag），并更新 DB */
    void appendCompletedPart(String uploadId, int partNum, String etag);

    /** 标记为已完成 */
    void markCompleted(String uploadId);

    /** 标记为已取消 */
    void markAborted(String uploadId);

    /** 查询租户某个桶下进行中的上传（用于断点续传列表） */
    List<MultipartUploadRecordVO> listResumeableUploads(Long tenantId, String bucketName);

    /** 按 uploadId 查询 */
    OciMultipartUploadRecord getByUploadId(String uploadId);

    /** 查询同一文件的进行中记录（用于 initiate 去重） */
    List<OciMultipartUploadRecord> findActiveUploads(Long tenantId, String bucketName, String objectName);
}
