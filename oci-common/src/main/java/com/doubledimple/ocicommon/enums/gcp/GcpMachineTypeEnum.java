package com.doubledimple.ocicommon.enums.gcp;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * GCP 机器类型枚举
 * 包含常用的 GCP 虚拟机机器类型
 */
public enum GcpMachineTypeEnum {

    // 共享核心系列 - 经济型
    E2_MICRO("e2-micro", "共享核心 - 微型", 0.25, 1, "e2", "shared-core"),
    E2_SMALL("e2-small", "共享核心 - 小型", 0.5, 2, "e2", "shared-core"),
    E2_MEDIUM("e2-medium", "共享核心 - 中型", 1, 4, "e2", "shared-core"),

    // E2 系列 - 经济型通用机器
    E2_STANDARD_2("e2-standard-2", "经济型 - 2核", 2, 8, "e2", "standard"),
    E2_STANDARD_4("e2-standard-4", "经济型 - 4核", 4, 16, "e2", "standard"),
    E2_STANDARD_8("e2-standard-8", "经济型 - 8核", 8, 32, "e2", "standard"),
    E2_STANDARD_16("e2-standard-16", "经济型 - 16核", 16, 64, "e2", "standard"),
    E2_STANDARD_32("e2-standard-32", "经济型 - 32核", 32, 128, "e2", "standard"),

    // E2 高内存系列
    E2_HIGHMEM_2("e2-highmem-2", "经济型高内存 - 2核", 2, 16, "e2", "highmem"),
    E2_HIGHMEM_4("e2-highmem-4", "经济型高内存 - 4核", 4, 32, "e2", "highmem"),
    E2_HIGHMEM_8("e2-highmem-8", "经济型高内存 - 8核", 8, 64, "e2", "highmem"),
    E2_HIGHMEM_16("e2-highmem-16", "经济型高内存 - 16核", 16, 128, "e2", "highmem"),

    // E2 高CPU系列
    E2_HIGHCPU_2("e2-highcpu-2", "经济型高CPU - 2核", 2, 2, "e2", "highcpu"),
    E2_HIGHCPU_4("e2-highcpu-4", "经济型高CPU - 4核", 4, 4, "e2", "highcpu"),
    E2_HIGHCPU_8("e2-highcpu-8", "经济型高CPU - 8核", 8, 8, "e2", "highcpu"),
    E2_HIGHCPU_16("e2-highcpu-16", "经济型高CPU - 16核", 16, 16, "e2", "highcpu"),

    // N1 系列 - 第一代通用机器
    N1_STANDARD_1("n1-standard-1", "通用型 - 1核", 1, 3.75, "n1", "standard"),
    N1_STANDARD_2("n1-standard-2", "通用型 - 2核", 2, 7.5, "n1", "standard"),
    N1_STANDARD_4("n1-standard-4", "通用型 - 4核", 4, 15, "n1", "standard"),
    N1_STANDARD_8("n1-standard-8", "通用型 - 8核", 8, 30, "n1", "standard"),
    N1_STANDARD_16("n1-standard-16", "通用型 - 16核", 16, 60, "n1", "standard"),
    N1_STANDARD_32("n1-standard-32", "通用型 - 32核", 32, 120, "n1", "standard"),
    N1_STANDARD_64("n1-standard-64", "通用型 - 64核", 64, 240, "n1", "standard"),

    // N1 高内存系列
    N1_HIGHMEM_2("n1-highmem-2", "高内存型 - 2核", 2, 13, "n1", "highmem"),
    N1_HIGHMEM_4("n1-highmem-4", "高内存型 - 4核", 4, 26, "n1", "highmem"),
    N1_HIGHMEM_8("n1-highmem-8", "高内存型 - 8核", 8, 52, "n1", "highmem"),
    N1_HIGHMEM_16("n1-highmem-16", "高内存型 - 16核", 16, 104, "n1", "highmem"),

    // N1 高CPU系列
    N1_HIGHCPU_2("n1-highcpu-2", "高CPU型 - 2核", 2, 1.8, "n1", "highcpu"),
    N1_HIGHCPU_4("n1-highcpu-4", "高CPU型 - 4核", 4, 3.6, "n1", "highcpu"),
    N1_HIGHCPU_8("n1-highcpu-8", "高CPU型 - 8核", 8, 7.2, "n1", "highcpu"),
    N1_HIGHCPU_16("n1-highcpu-16", "高CPU型 - 16核", 16, 14.4, "n1", "highcpu"),

