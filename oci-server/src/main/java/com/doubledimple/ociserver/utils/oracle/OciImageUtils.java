package com.doubledimple.ociserver.utils.oracle;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.response.ImageInfoRes;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.model.Image;
import com.oracle.bmc.core.requests.ListImagesRequest;
import com.oracle.bmc.core.responses.ListImagesResponse;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName OciImageUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-29 03:46
 */
@Slf4j
public class OciImageUtils {

    /**
     * 获取镜像系统列表（仅 Oracle Linux / Ubuntu / CentOS）
     */
    public static List<ImageInfoRes> listSupportedLinuxImages(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        List<ImageInfoRes> result = new ArrayList<>();

        try (ComputeClient computeClient = ComputeClient.builder().build(provider)) {
            ListImagesResponse response = computeClient.listImages(
                    ListImagesRequest.builder()
                            .compartmentId(provider.getTenantId())
                            .sortBy(ListImagesRequest.SortBy.Displayname)
                            .sortOrder(ListImagesRequest.SortOrder.Asc)
                            .build()
            );

            Map<String, ImageInfoRes> map = new HashMap<>();

            for (Image img : response.getItems()) {
                if (img.getOperatingSystem() == null || img.getOperatingSystemVersion() == null) continue;
                log.debug("Image: {}", JSON.toJSONString( img));

                String os = img.getOperatingSystem().trim();
                String version = img.getOperatingSystemVersion();
                String display = Optional.ofNullable(img.getDisplayName()).orElse("").toLowerCase();

                // 只保留 Oracle Linux / Ubuntu / CentOS
                if (!isAllowedOs(os)) {
                    continue;
                }

                // 判断架构
                String arch;
                if (display.contains("aarch64") || display.contains("ampere")) {
                    arch = "ARM";
                } else {
                    arch = "AMD";
                }


                boolean free = isAlwaysFreeImage(os, version, arch);
                String key = os + "_" + version + "_" + arch;

                if (!map.containsKey(key)) {
                    ImageInfoRes info = new ImageInfoRes();
                    info.setImageId(img.getId());
                    info.setOperatingSystem(os);
                    info.setOperatingSystemVersion(version);
                    info.setArchitecture(arch);
                    info.setAlwaysFreeEligible(free);
                    info.setCloudType(CloudTypeEnum.ORACLE_CLOUD.getType());
                    map.put(key, info);
                }
            }

            result.addAll(map.values().stream()
                    .sorted(Comparator.comparing(ImageInfoRes::getOperatingSystem)
                            .thenComparing(ImageInfoRes::getOperatingSystemVersion))
                    .collect(Collectors.toList()));

        } catch (Exception e) {
            log.error("获取镜像系统列表失败: {}", e.getMessage(), e);
        }

        return result;
    }

    /**
     *  白名单
     */
    private static boolean isAllowedOs(String os) {
        String lower = os.toLowerCase();
        return lower.contains("oracle linux") ||
                lower.contains("ubuntu") ||
                lower.contains("centos");
    }

    /**
     *  判断是否 Always Free
     */
    private static boolean isAlwaysFreeImage(String os, String version, String arch) {
        //todo 为了以后扩展,暂时都是免费
        return true;
    }

    /**
     * 根据 Shape 自动筛选对应的镜像（ARM / AMD）
     * @param tenant 当前租户
     * @param shapeType 当前 Shape，例如 VM.Standard.A1.Flex
     * @return 对应的镜像列表（已自动匹配架构）
     */
    public static List<ImageInfoRes> listImagesByShape(Tenant tenant, String shapeType) {
        // 根据 shape 获取枚举
        ArchitectureEnum archEnum = ArchitectureEnum.getType(shapeType);
        if (archEnum == null) {
            log.warn("未找到对应的架构类型: {}", shapeType);
            return Collections.emptyList();
        }

        String archType = archEnum.getBackUpName(); // ARM 或 AMD

        // 拿到所有镜像
        List<ImageInfoRes> allImages = listSupportedLinuxImages(tenant);

        // 根据 Shape 的架构过滤
        return allImages.stream()
                .filter(img -> archType.equalsIgnoreCase(img.getArchitecture()))
                .sorted(Comparator.comparing(ImageInfoRes::getOperatingSystem)
                        .thenComparing(ImageInfoRes::getOperatingSystemVersion))
                .collect(Collectors.toList());
    }

}
