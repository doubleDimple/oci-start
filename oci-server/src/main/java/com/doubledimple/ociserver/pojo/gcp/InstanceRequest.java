package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Data;

import java.util.List;
import java.util.Map;

/**
 * GCP实例创建请求
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class InstanceRequest {
    private String name;
    private String machineType;
    //private MachineTypeConfig machineType;
    private List<AttachedDiskConfig> disks;
    private List<NetworkInterfaceConfig> networkInterfaces;
    private Map<String, String> labels;
    private MetadataConfig metadata;
    private List<ServiceAccountConfig> serviceAccounts;
    private TagsConfig tags;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class MachineTypeConfig {
        // 可以是完整的URL或者简单的类型名称
        private String machineType;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class AttachedDiskConfig {
        private Boolean boot;
        private Boolean autoDelete;
        private InitializeParamsConfig initializeParams;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        @JsonInclude(JsonInclude.Include.NON_NULL)
        public static class InitializeParamsConfig {
            private String sourceImage;
            private Integer diskSizeGb;
            private String diskType;
        }
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class NetworkInterfaceConfig {
        private String network;
        private String subnetwork;
        private List<AccessConfigConfig> accessConfigs;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        @JsonInclude(JsonInclude.Include.NON_NULL)
        public static class AccessConfigConfig {
            private String name;
            private String type;
        }
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class ServiceAccountConfig {
        private String email;
        private List<String> scopes;
    }

    /**
     * 元数据配置
     */
    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class MetadataConfig {
        private List<MetadataItemConfig> items;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        @JsonInclude(JsonInclude.Include.NON_NULL)
        public static class MetadataItemConfig {
            private String key;
            private String value;
        }
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class TagsConfig {
        private List<String> items;
        private String fingerprint;
    }
}