    // N2 系列 - 第二代通用机器
    N2_STANDARD_2("n2-standard-2", "第二代通用型 - 2核", 2, 8, "n2", "standard"),
    N2_STANDARD_4("n2-standard-4", "第二代通用型 - 4核", 4, 16, "n2", "standard"),
    N2_STANDARD_8("n2-standard-8", "第二代通用型 - 8核", 8, 32, "n2", "standard"),
    N2_STANDARD_16("n2-standard-16", "第二代通用型 - 16核", 16, 64, "n2", "standard"),
    N2_STANDARD_32("n2-standard-32", "第二代通用型 - 32核", 32, 128, "n2", "standard"),

    // C2 系列 - 计算优化型
    C2_STANDARD_4("c2-standard-4", "计算优化型 - 4核", 4, 16, "c2", "standard"),
    C2_STANDARD_8("c2-standard-8", "计算优化型 - 8核", 8, 32, "c2", "standard"),
    C2_STANDARD_16("c2-standard-16", "计算优化型 - 16核", 16, 64, "c2", "standard"),
    C2_STANDARD_30("c2-standard-30", "计算优化型 - 30核", 30, 120, "c2", "standard"),
    C2_STANDARD_60("c2-standard-60", "计算优化型 - 60核", 60, 240, "c2", "standard");

    // 机器类型名称
    private final String name;
    // 显示名称
    private final String displayName;
    // vCPU数量
    private final double vCpuCount;
    // 内存大小(GB)
    private final double memoryGb;
    // 系列名称
    private final String series;
    // 类型
    private final String type;

    // 按名称的映射
    private static final Map<String, GcpMachineTypeEnum> NAME_MAP;
    // 按系列和类型的映射
    private static final Map<String, List<GcpMachineTypeEnum>> SERIES_TYPE_MAP;

    static {
        NAME_MAP = Arrays.stream(values())
                .collect(Collectors.toMap(GcpMachineTypeEnum::getName, mt -> mt));

        SERIES_TYPE_MAP = new HashMap<>();
        for (GcpMachineTypeEnum mt : values()) {
            String key = mt.getSeries() + "-" + mt.getType();
            List<GcpMachineTypeEnum> list = SERIES_TYPE_MAP.computeIfAbsent(key, k -> new java.util.ArrayList<>());
            list.add(mt);
        }
    }

    /**
     * 构造函数
     */
    GcpMachineTypeEnum(String name, String displayName, double vCpuCount, double memoryGb, String series, String type) {
        this.name = name;
        this.displayName = displayName;
        this.vCpuCount = vCpuCount;
        this.memoryGb = memoryGb;
        this.series = series;
        this.type = type;
    }

    /**
     * 获取机器类型名称
     */
    public String getName() {
        return name;
    }

    /**
     * 获取显示名称
     */
    public String getDisplayName() {
        return displayName;
    }

    /**
     * 获取vCPU数量
     */
    public double getVCpuCount() {
        return vCpuCount;
    }

    /**
     * 获取内存大小(GB)
     */
    public double getMemoryGb() {
        return memoryGb;
    }

    /**
     * 获取系列名称
     */
    public String getSeries() {
        return series;
    }

    /**
     * 获取类型
     */
    public String getType() {
        return type;
    }

    /**
     * 获取机器类型的完整URL
     *
     * @param zone 区域名称
     * @return 完整URL
     */
    public String getFullUrl(String zone) {
        return "zones/" + zone + "/machineTypes/" + name;
    }

    /**
     * 根据名称获取机器类型枚举
     *
     * @param name 机器类型名称
     * @return 机器类型枚举
     */
    public static GcpMachineTypeEnum getByName(String name) {
        return NAME_MAP.get(name);
    }

    /**
     * 根据系列和类型获取机器类型列表
     *
     * @param series 系列名称
     * @param type 类型
     * @return 机器类型列表
     */
    public static List<GcpMachineTypeEnum> getBySeriesAndType(String series, String type) {
        return SERIES_TYPE_MAP.getOrDefault(series + "-" + type, new java.util.ArrayList<>());
    }

    /**
     * 获取所有共享核心机器类型
     */
    public static List<GcpMachineTypeEnum> getSharedCoreMachineTypes() {
        return getBySeriesAndType("e2", "shared-core");
    }

    /**
     * 获取所有经济型标准机器类型
     */
    public static List<GcpMachineTypeEnum> getEconomyStandardMachineTypes() {
        return getBySeriesAndType("e2", "standard");
    }

