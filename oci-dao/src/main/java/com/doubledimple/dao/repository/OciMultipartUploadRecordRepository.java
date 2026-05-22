package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.OciMultipartUploadRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface OciMultipartUploadRecordRepository extends JpaRepository<OciMultipartUploadRecord, Long> {

    /** 查询租户下指定桶中进行中的上传记录 */
    List<OciMultipartUploadRecord> findByTenantIdAndBucketNameAndStatus(
            Long tenantId, String bucketName, String status);

    /** 按 uploadId 查询 */
    Optional<OciMultipartUploadRecord> findByUploadId(String uploadId);

    /** 查询同一文件的进行中记录（去重用） */
    List<OciMultipartUploadRecord> findByTenantIdAndBucketNameAndObjectNameAndStatus(
            Long tenantId, String bucketName, String objectName, String status);

    /** 查询所有超时的进行中记录（用于定时清理） */
    @Query("SELECT r FROM OciMultipartUploadRecord r WHERE r.status = 'uploading' AND r.updateTime < :threshold")
    List<OciMultipartUploadRecord> findStaleUploads(@Param("threshold") LocalDateTime threshold);

    /** 修正 tenant_id（租户删除重导后同步新主键） */
    @Modifying
    @Transactional
    @Query("UPDATE OciMultipartUploadRecord r SET r.tenantId = :newTenantId, r.updateTime = :now WHERE r.tenancyOcid = :tenancyOcid AND r.tenantId != :newTenantId")
    int fixTenantId(@Param("tenancyOcid") String tenancyOcid,
                    @Param("newTenantId") Long newTenantId,
                    @Param("now") LocalDateTime now);

    /** 更新状态 */
    @Modifying
    @Transactional
    @Query("UPDATE OciMultipartUploadRecord r SET r.status = :status, r.updateTime = :now WHERE r.uploadId = :uploadId")
    int updateStatus(@Param("uploadId") String uploadId,
                     @Param("status") String status,
                     @Param("now") LocalDateTime now);

    /** 更新已完成分片列表 */
    @Modifying
    @Transactional
    @Query("UPDATE OciMultipartUploadRecord r SET r.completedParts = :completedParts, r.updateTime = :now WHERE r.uploadId = :uploadId")
    int updateCompletedParts(@Param("uploadId") String uploadId,
                              @Param("completedParts") String completedParts,
                              @Param("now") LocalDateTime now);

    /** 按租户ID删除所有分片上传记录（租户删除时联动清理） */
    @Modifying
    @Transactional
    @Query("DELETE FROM OciMultipartUploadRecord r WHERE r.tenantId = :tenantId")
    int deleteByTenantId(@Param("tenantId") Long tenantId);
}
