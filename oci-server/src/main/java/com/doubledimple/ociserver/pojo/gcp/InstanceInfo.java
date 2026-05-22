package com.doubledimple.ociserver.pojo.gcp;

import com.doubledimple.dao.entity.OtherBootInstance;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * GCP实例信息
 */
/**
 * GCP实例信息
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class InstanceInfo {
    private String id;
    private String name;
    private String description;
    private String status;
    private String machineType;
    private String zone;
    private List<NetworkInterface> networkInterfaces;
    private List<Disk> disks;
    private Map<String, String> labels;
    private Metadata metadata;  // 修正：改为Metadata对象
    private List<ServiceAccount> serviceAccounts;
    private String cpuPlatform;
    private Tags tags;
    private String creationTimestamp;
    private String selfLink;

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class NetworkInterface {
        private String name;
        private String network;
        private String subnetwork;
        private String networkIP;
        private List<AccessConfig> accessConfigs;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class AccessConfig {
            private String name;
            private String type;
            private String natIP;
            private String networkTier;  // 新增
        }
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Disk {
        private String kind;
        private String type;
        private String mode;
        private String source;
        private String deviceName;
        private Integer index;
        private Boolean boot;
        private Boolean autoDelete;
        private String diskSizeGb;
        private List<String> licenses;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ServiceAccount {
        private String email;
        private List<String> scopes;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Tags {
        private List<String> items;
        private String fingerprint;
    }

    // 新增：Metadata结构
    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Metadata {
        private String kind;
        private String fingerprint;
        private List<MetadataItem> items;

        @Data
        @JsonIgnoreProperties(ignoreUnknown = true)
        public static class MetadataItem {
            private String key;
            private String value;
        }
    }

    // 便捷方法：获取外部IP
    public String getExternalIP() {
        if (networkInterfaces != null && !networkInterfaces.isEmpty()) {
            NetworkInterface nic = networkInterfaces.get(0);
            if (nic.getAccessConfigs() != null && !nic.getAccessConfigs().isEmpty()) {
                return nic.getAccessConfigs().get(0).getNatIP();
            }
        }
        return null;
    }

    // 便捷方法：获取内部IP
    public String getInternalIP() {
        if (networkInterfaces != null && !networkInterfaces.isEmpty()) {
            return networkInterfaces.get(0).getNetworkIP();
        }
        return null;
    }

    // 便捷方法：获取标签列表
    public List<String> getTagItems() {
        if (tags != null && tags.getItems() != null) {
            return tags.getItems();
        }
        return new ArrayList<>();
    }

    // 便捷方法：获取元数据值
    public String getMetadataValue(String key) {
        if (metadata != null && metadata.getItems() != null) {
            return metadata.getItems().stream()
                    .filter(item -> key.equals(item.getKey()))
                    .map(Metadata.MetadataItem::getValue)
                    .findFirst()
                    .orElse(null);
        }
        return null;
    }

    public static OtherBootInstance convertToOtherBootInstance(InstanceInfo instanceInfo,
                                                               Long tenantId,
                                                               String bootId,
                                                               String rootPassword) {
        if (instanceInfo == null) {
            return null;
        }

        OtherBootInstance otherBootInstance = new OtherBootInstance();

        // 基本信息
        otherBootInstance.setBootId(bootId);
        otherBootInstance.setTenantId(tenantId);
        otherBootInstance.setInstanceName(instanceInfo.getName());
        otherBootInstance.setRootPassword(rootPassword);

        // 从GCP zone URL中提取zone名称
        String zone = extractZoneFromUrl(instanceInfo.getZone());
        otherBootInstance.setZone(zone);

        // 设置公网IP
        String externalIP = instanceInfo.getExternalIP();
        otherBootInstance.setPublicIp(externalIP != null ? externalIP : "0.0.0.0");

        // 从机器类型中解析配置信息
        MachineTypeInfo machineTypeInfo = parseMachineType(instanceInfo.getMachineType());
        otherBootInstance.setOcpu(machineTypeInfo.getCpu());
        otherBootInstance.setMemory(machineTypeInfo.getMemory());

        // 从磁盘信息中获取磁盘大小
        int diskSize = parseDiskSize(instanceInfo.getDisks());
        otherBootInstance.setDisk(diskSize);

        // 设置实例数量（单个实例）
        otherBootInstance.setInstanceCount(1);

        // 根据GCP状态映射到OtherBootInstance状态
        int status = mapGcpStatusToOtherBootStatus(instanceInfo.getStatus());
        otherBootInstance.setStatus(status);

        // 设置架构类型
        String architecture = extractArchitecture(instanceInfo);
        otherBootInstance.setArchitecture(architecture);

        // 设置云厂商类型为GCP
        otherBootInstance.setCloudType(2); // 假设2代表GCP

        // 设置备注信息
        String remark = buildRemark(instanceInfo);
        otherBootInstance.setRemark(remark);

        return otherBootInstance;
    }

    /**
     * 从GCP zone URL中提取zone名称
     * 例如: "https://www.googleapis.com/compute/v1/projects/xxx/zones/asia-east1-b" -> "asia-east1-b"
     */
    private static String extractZoneFromUrl(String zoneUrl) {
        if (zoneUrl == null || zoneUrl.isEmpty()) {
            return "";
        }

        String[] parts = zoneUrl.split("/");
        return parts.length > 0 ? parts[parts.length - 1] : "";
    }

    /**
     * 解析机器类型信息
     * 例如: "e2-micro" -> CPU: 1, Memory: 1GB
     */
    private static MachineTypeInfo parseMachineType(String machineTypeUrl) {
        MachineTypeInfo info = new MachineTypeInfo();

        if (machineTypeUrl == null || machineTypeUrl.isEmpty()) {
            info.setCpu(1);
            info.setMemory(1);
            return info;
        }

        // 从URL中提取机器类型名称
        String machineType = machineTypeUrl.substring(machineTypeUrl.lastIndexOf("/") + 1);

        // 根据GCP机器类型映射CPU和内存
        switch (machineType.toLowerCase()) {
            case "e2-micro":
                info.setCpu(1);
                info.setMemory(1); // 1GB
                break;
            case "e2-small":
                info.setCpu(1);
                info.setMemory(2); // 2GB
                break;
            case "e2-medium":
                info.setCpu(1);
                info.setMemory(4); // 4GB
                break;
            case "e2-standard-2":
                info.setCpu(2);
                info.setMemory(8); // 8GB
                break;
            case "e2-standard-4":
                info.setCpu(4);
                info.setMemory(16); // 16GB
                break;
            case "e2-standard-8":
                info.setCpu(8);
                info.setMemory(32); // 32GB
                break;
            case "e2-standard-16":
                info.setCpu(16);
                info.setMemory(64); // 64GB
                break;
            default:
                // 默认配置
                info.setCpu(1);
                info.setMemory(1);
                break;
        }

        return info;
    }

    /**
     * 解析磁盘大小
     */
    private static int parseDiskSize(List<Disk> disks) {
        if (disks == null || disks.isEmpty()) {
            return 20; // 默认20GB
        }

        // 获取启动磁盘的大小
        for (Disk disk : disks) {
            if (Boolean.TRUE.equals(disk.getBoot()) && disk.getDiskSizeGb() != null) {
                try {
                    return Integer.parseInt(disk.getDiskSizeGb());
                } catch (NumberFormatException e) {
                    // 如果解析失败，继续查找其他磁盘
                }
            }
        }

        // 如果没有找到启动磁盘，使用第一个磁盘的大小
        Disk firstDisk = disks.get(0);
        if (firstDisk.getDiskSizeGb() != null) {
            try {
                return Integer.parseInt(firstDisk.getDiskSizeGb());
            } catch (NumberFormatException e) {
                return 20; // 解析失败时的默认值
            }
        }

        return 20; // 默认20GB
    }

    /**
     * 映射GCP状态到OtherBootInstance状态
     * GCP状态: PROVISIONING, STAGING, RUNNING, STOPPING, STOPPED, SUSPENDING, SUSPENDED, TERMINATED
     * OtherBootInstance状态: 0-未开机, 1-开机中, 2-已开机
     */
    private static int mapGcpStatusToOtherBootStatus(String gcpStatus) {
        if (gcpStatus == null) {
            return 0;
        }

        switch (gcpStatus.toUpperCase()) {
            case "RUNNING":
                return 2; // 已开机
            case "PROVISIONING":
            case "STAGING":
                return 1; // 开机中
            case "STOPPED":
            case "TERMINATED":
            case "SUSPENDED":
                return 0; // 未开机
            case "STOPPING":
            case "SUSPENDING":
                return 1; // 状态变化中，视为开机中
            default:
                return 0; // 未知状态默认为未开机
        }
    }

    /**
     * 提取架构信息
     */
    private static String extractArchitecture(InstanceInfo instanceInfo) {

        // 从机器类型推断架构
        if (instanceInfo.getMachineType() != null) {
            String machineType = instanceInfo.getMachineType().toLowerCase();
            if (machineType.contains("arm") || machineType.contains("t2a")) {
                return "arm64";
            }
        }

        return "x86_64"; // 默认架构
    }

    /**
     * 构建备注信息
     */
    private static String buildRemark(InstanceInfo instanceInfo) {
        StringBuilder remark = new StringBuilder();

        // 添加CPU平台信息
        if (instanceInfo.getCpuPlatform() != null) {
            remark.append("CPU平台: ").append(instanceInfo.getCpuPlatform()).append("; ");
        }

        // 添加标签信息
        List<String> tags = instanceInfo.getTagItems();
        if (!tags.isEmpty()) {
            remark.append("标签: ").append(String.join(", ", tags)).append("; ");
        }

        // 添加内网IP信息
        String internalIP = instanceInfo.getInternalIP();
        if (internalIP != null) {
            remark.append("内网IP: ").append(internalIP).append("; ");
        }

        // 添加创建时间
        if (instanceInfo.getCreationTimestamp() != null) {
            remark.append("创建时间: ").append(instanceInfo.getCreationTimestamp());
        }

        return remark.toString();
    }

    /**
     * 机器类型信息辅助类
     */
    private static class MachineTypeInfo {
        private int cpu;
        private int memory;

        public int getCpu() {
            return cpu;
        }

        public void setCpu(int cpu) {
            this.cpu = cpu;
        }

        public int getMemory() {
            return memory;
        }

        public void setMemory(int memory) {
            this.memory = memory;
        }
    }
}
