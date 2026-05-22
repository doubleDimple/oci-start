package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * OCI 分片上传记录表
 * 用于断点续传、孤儿分片清理
 */
@Data
@Entity
@Table(name = "oci_multipart_upload_record")
public class OciMultipartUploadRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tenant_id", nullable = false)
    private Long tenantId;

    /** 云类型：1=OCI，2=GCP，3=Azure，4=AWS */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    /** OCI Tenancy OCID（冗余字段）：租户删除重导后可凭此找回新的 tenant_id */
    @Column(name = "tenancy_ocid", length = 512)
    private String tenancyOcid;

    @Column(name = "namespace", length = 128)
    private String namespace;

    @Column(name = "bucket_name", length = 256, nullable = false)
    private String bucketName;

    @Column(name = "object_name", length = 1024, nullable = false)
    private String objectName;

    /** OCI 返回的 uploadId */
    @Column(name = "upload_id", length = 512, nullable = false)
    private String uploadId;

    /** 文件总大小（字节） */
    @Column(name = "total_size")
    private Long totalSize;

    /** 分片大小（字节） */
    @Column(name = "chunk_size")
    private Long chunkSize;

    /** 总分片数 */
    @Column(name = "total_parts")
    private Integer totalParts;

    /** 已完成分片 JSON：[{"partNum":1,"etag":"xxx"},...]  */
    @Column(name = "completed_parts", columnDefinition = "TEXT")
    private String completedParts;

    /** uploading / completed / aborted */
    @Column(name = "status", length = 16)
    private String status = "uploading";

    @Column(name = "create_time")
    private LocalDateTime createTime;

    @Column(name = "update_time")
    private LocalDateTime updateTime;
}
