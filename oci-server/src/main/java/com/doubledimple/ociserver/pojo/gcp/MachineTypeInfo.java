package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

/**
 * GCP机器类型信息
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class MachineTypeInfo {
    private String kind;
    private String id;
    private String creationTimestamp;
    private String name;
    private String description;
    private Integer guestCpus;
    private Integer memoryMb;
    private String zone;
    private String selfLink;
    private Boolean isSharedCpu;
    private Integer maximumPersistentDisks;
    private Long maximumPersistentDisksSizeGb;
}
