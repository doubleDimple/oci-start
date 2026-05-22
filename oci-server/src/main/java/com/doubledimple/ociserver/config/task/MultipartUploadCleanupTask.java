package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.OciMultipartUploadRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OciMultipartUploadRecordRepository;
import com.doubledimple.ociserver.service.OciMultipartUploadService;
import com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 清理超时未完成的分片上传记录（由 Quartz Job 调用）
 * 超过 24 小时仍处于 uploading 状态的记录，调用 OCI abort 接口清理残留分片
 */
@Component
@Slf4j
public class MultipartUploadCleanupTask {

    private static final long STALE_HOURS = 24;

    @Resource
    private OciMultipartUploadRecordRepository recordRepository;

    @Resource
    private OciMultipartUploadService multipartUploadService;

    @Transactional
    public void cleanStaleUploads() {
        LocalDateTime threshold = LocalDateTime.now().minusHours(STALE_HOURS);
        List<OciMultipartUploadRecord> staleRecords = recordRepository.findStaleUploads(threshold);

        if (staleRecords.isEmpty()) {
            return;
        }
        log.info("发现 {} 条超时分片上传记录，开始清理", staleRecords.size());

        for (OciMultipartUploadRecord record : staleRecords) {
            try {
                // 使用带回退的租户查询（支持租户删除重导的场景）
                Tenant tenant = multipartUploadService.resolveTenant(record);
                if (tenant != null) {
                    boolean aborted = OciObjectStorageUtil.abortMultipartUpload(
                            tenant,
                            record.getNamespace(),
                            record.getBucketName(),
                            record.getObjectName(),
                            record.getUploadId());
                    if (aborted) {
                        log.info("已清理孤儿分片 uploadId={} object={}", record.getUploadId(), record.getObjectName());
                    }
                } else {
                    log.warn("无法找到租户，跳过 abort，仅标记为 aborted uploadId={}", record.getUploadId());
                }
                recordRepository.updateStatus(record.getUploadId(), "aborted", LocalDateTime.now());
            } catch (Exception e) {
                log.error("清理分片上传失败 uploadId={}", record.getUploadId(), e);
            }
        }
        log.info("分片上传清理完成，共处理 {} 条", staleRecords.size());
    }
}