    /**
     * 获取所有通用型机器类型
     */
    public static List<GcpMachineTypeEnum> getGeneralPurposeMachineTypes() {
        List<GcpMachineTypeEnum> result = new java.util.ArrayList<>();
        result.addAll(getBySeriesAndType("n1", "standard"));
        result.addAll(getBySeriesAndType("n2", "standard"));
        return result;
    }

    /**
     * 获取所有高内存型机器类型
     */
    public static List<GcpMachineTypeEnum> getHighMemoryMachineTypes() {
        List<GcpMachineTypeEnum> result = new java.util.ArrayList<>();
        result.addAll(getBySeriesAndType("n1", "highmem"));
        result.addAll(getBySeriesAndType("e2", "highmem"));
        return result;
    }

    /**
     * 获取所有高CPU型机器类型
     */
    public static List<GcpMachineTypeEnum> getHighCpuMachineTypes() {
        List<GcpMachineTypeEnum> result = new java.util.ArrayList<>();
        result.addAll(getBySeriesAndType("n1", "highcpu"));
        result.addAll(getBySeriesAndType("e2", "highcpu"));
        return result;
    }

    /**
     * 获取所有计算优化型机器类型
     */
    public static List<GcpMachineTypeEnum> getComputeOptimizedMachineTypes() {
        return getBySeriesAndType("c2", "standard");
    }

    /**
     * 获取按vCPU排序的所有机器类型
     */
    public static List<GcpMachineTypeEnum> getAllSortedByVCpu() {
        return Arrays.stream(values())
                .sorted((a, b) -> Double.compare(a.getVCpuCount(), b.getVCpuCount()))
                .collect(Collectors.toList());
    }

    /**
     * 获取按内存排序的所有机器类型
     */
    public static List<GcpMachineTypeEnum> getAllSortedByMemory() {
        return Arrays.stream(values())
                .sorted((a, b) -> Double.compare(a.getMemoryGb(), b.getMemoryGb()))
                .collect(Collectors.toList());
    }

    /**
     * 获取所有机器类型的分组信息
     */
    public static Map<String, List<Map<String, Object>>> getAllGrouped() {
        Map<String, List<Map<String, Object>>> result = new HashMap<>();

        // 共享核心
        result.put("共享核心", getSharedCoreMachineTypes().stream()
                .map(GcpMachineTypeEnum::toMap)
                .collect(Collectors.toList()));

        // 经济型
        result.put("经济型", getEconomyStandardMachineTypes().stream()
                .map(GcpMachineTypeEnum::toMap)
                .collect(Collectors.toList()));

        // 通用型
        result.put("通用型", getGeneralPurposeMachineTypes().stream()
                .map(GcpMachineTypeEnum::toMap)
                .collect(Collectors.toList()));

        // 高内存型
        result.put("高内存型", getHighMemoryMachineTypes().stream()
                .map(GcpMachineTypeEnum::toMap)
                .collect(Collectors.toList()));

        // 高CPU型
        result.put("高CPU型", getHighCpuMachineTypes().stream()
                .map(GcpMachineTypeEnum::toMap)
                .collect(Collectors.toList()));

        // 计算优化型
        result.put("计算优化型", getComputeOptimizedMachineTypes().stream()
                .map(GcpMachineTypeEnum::toMap)
                .collect(Collectors.toList()));

        return result;
    }

    /**
     * 转换为Map
     */
    public Map<String, Object> toMap() {
        Map<String, Object> map = new HashMap<>();
        map.put("name", name);
        map.put("displayName", displayName);
        map.put("vCpuCount", vCpuCount);
        map.put("memoryGb", memoryGb);
        map.put("series", series);
        map.put("type", type);
        return map;
    }

    @Override
    public String toString() {
        return displayName + " (" + name + ", " + vCpuCount + " vCPUs, " + memoryGb + " GB)";
        
        
    }
    
    public static GcpMachineTypeEnum getCustomerCpu(Integer customCpuCount){
        if (2 <= customCpuCount && customCpuCount < 4){
            return GcpMachineTypeEnum.E2_STANDARD_2;
        } else if (4 <= customCpuCount && customCpuCount < 8){
            return GcpMachineTypeEnum.E2_STANDARD_4;
        } else if (8 <= customCpuCount && customCpuCount < 16) {
            return GcpMachineTypeEnum.E2_STANDARD_8;
        } else if (16 <= customCpuCount && customCpuCount < 32) {
            return GcpMachineTypeEnum.E2_STANDARD_16;
        } else  {
            return GcpMachineTypeEnum.E2_STANDARD_32;
        }
    }
}
