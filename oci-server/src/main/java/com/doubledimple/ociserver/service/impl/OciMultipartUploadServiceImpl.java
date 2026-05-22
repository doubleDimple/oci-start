package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.OciMultipartUploadRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OciMultipartUploadRecordRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.response.MultipartUploadRecordVO;
import com.doubledimple.ociserver.service.OciMultipartUploadService;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@Slf4j
public class OciMultipartUploadServiceImpl implements OciMultipartUploadService {

    @Resource
    private OciMultipartUploadRecordRepository repository;

    @Resource
    private TenantRepository tenantRepository;

    private final ObjectMapper objectMapper = new ObjectMapper();
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @Override
    @Transactional
    public OciMultipartUploadRecord create(Long tenantId, String tenancyOcid, String namespace,
                                           String bucketName, String objectName, String uploadId,
                                           Long totalSize, Long chunkSize, Integer totalParts) {
        OciMultipartUploadRecord record = new OciMultipartUploadRecord();
        record.setTenantId(tenantId);
        record.setTenancyOcid(tenancyOcid);
        record.setNamespace(namespace);
        record.setBucketName(bucketName);
        record.setObjectName(objectName);
        record.setUploadId(uploadId);
        record.setTotalSize(totalSize);
        record.setChunkSize(chunkSize);
        record.setTotalParts(totalParts);
        record.setCompletedParts("[]");
        record.setStatus("uploading");
        record.setCreateTime(LocalDateTime.now());
        record.setUpdateTime(LocalDateTime.now());
        return repository.save(record);
    }

    @Override
    @Transactional
    public void appendCompletedPart(String uploadId, int partNum, String etag) {
        repository.findByUploadId(uploadId).ifPresent(record -> {
            try {
                List<PartEntry> parts = parseCompletedParts(record.getCompletedParts());
                // avoid duplicate
                parts.removeIf(p -> p.partNum == partNum);
                parts.add(new PartEntry(partNum, etag));
                String json = objectMapper.writeValueAsString(parts);
                repository.updateCompletedParts(uploadId, json, LocalDateTime.now());
            } catch (Exception e) {
                log.error("更新已完成分片失败 uploadId={}", uploadId, e);
            }
        });
    }

    @Override
    @Transactional
    public void markCompleted(String uploadId) {
        repository.updateStatus(uploadId, "completed", LocalDateTime.now());
    }

    @Override
    @Transactional
    public void markAborted(String uploadId) {
        repository.updateStatus(uploadId, "aborted", LocalDateTime.now());
    }

    @Override
    public List<MultipartUploadRecordVO> listResumeableUploads(Long tenantId, String bucketName) {
        List<OciMultipartUploadRecord> records =
                repository.findByTenantIdAndBucketNameAndStatus(tenantId, bucketName, "uploading");
        return records.stream().map(r -> {
            List<PartEntry> parts = parseCompletedParts(r.getCompletedParts());
            List<MultipartUploadRecordVO.PartDetail> partDetails = parts.stream()
                    .map(p -> MultipartUploadRecordVO.PartDetail.builder()
                            .partNum(p.partNum).etag(p.etag).build())
                    .collect(Collectors.toList());
            return MultipartUploadRecordVO.builder()
                    .id(r.getId())
                    .uploadId(r.getUploadId())
                    .objectName(r.getObjectName())
                    .bucketName(r.getBucketName())
                    .namespace(r.getNamespace())
                    .totalSize(r.getTotalSize())
                    .chunkSize(r.getChunkSize())
                    .totalParts(r.getTotalParts())
                    .completedPartCount(parts.size())
                    .completedParts(partDetails)
                    .createTime(r.getCreateTime() != null ? r.getCreateTime().format(FMT) : null)
                    .build();
        }).collect(Collectors.toList());
    }

    @Override
    public OciMultipartUploadRecord getByUploadId(String uploadId) {
        Optional<OciMultipartUploadRecord> opt = repository.findByUploadId(uploadId);
        return opt.orElse(null);
    }

    @Override
    public List<OciMultipartUploadRecord> findActiveUploads(Long tenantId, String bucketName, String objectName) {
        return repository.findByTenantIdAndBucketNameAndObjectNameAndStatus(tenantId, bucketName, objectName, "uploading");
    }

    @Override
    public Tenant resolveTenant(OciMultipartUploadRecord record) {
        // 1. 优先用 tenant_id 直接查
        Tenant tenant = tenantRepository.findById(record.getTenantId()).orElse(null);
        if (tenant != null) {
            return tenant;
        }
        // 2. tenant_id 失效（租户被删除重导）→ 用 tenancy_ocid 回退，只查父记录
        if (record.getTenancyOcid() == null || StringUtils.isBlank(record.getTenancyOcid())) {
            log.warn("租户 id={} 不存在且无 tenancy_ocid，无法回退查询", record.getTenantId());
            return null;
        }
        // 只查父记录（parenId IS NULL OR 0），避免子域记录干扰（同一 OCID 有多条）
        List<Tenant> candidates = tenantRepository.findParentByTenancyOcid(record.getTenancyOcid());
        if (candidates.isEmpty()) {
            log.warn("通过 tenancy_ocid={} 也未找到父租户记录", record.getTenancyOcid());
            return null;
        }
        tenant = candidates.get(0);
        // 3. 顺手修正记录里的 tenant_id，下次直接命中
        repository.fixTenantId(record.getTenancyOcid(), tenant.getId(), LocalDateTime.now());
        log.info("租户 tenancy_ocid={} 已重导，tenant_id 从 {} 修正为 {}",
                record.getTenancyOcid(), record.getTenantId(), tenant.getId());
        return tenant;
    }

    // ── helper ──────────────────────────────────────────────────
    private List<PartEntry> parseCompletedParts(String json) {
        try {
            if (StringUtils.isBlank( json)) return new ArrayList<>();
            return objectMapper.readValue(json, new TypeReference<List<PartEntry>>() {});
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    private static class PartEntry {
        public int partNum;
        public String etag;
        public PartEntry() {}
        public PartEntry(int partNum, String etag) { this.partNum = partNum; this.etag = etag; }
    }
}
