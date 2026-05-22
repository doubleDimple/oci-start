package com.doubledimple.ociserver.utils.google;

import com.doubledimple.ocicommon.enums.gcp.GcpRegionZoneEnum;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName GcpZoneUtil
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-22 14:57
 */
public class GcpZoneUtil {

    /**
     * 将API返回的区域信息列表转换为带中文翻译的区域信息列表
     *
     * @param apiResponseJson API返回的JSON字符串
     * @return 带中文翻译的区域信息列表
     */
    public static List<GcpRegionZoneEnum.ZoneInfoWithChinese> convertApiResponseToChineseZones(String apiResponseJson) {
        try {
            ObjectMapper objectMapper = new ObjectMapper();
            List<Map<String, Object>> apiZones = objectMapper.readValue(
                    apiResponseJson,
                    new TypeReference<List<Map<String, Object>>>() {}
            );

            return apiZones.stream()
                    .map(GcpZoneUtil::convertMapToZoneInfoWithChinese)
                    .collect(Collectors.toList());
        } catch (JsonProcessingException e) {
            throw new RuntimeException("解析API响应失败", e);
        }
    }

    /**
     * 将Map格式的区域信息转换为带中文翻译的区域信息
     *
     * @param zoneMap Map格式的区域信息
     * @return 带中文翻译的区域信息
     */
    private static GcpRegionZoneEnum.ZoneInfoWithChinese convertMapToZoneInfoWithChinese(Map<String, Object> zoneMap) {
        String id = (String) zoneMap.get("id");
        String name = (String) zoneMap.get("name");
        String description = (String) zoneMap.get("description");
        String status = (String) zoneMap.get("status");
        String regionUrl = (String) zoneMap.get("region");

        String regionName = GcpRegionZoneEnum.extractRegionNameFromUrl(regionUrl);

        GcpRegionZoneEnum.ZoneInfoWithChinese result = new GcpRegionZoneEnum.ZoneInfoWithChinese();
        result.setId(id);
        result.setName(name);
        result.setNameZh(GcpRegionZoneEnum.getZoneNameZh(name));
        result.setDescription(description);
        result.setStatus(status);
        result.setStatusZh(GcpRegionZoneEnum.getStatusZh(status));
        result.setRegion(regionName);
        result.setRegionZh(GcpRegionZoneEnum.getRegionNameZh(regionName));

        return result;
    }

    /**
     * 将API返回的原始区域对象转换为带中文翻译的区域信息
     *
     * @param apiZoneInfo API返回的原始区域对象
     * @return 带中文翻译的区域信息
     */
    public static GcpRegionZoneEnum.ZoneInfoWithChinese convertApiZoneToChineseZone(Object apiZoneInfo) {
        return GcpRegionZoneEnum.convertToZoneInfoWithChinese(apiZoneInfo);
    }

    /**
     * 将API返回的原始区域列表转换为带中文翻译的区域信息列表
     *
     * @param apiZoneInfoList API返回的原始区域列表
     * @return 带中文翻译的区域信息列表
     */
    public static List<GcpRegionZoneEnum.ZoneInfoWithChinese> convertApiZonesToChineseZones(List<?> apiZoneInfoList) {
        List<GcpRegionZoneEnum.ZoneInfoWithChinese> result = new ArrayList<>();

        for (Object apiZoneInfo : apiZoneInfoList) {
            result.add(convertApiZoneToChineseZone(apiZoneInfo));
        }

        return result;
    }

    /**
     * 将区域列表按区域分组
     *
     * @param zones 区域列表
     * @return 按区域分组的区域列表
     */
    public static Map<String, List<GcpRegionZoneEnum.ZoneInfoWithChinese>> groupZonesByRegion(
            List<GcpRegionZoneEnum.ZoneInfoWithChinese> zones) {
        return zones.stream()
                .collect(Collectors.groupingBy(GcpRegionZoneEnum.ZoneInfoWithChinese::getRegion));
    }

    /**
     * 将区域列表按区域（中文）分组
     *
     * @param zones 区域列表
     * @return 按区域（中文）分组的区域列表
     */
    public static Map<String, List<GcpRegionZoneEnum.ZoneInfoWithChinese>> groupZonesByRegionZh(
            List<GcpRegionZoneEnum.ZoneInfoWithChinese> zones) {
        return zones.stream()
                .collect(Collectors.groupingBy(GcpRegionZoneEnum.ZoneInfoWithChinese::getRegionZh));
    }

    /**
     * 获取所有区域的中英文对照表
     *
     * @return 区域中英文对照表
     */
    public static Map<String, String> getAllRegionsWithChinese() {
        return Arrays.stream(GcpRegionZoneEnum.values())
                .collect(Collectors.toMap(
                        GcpRegionZoneEnum::getRegionName,
                        GcpRegionZoneEnum::getRegionNameZh
                ));
    }

    /**
     * 获取所有可用区的中英文对照表
     *
     * @return 可用区中英文对照表
     */
    public static Map<String, String> getAllZonesWithChinese() {
        Map<String, String> result = new HashMap<>();

        for (GcpRegionZoneEnum region : GcpRegionZoneEnum.values()) {
            for (GcpRegionZoneEnum.ZoneInfo zone : region.getZones()) {
                result.put(zone.getZoneName(), zone.getZoneNameZh());
            }
        }

        return result;
    }
}
