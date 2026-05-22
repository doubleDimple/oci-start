package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * GCP网络列表响应
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class NetworkListResponse {
    private String kind;
    private String id;
    private List<NetworkInfo> items;
    private String selfLink;
    private String nextPageToken;
}
