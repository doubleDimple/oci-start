package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * GCP镜像列表响应
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class ImageListResponse {
    private String kind;
    private String id;
    private List<ImageInfo> items;
    private String selfLink;
    private String nextPageToken;
}
