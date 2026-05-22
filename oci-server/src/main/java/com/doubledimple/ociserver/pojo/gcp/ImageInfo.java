package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;
import java.util.Map;

/**
 * GCP镜像信息
 */
/**
 * GCP镜像信息
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class ImageInfo {
    private String kind;
    private String id;
    private String creationTimestamp;
    private String name;
    private String description;
    private String sourceType;
    private RawDisk rawDisk;
    private String status;
    private Deprecated deprecated;  // 修改为 Deprecated 对象
    private String family;
    private Map<String, String> labels;
    private String labelFingerprint;
    private Long diskSizeGb;
    private Long archiveSizeBytes;  // 添加的字段
    private String sourceDisk;
    private String sourceDiskId;
    private String sourceImage;
    private String sourceImageId;
    private String sourceSnapshot;
    private String sourceSnapshotId;
    private String selfLink;
    private List<String> licenseCodes;
    private String architecture;
    private List<String> storageLocations;  // 添加的字段
    private Boolean enableConfidentialCompute;  // 添加的字段

    /**
     * 原始磁盘信息
     */
    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class RawDisk {
        private String containerType;
        private String source;
        private String sha1Checksum;
    }

    /**
     * 弃用信息
     */
    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Deprecated {
        private String state;
        private String replacement;
        private String deprecated;  // 日期字符串
        private String obsolete;    // 日期字符串
        private String deleted;     // 日期字符串
    }
}
