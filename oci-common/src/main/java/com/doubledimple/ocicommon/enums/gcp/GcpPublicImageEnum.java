package com.doubledimple.ocicommon.enums.gcp;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * GCP公共镜像枚举
 * 包含Debian系列镜像
 */
public enum GcpPublicImageEnum {

    // Debian 12 (x86_64)
    DEBIAN_12_X86("debian-12-bookworm-v20250610",
            "debian-cloud",
            "debian-12",
            "Debian 12 (Bookworm)",
            "Debian, Debian GNU/Linux, 12 (bookworm), amd64 built on 20250610",
            10L,
            "X86_64"),


    // Debian 12 (ARM64)
    DEBIAN_12_ARM64("debian-12-bookworm-arm64-v20250610",
            "debian-cloud",
            "debian-12-arm64",
            "Debian 12 (Bookworm) ARM64",
            "Debian, Debian GNU/Linux, 12 (bookworm), arm64 built on 20250610",
            10L,
            "ARM64");

    // 镜像名称
    private final String imageName;
    // 项目ID
    private final String projectId;
    // 镜像族
    private final String family;
    // 显示名称
    private final String displayName;
    // 描述
    private final String description;
    // 磁盘大小(GB)
    private final Long diskSizeGb;
    // 架构
    private final String architecture;

    // 按imageName的映射
    private static final Map<String, GcpPublicImageEnum> IMAGE_NAME_MAP;
    // 按projectId和family的映射
    private static final Map<String, GcpPublicImageEnum> PROJECT_FAMILY_MAP;

    static {
        IMAGE_NAME_MAP = Arrays.stream(values())
                .collect(Collectors.toMap(GcpPublicImageEnum::getImageName, Function.identity()));

        PROJECT_FAMILY_MAP = Arrays.stream(values())
                .collect(Collectors.toMap(
                        image -> image.getProjectId() + "/" + image.getFamily(),
                        Function.identity()));
    }

    /**
     * 构造函数
     */
    GcpPublicImageEnum(String imageName, String projectId, String family,
                       String displayName, String description,
                       Long diskSizeGb, String architecture) {
        this.imageName = imageName;
        this.projectId = projectId;
        this.family = family;
        this.displayName = displayName;
        this.description = description;
        this.diskSizeGb = diskSizeGb;
        this.architecture = architecture;
    }

    /**
     * 获取镜像名称
     */
    public String getImageName() {
        return imageName;
    }

    /**
     * 获取项目ID
     */
    public String getProjectId() {
        return projectId;
    }

    /**
     * 获取镜像族
     */
    public String getFamily() {
        return family;
    }

    /**
     * 获取显示名称
     */
    public String getDisplayName() {
        return displayName;
    }

    /**
     * 获取描述
     */
    public String getDescription() {
        return description;
    }

    /**
     * 获取磁盘大小(GB)
     */
    public Long getDiskSizeGb() {
        return diskSizeGb;
    }

    /**
     * 获取架构
     */
    public String getArchitecture() {
        return architecture;
    }

    /**
     * 获取镜像源URL (用于创建实例)
     */
    public String getSourceImageUrl() {
        return "projects/" + projectId + "/global/images/" + imageName;
    }

    /**
     * 获取镜像族URL (用于创建实例)
     */
    public String getFamilyUrl() {
        return "projects/" + projectId + "/global/images/family/" + family;
    }

    /**
     * 通过镜像名称获取枚举
     */
    public static GcpPublicImageEnum getByImageName(String imageName) {
        return IMAGE_NAME_MAP.get(imageName);
    }

    /**
     * 通过项目ID和镜像族获取枚举
     */
    public static GcpPublicImageEnum getByProjectAndFamily(String projectId, String family) {
        return PROJECT_FAMILY_MAP.get(projectId + "/" + family);
    }

    /**
     * 获取所有镜像的显示信息
     */
    public static List<Map<String, String>> getAllImagesDisplayInfo() {
        return Arrays.stream(values())
                .map(image -> {
                    Map<String, String> map = new HashMap<>();
                    map.put("id", image.name());
                    map.put("name", image.getDisplayName());
                    map.put("description", image.getDescription());
                    map.put("architecture", image.getArchitecture());
                    map.put("diskSizeGb", String.valueOf(image.getDiskSizeGb()));
                    map.put("project", image.getProjectId());
                    map.put("family", image.getFamily());
                    map.put("imageName", image.getImageName());
                    return map;
                })
                .collect(Collectors.toList());
    }

    /**
     * 获取特定架构的镜像
     */
    public static List<GcpPublicImageEnum> getByArchitecture(String architecture) {
        return Arrays.stream(values())
                .filter(image -> image.getArchitecture().equalsIgnoreCase(architecture))
                .collect(Collectors.toList());
    }

    /**
     * 获取推荐的默认镜像
     */
    public static GcpPublicImageEnum getDefaultImage() {
        return DEBIAN_12_X86;  // 默认推荐使用 Debian 12 x86_64
    }
}
