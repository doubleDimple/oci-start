package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * GCP机器类型列表响应
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class MachineTypeListResponse {
    private String kind;
    private String id;
    private List<MachineTypeInfo> items;
    private String selfLink;
    private String nextPageToken;
}
