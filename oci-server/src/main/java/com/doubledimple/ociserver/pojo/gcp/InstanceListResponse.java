package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * GCP实例列表响应
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class InstanceListResponse {
    private String kind;
    private String id;
    private List<InstanceInfo> items;
    private String selfLink;
    private String nextPageToken;
}
