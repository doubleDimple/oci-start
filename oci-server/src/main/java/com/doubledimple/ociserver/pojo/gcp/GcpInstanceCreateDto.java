package com.doubledimple.ociserver.pojo.gcp;

import com.doubledimple.ocicommon.enums.gcp.GcpMachineTypeEnum;
import lombok.Data;

import javax.validation.constraints.Max;
import javax.validation.constraints.Min;
import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;
import javax.validation.constraints.Pattern;

/**
 * @version 1.0.0
 * @ClassName GcpInstanceCreateDto
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-12 12:47
 */
@Data
public class GcpInstanceCreateDto {

    /**
     * 租户ID
     */
    @NotNull(message = "租户ID不能为空")
    private Long tenantId;

    /**
     * 区域
     */
    @NotBlank(message = "区域不能为空")
    private String region;

    /**
     * 可用区
     */
    @NotBlank(message = "可用区不能为空")
    private String zone;

    /**
     * 机器类型
     */
    @NotBlank(message = "机器类型不能为空")
    private String machineType;

    /**
     * 是否为自定义机器类型
     */
    private Boolean isCustomMachine = false;

    /**
     * 自定义CPU数量（仅在isCustomMachine=true时使用）
     */
    private Integer customCpuCount;

    /**
     * 自定义内存大小MB（仅在isCustomMachine=true时使用）
     */
    private Integer customMemoryMb;

    /**
     * 源镜像URL
     */
    @NotBlank(message = "源镜像不能为空")
    private String sourceImage;

    /**
     * 实例名称
     */
    @NotBlank(message = "实例名称不能为空")
    @Pattern(regexp = "^[a-z]([-a-z0-9]*[a-z0-9])?$",
            message = "实例名称只能包含小写字母、数字和连字符，且必须以字母开头")
    private String instanceName;

    /**
     * 磁盘大小(GB)
     */
    @Min(value = 10, message = "磁盘大小不能小于10GB")
    @Max(value = 2048, message = "磁盘大小不能超过2048GB")
    private Integer diskSize;

    /**
     * 实例数量
     */
    @Min(value = 1, message = "实例数量不能小于1")
    @Max(value = 10, message = "实例数量不能超过10")
    private Integer instanceCount;

    /**
     * 网络标签（可选）
     */
    private String networkTags;

    /**
     * 是否允许HTTP流量
     */
    private Boolean allowHttp = false;

    /**
     * 是否允许HTTPS流量
     */
    private Boolean allowHttps = false;

    /**
     * 启动脚本（可选）
     */
    private String startupScript;

    /**
     * 服务账号邮箱（可选）
     */
    private String serviceAccountEmail;

    /**
     * 访问作用域
     */
    private String[] scopes = new String[]{"https://www.googleapis.com/auth/cloud-platform"};

    /**
     * 标签（可选）
     */
    private java.util.Map<String, String> labels;

    /**
     * 是否可抢占
     */
    private Boolean preemptible = false;

    /**
     * 自动删除磁盘
     */
    private Boolean autoDelete = true;

    /**
     * 磁盘类型
     */
    private String diskType = "pd-standard"; // pd-standard, pd-ssd, pd-balanced

    /**
     * 获取实际使用的机器类型（可能是预定义的或自定义的）
     */
    public String getActualMachineType() {
        if (Boolean.TRUE.equals(isCustomMachine) && customCpuCount != null && customMemoryMb != null) {
            return "custom-" + customCpuCount + "-" + customMemoryMb;
        }
        return machineType;
    }

    /**
     * 获取完整的机器类型URL
     */
    public String getMachineTypeUrl() {
        return String.format("zones/%s/machineTypes/%s", zone, getActualMachineType());
    }

    /**
     * 获取CPU数量（兼容预定义和自定义）
     */
    public Double getCpuCount() {
        if (Boolean.TRUE.equals(isCustomMachine) && customCpuCount != null) {
            return customCpuCount.doubleValue();
        }
        // 从预定义机器类型解析CPU数量
        return parseCpuFromMachineType(machineType);
    }

