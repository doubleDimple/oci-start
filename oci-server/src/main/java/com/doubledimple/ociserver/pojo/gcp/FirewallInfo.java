package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * 防火墙规则信息
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class FirewallInfo {
    private String kind;
    private String id;
    private String creationTimestamp;
    private String name;
    private String description;
    private String network;
    private String direction;
    private Integer priority;
    private List<String> sourceRanges;
    private List<String> destinationRanges;
    private List<String> sourceTags;
    private List<String> targetTags;
    private List<AllowedRule> allowed;
    private List<DeniedRule> denied;
    private Boolean disabled;
    private String selfLink;

    // 将 logConfig 从 Boolean 改为 LogConfig 对象
    private LogConfig logConfig;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class LogConfig {
        private Boolean enable;
        private String metadata;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class AllowedRule {
        private String IPProtocol;
        private List<String> ports;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class DeniedRule {
        private String IPProtocol;
        private List<String> ports;
    }
}
