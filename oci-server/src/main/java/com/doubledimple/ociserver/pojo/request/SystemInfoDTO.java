package com.doubledimple.ociserver.pojo.request;

import lombok.Builder;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName SystemInfoDTO
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-29 10:13
 */
@Data
@Builder
public class SystemInfoDTO {
    private String osName;            // 操作系统名称
    private String osArch;            // 系统架构
    private String osVersion;         // 系统版本
    private String hostname;          // 主机名
    private String cpuModel;          // CPU型号
    private String cpuVendor;         // CPU厂商
    private int cpuPhysicalCount;     // CPU物理核心数
    private int cpuLogicalCount;      // CPU逻辑核心数
    private double cpuFrequency;      // CPU频率（GHz）
    private long totalMemory;         // 总内存（GB）
    private long totalSwap;           // 总交换空间（GB）
    private String[] ipAddresses;     // IP地址列表
    private String[] networkInterfaces; // 网络接口列表
}
