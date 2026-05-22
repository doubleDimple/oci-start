package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * 防火墙规则列表响应
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class FirewallListResponse {
    private String kind;
    private String id;
    private List<FirewallInfo> items;
    private String selfLink;
    private String nextPageToken;
}