    /**
     * 获取内存大小GB（兼容预定义和自定义）
     */
    public Double getMemoryGb() {
        if (Boolean.TRUE.equals(isCustomMachine) && customMemoryMb != null) {
            return customMemoryMb / 1024.0;
        }
        // 从预定义机器类型解析内存大小
        return parseMemoryFromMachineType(machineType);
    }

    /**
     * 从机器类型名称解析CPU数量
     */
    private Double parseCpuFromMachineType(String machineType) {
        if (machineType == null) return 1.0;

        // 使用枚举获取CPU信息
        GcpMachineTypeEnum machineTypeEnum = GcpMachineTypeEnum.getByName(machineType);
        if (machineTypeEnum != null) {
            return machineTypeEnum.getVCpuCount();
        }

        // 如果枚举中找不到，尝试从名称中解析
        if (machineType.contains("micro")) return 0.25;
        if (machineType.contains("small")) return 0.5;
        if (machineType.contains("medium")) return 1.0;

        // 尝试从名称中提取数字
        String[] parts = machineType.split("-");
        for (String part : parts) {
            try {
                return Double.parseDouble(part);
            } catch (NumberFormatException ignored) {
                // 继续尝试下一个部分
            }
        }

        return 1.0; // 默认值
    }

    /**
     * 从机器类型名称解析内存大小
     */
    private Double parseMemoryFromMachineType(String machineType) {
        if (machineType == null) return 4.0;

        // 使用枚举获取内存信息
        GcpMachineTypeEnum machineTypeEnum = GcpMachineTypeEnum.getByName(machineType);
        if (machineTypeEnum != null) {
            return machineTypeEnum.getMemoryGb();
        }

        // 默认内存值映射
        if (machineType.contains("micro")) return 1.0;
        if (machineType.contains("small")) return 2.0;
        if (machineType.contains("medium")) return 4.0;

        return 4.0; // 默认值
    }

    /**
     * 获取完整的磁盘类型URL
     */
    public String getDiskTypeUrl() {
        return String.format("zones/%s/diskTypes/%s", zone, diskType);
    }

    /**
     * 获取网络URL
     */
    public String getNetworkUrl() {
        return "global/networks/default";
    }

    /**
     * 获取子网URL
     */
    public String getSubnetworkUrl() {
        return String.format("regions/%s/subnetworks/default", region);
    }

    /**
     * 验证自定义机器配置
     */
    public boolean isValidCustomMachineConfig() {
        if (!Boolean.TRUE.equals(isCustomMachine)) {
            return true; // 非自定义配置总是有效的
        }

        if (customCpuCount == null || customMemoryMb == null) {
            return false;
        }

        // 验证CPU规则：1或偶数
        if (customCpuCount > 1 && customCpuCount % 2 != 0) {
            return false;
        }

        // 验证内存规则：每个vCPU对应0.9-6.5GB内存
        double memoryGb = customMemoryMb / 1024.0;
        double minMemory = Math.max(0.9 * customCpuCount, 1.0);
        double maxMemory = 6.5 * customCpuCount;

        if (memoryGb < minMemory || memoryGb > maxMemory) {
            return false;
        }

        // 验证内存是0.25GB的倍数
        return (customMemoryMb % 256) == 0; // 256MB = 0.25GB
    }

    /**
     * 获取机器配置描述
     */
    public String getMachineConfigDescription() {
        if (Boolean.TRUE.equals(isCustomMachine)) {
            return String.format("自定义配置: %d vCPU, %.2f GB 内存",
                    customCpuCount, customMemoryMb / 1024.0);
        } else {
            return String.format("预定义类型: %s (%.1f vCPU, %.1f GB 内存)",
                    machineType, getCpuCount(), getMemoryGb());
        }
    }
}
