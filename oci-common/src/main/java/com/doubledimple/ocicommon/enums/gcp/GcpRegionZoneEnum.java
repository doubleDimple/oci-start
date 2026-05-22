package com.doubledimple.ocicommon.enums.gcp;

import lombok.Data;
import lombok.ToString;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * GCP区域和可用区枚举类
 * 包含完整的GCP区域和可用区的中英文映射关系
 * 基于实际API返回数据构建
 */
public enum GcpRegionZoneEnum {

        // 非洲
        AFRICA_SOUTH1("africa-south1", "约翰内斯堡", Arrays.asList(
                new ZoneInfo("africa-south1-a", "约翰内斯堡 可用区 a"),
                new ZoneInfo("africa-south1-b", "约翰内斯堡 可用区 b"),
                new ZoneInfo("africa-south1-c", "约翰内斯堡 可用区 c")
        )),

        // 亚太地区
        ASIA_EAST1("asia-east1", "中国台湾", Arrays.asList(
                new ZoneInfo("asia-east1-a", "中国台湾 可用区 a"),
                new ZoneInfo("asia-east1-b", "中国台湾 可用区 b"),
                new ZoneInfo("asia-east1-c", "中国台湾 可用区 c")
        )),

        ASIA_EAST2("asia-east2", "中国香港", Arrays.asList(
                new ZoneInfo("asia-east2-a", "中国香港 可用区 a"),
                new ZoneInfo("asia-east2-b", "中国香港 可用区 b"),
                new ZoneInfo("asia-east2-c", "中国香港 可用区 c")
        )),

        ASIA_NORTHEAST1("asia-northeast1", "东京", Arrays.asList(
                new ZoneInfo("asia-northeast1-a", "东京 可用区 a"),
                new ZoneInfo("asia-northeast1-b", "东京 可用区 b"),
                new ZoneInfo("asia-northeast1-c", "东京 可用区 c")
        )),

        ASIA_NORTHEAST2("asia-northeast2", "大阪", Arrays.asList(
                new ZoneInfo("asia-northeast2-a", "大阪 可用区 a"),
                new ZoneInfo("asia-northeast2-b", "大阪 可用区 b"),
                new ZoneInfo("asia-northeast2-c", "大阪 可用区 c")
        )),

        ASIA_NORTHEAST3("asia-northeast3", "首尔", Arrays.asList(
                new ZoneInfo("asia-northeast3-a", "首尔 可用区 a"),
                new ZoneInfo("asia-northeast3-b", "首尔 可用区 b"),
                new ZoneInfo("asia-northeast3-c", "首尔 可用区 c")
        )),

        ASIA_SOUTH1("asia-south1", "孟买", Arrays.asList(
                new ZoneInfo("asia-south1-a", "孟买 可用区 a"),
                new ZoneInfo("asia-south1-b", "孟买 可用区 b"),
                new ZoneInfo("asia-south1-c", "孟买 可用区 c")
        )),

        ASIA_SOUTH2("asia-south2", "德里", Arrays.asList(
                new ZoneInfo("asia-south2-a", "德里 可用区 a"),
                new ZoneInfo("asia-south2-b", "德里 可用区 b"),
                new ZoneInfo("asia-south2-c", "德里 可用区 c")
        )),

        ASIA_SOUTHEAST1("asia-southeast1", "新加坡", Arrays.asList(
                new ZoneInfo("asia-southeast1-a", "新加坡 可用区 a"),
                new ZoneInfo("asia-southeast1-b", "新加坡 可用区 b"),
                new ZoneInfo("asia-southeast1-c", "新加坡 可用区 c")
        )),

        ASIA_SOUTHEAST2("asia-southeast2", "雅加达", Arrays.asList(
                new ZoneInfo("asia-southeast2-a", "雅加达 可用区 a"),
                new ZoneInfo("asia-southeast2-b", "雅加达 可用区 b"),
                new ZoneInfo("asia-southeast2-c", "雅加达 可用区 c")
        )),

        // 澳大利亚
        AUSTRALIA_SOUTHEAST1("australia-southeast1", "悉尼", Arrays.asList(
                new ZoneInfo("australia-southeast1-a", "悉尼 可用区 a"),
                new ZoneInfo("australia-southeast1-b", "悉尼 可用区 b"),
                new ZoneInfo("australia-southeast1-c", "悉尼 可用区 c")
        )),

        AUSTRALIA_SOUTHEAST2("australia-southeast2", "墨尔本", Arrays.asList(
                new ZoneInfo("australia-southeast2-a", "墨尔本 可用区 a"),
                new ZoneInfo("australia-southeast2-b", "墨尔本 可用区 b"),
                new ZoneInfo("australia-southeast2-c", "墨尔本 可用区 c")
        )),

        // 欧洲
        EUROPE_CENTRAL2("europe-central2", "华沙", Arrays.asList(
                new ZoneInfo("europe-central2-a", "华沙 可用区 a"),
                new ZoneInfo("europe-central2-b", "华沙 可用区 b"),
                new ZoneInfo("europe-central2-c", "华沙 可用区 c")
        )),

        EUROPE_NORTH1("europe-north1", "芬兰", Arrays.asList(
                new ZoneInfo("europe-north1-a", "芬兰 可用区 a"),
                new ZoneInfo("europe-north1-b", "芬兰 可用区 b"),
                new ZoneInfo("europe-north1-c", "芬兰 可用区 c")
        )),

        EUROPE_NORTH2("europe-north2", "赫尔辛基", Arrays.asList(
                new ZoneInfo("europe-north2-a", "赫尔辛基 可用区 a"),
                new ZoneInfo("europe-north2-b", "赫尔辛基 可用区 b"),
                new ZoneInfo("europe-north2-c", "赫尔辛基 可用区 c")
        )),

        EUROPE_SOUTHWEST1("europe-southwest1", "马德里", Arrays.asList(
                new ZoneInfo("europe-southwest1-a", "马德里 可用区 a"),
                new ZoneInfo("europe-southwest1-b", "马德里 可用区 b"),
                new ZoneInfo("europe-southwest1-c", "马德里 可用区 c")
        )),

        EUROPE_WEST1("europe-west1", "比利时", Arrays.asList(
                new ZoneInfo("europe-west1-b", "比利时 可用区 b"),
                new ZoneInfo("europe-west1-c", "比利时 可用区 c"),
                new ZoneInfo("europe-west1-d", "比利时 可用区 d")
        )),

        EUROPE_WEST2("europe-west2", "伦敦", Arrays.asList(
                new ZoneInfo("europe-west2-a", "伦敦 可用区 a"),
                new ZoneInfo("europe-west2-b", "伦敦 可用区 b"),
                new ZoneInfo("europe-west2-c", "伦敦 可用区 c")
        )),

        EUROPE_WEST3("europe-west3", "法兰克福", Arrays.asList(
                new ZoneInfo("europe-west3-a", "法兰克福 可用区 a"),
                new ZoneInfo("europe-west3-b", "法兰克福 可用区 b"),
                new ZoneInfo("europe-west3-c", "法兰克福 可用区 c")
        )),

        EUROPE_WEST4("europe-west4", "荷兰", Arrays.asList(
                new ZoneInfo("europe-west4-a", "荷兰 可用区 a"),
                new ZoneInfo("europe-west4-b", "荷兰 可用区 b"),
                new ZoneInfo("europe-west4-c", "荷兰 可用区 c")
        )),

        EUROPE_WEST6("europe-west6", "苏黎世", Arrays.asList(
                new ZoneInfo("europe-west6-a", "苏黎世 可用区 a"),
                new ZoneInfo("europe-west6-b", "苏黎世 可用区 b"),
                new ZoneInfo("europe-west6-c", "苏黎世 可用区 c")
        )),

        EUROPE_WEST8("europe-west8", "米兰", Arrays.asList(
                new ZoneInfo("europe-west8-a", "米兰 可用区 a"),
                new ZoneInfo("europe-west8-b", "米兰 可用区 b"),
                new ZoneInfo("europe-west8-c", "米兰 可用区 c")
        )),

        EUROPE_WEST9("europe-west9", "巴黎", Arrays.asList(
                new ZoneInfo("europe-west9-a", "巴黎 可用区 a"),
                new ZoneInfo("europe-west9-b", "巴黎 可用区 b"),
                new ZoneInfo("europe-west9-c", "巴黎 可用区 c")
        )),

        EUROPE_WEST10("europe-west10", "柏林", Arrays.asList(
                new ZoneInfo("europe-west10-a", "柏林 可用区 a"),
                new ZoneInfo("europe-west10-b", "柏林 可用区 b"),
                new ZoneInfo("europe-west10-c", "柏林 可用区 c")
        )),

        EUROPE_WEST12("europe-west12", "都灵", Arrays.asList(
                new ZoneInfo("europe-west12-a", "都灵 可用区 a"),
                new ZoneInfo("europe-west12-b", "都灵 可用区 b"),
                new ZoneInfo("europe-west12-c", "都灵 可用区 c")
        )),

        // 中东
        ME_CENTRAL1("me-central1", "多哈", Arrays.asList(
                new ZoneInfo("me-central1-a", "多哈 可用区 a"),
                new ZoneInfo("me-central1-b", "多哈 可用区 b"),
                new ZoneInfo("me-central1-c", "多哈 可用区 c")
        )),

        ME_CENTRAL2("me-central2", "达曼", Arrays.asList(
                new ZoneInfo("me-central2-a", "达曼 可用区 a"),
                new ZoneInfo("me-central2-b", "达曼 可用区 b"),
                new ZoneInfo("me-central2-c", "达曼 可用区 c")
        )),

        ME_WEST1("me-west1", "特拉维夫", Arrays.asList(
                new ZoneInfo("me-west1-a", "特拉维夫 可用区 a"),
                new ZoneInfo("me-west1-b", "特拉维夫 可用区 b"),
                new ZoneInfo("me-west1-c", "特拉维夫 可用区 c")
        )),

        // 北美
        NORTHAMERICA_NORTHEAST1("northamerica-northeast1", "蒙特利尔", Arrays.asList(
                new ZoneInfo("northamerica-northeast1-a", "蒙特利尔 可用区 a"),
                new ZoneInfo("northamerica-northeast1-b", "蒙特利尔 可用区 b"),
                new ZoneInfo("northamerica-northeast1-c", "蒙特利尔 可用区 c")
        )),

        NORTHAMERICA_NORTHEAST2("northamerica-northeast2", "多伦多", Arrays.asList(
                new ZoneInfo("northamerica-northeast2-a", "多伦多 可用区 a"),
                new ZoneInfo("northamerica-northeast2-b", "多伦多 可用区 b"),
                new ZoneInfo("northamerica-northeast2-c", "多伦多 可用区 c")
        )),

        NORTHAMERICA_SOUTH1("northamerica-south1", "墨西哥城", Arrays.asList(
                new ZoneInfo("northamerica-south1-a", "墨西哥城 可用区 a"),
                new ZoneInfo("northamerica-south1-b", "墨西哥城 可用区 b"),
                new ZoneInfo("northamerica-south1-c", "墨西哥城 可用区 c")
        )),

        // 南美
        SOUTHAMERICA_EAST1("southamerica-east1", "圣保罗", Arrays.asList(
                new ZoneInfo("southamerica-east1-a", "圣保罗 可用区 a"),
                new ZoneInfo("southamerica-east1-b", "圣保罗 可用区 b"),
                new ZoneInfo("southamerica-east1-c", "圣保罗 可用区 c")
        )),

        SOUTHAMERICA_WEST1("southamerica-west1", "圣地亚哥", Arrays.asList(
                new ZoneInfo("southamerica-west1-a", "圣地亚哥 可用区 a"),
                new ZoneInfo("southamerica-west1-b", "圣地亚哥 可用区 b"),
                new ZoneInfo("southamerica-west1-c", "圣地亚哥 可用区 c")
        )),

        // 美国
        US_CENTRAL1("us-central1", "爱荷华", Arrays.asList(
                new ZoneInfo("us-central1-a", "爱荷华 可用区 a"),
                new ZoneInfo("us-central1-b", "爱荷华 可用区 b"),
                new ZoneInfo("us-central1-c", "爱荷华 可用区 c"),
                new ZoneInfo("us-central1-f", "爱荷华 可用区 f")
        )),

        US_EAST1("us-east1", "南卡罗来纳", Arrays.asList(
                new ZoneInfo("us-east1-b", "南卡罗来纳 可用区 b"),
                new ZoneInfo("us-east1-c", "南卡罗来纳 可用区 c"),
                new ZoneInfo("us-east1-d", "南卡罗来纳 可用区 d")
        )),

        US_EAST4("us-east4", "北弗吉尼亚", Arrays.asList(
                new ZoneInfo("us-east4-a", "北弗吉尼亚 可用区 a"),
                new ZoneInfo("us-east4-b", "北弗吉尼亚 可用区 b"),
                new ZoneInfo("us-east4-c", "北弗吉尼亚 可用区 c")
        )),

        US_EAST5("us-east5", "哥伦布", Arrays.asList(
                new ZoneInfo("us-east5-a", "哥伦布 可用区 a"),
                new ZoneInfo("us-east5-b", "哥伦布 可用区 b"),
                new ZoneInfo("us-east5-c", "哥伦布 可用区 c")
        )),

        US_SOUTH1("us-south1", "达拉斯", Arrays.asList(
                new ZoneInfo("us-south1-a", "达拉斯 可用区 a"),
                new ZoneInfo("us-south1-b", "达拉斯 可用区 b"),
                new ZoneInfo("us-south1-c", "达拉斯 可用区 c")
        )),

        US_WEST1("us-west1", "俄勒冈", Arrays.asList(
                new ZoneInfo("us-west1-a", "俄勒冈 可用区 a"),
                new ZoneInfo("us-west1-b", "俄勒冈 可用区 b"),
                new ZoneInfo("us-west1-c", "俄勒冈 可用区 c")
        )),

        US_WEST2("us-west2", "洛杉矶", Arrays.asList(
                new ZoneInfo("us-west2-a", "洛杉矶 可用区 a"),
                new ZoneInfo("us-west2-b", "洛杉矶 可用区 b"),
                new ZoneInfo("us-west2-c", "洛杉矶 可用区 c")
        )),

        US_WEST3("us-west3", "盐湖城", Arrays.asList(
                new ZoneInfo("us-west3-a", "盐湖城 可用区 a"),
                new ZoneInfo("us-west3-b", "盐湖城 可用区 b"),
                new ZoneInfo("us-west3-c", "盐湖城 可用区 c")
        )),

        US_WEST4("us-west4", "拉斯维加斯", Arrays.asList(
                new ZoneInfo("us-west4-a", "拉斯维加斯 可用区 a"),
                new ZoneInfo("us-west4-b", "拉斯维加斯 可用区 b"),
                new ZoneInfo("us-west4-c", "拉斯维加斯 可用区 c")
        ));

        // 区域英文名称
        private final String regionName;
        // 区域中文名称
        private final String regionNameZh;
        // 区域包含的可用区列表
        private final List<ZoneInfo> zones;

        // 可用区状态中英文映射
        private static final Map<String, String> STATUS_MAP = new HashMap<>();
        // 区域中英文映射缓存
        private static final Map<String, GcpRegionZoneEnum> REGION_MAP = new HashMap<>();
        // 可用区中英文映射缓存
        private static final Map<String, ZoneInfo> ZONE_MAP = new HashMap<>();

        static {
            // 初始化状态映射
            STATUS_MAP.put("UP", "正常运行");
            STATUS_MAP.put("DOWN", "停止服务");
            STATUS_MAP.put("MAINTENANCE", "维护中");

            // 初始化区域和可用区映射缓存
            for (GcpRegionZoneEnum region : GcpRegionZoneEnum.values()) {
                REGION_MAP.put(region.getRegionName(), region);

                for (ZoneInfo zone : region.getZones()) {
                    ZONE_MAP.put(zone.getZoneName(), zone);
                }
            }
        }

        /**
         * 构造函数
         *
         * @param regionName   区域英文名称
         * @param regionNameZh 区域中文名称
         * @param zones        可用区列表
         */
        GcpRegionZoneEnum(String regionName, String regionNameZh, List<ZoneInfo> zones) {
            this.regionName = regionName;
            this.regionNameZh = regionNameZh;
            this.zones = Collections.unmodifiableList(zones);
        }

        /**
         * 获取区域英文名称
         */
        public String getRegionName() {
            return regionName;
        }

        /**
         * 获取区域中文名称
         */
        public String getRegionNameZh() {
            return regionNameZh;
        }

        /**
         * 获取区域包含的可用区列表
         */
        public List<ZoneInfo> getZones() {
            return zones;
        }

        /**
         * 根据区域英文名称获取区域枚举
         *
         * @param regionName 区域英文名称
         * @return 区域枚举
         */
        public static GcpRegionZoneEnum getByRegionName(String regionName) {
            return REGION_MAP.get(regionName);
        }

        /**
         * 从区域URL中提取区域名称
         *
         * @param regionUrl 区域URL
         * @return 区域名称
         */
        public static String extractRegionNameFromUrl(String regionUrl) {
            if (regionUrl != null && regionUrl.contains("/regions/")) {
                return regionUrl.substring(regionUrl.lastIndexOf("/") + 1);
            }
            return regionUrl;
        }

        /**
         * 根据区域URL获取区域中文名称
         *
         * @param regionUrl 区域URL
         * @return 区域中文名称，如果未找到则返回原始名称
         */
        public static String getRegionNameZhFromUrl(String regionUrl) {
            String regionName = extractRegionNameFromUrl(regionUrl);
            return getRegionNameZh(regionName);
        }

        /**
         * 根据区域英文名称获取区域中文名称
         *
         * @param regionName 区域英文名称
         * @return 区域中文名称，如果未找到则返回原始名称
         */
        public static String getRegionNameZh(String regionName) {
            return Optional.ofNullable(REGION_MAP.get(regionName))
                    .map(GcpRegionZoneEnum::getRegionNameZh)
                    .orElse(regionName);
        }

        /**
         * 根据可用区英文名称获取可用区信息
         *
         * @param zoneName 可用区英文名称
         * @return 可用区信息
         */
        public static ZoneInfo getZoneInfo(String zoneName) {
            return ZONE_MAP.get(zoneName);
        }

        /**
         * 根据可用区英文名称获取可用区中文名称
         *
         * @param zoneName 可用区英文名称
         * @return 可用区中文名称，如果未找到则返回原始名称
         */
        public static String getZoneNameZh(String zoneName) {
            return Optional.ofNullable(ZONE_MAP.get(zoneName))
                    .map(ZoneInfo::getZoneNameZh)
                    .orElse(zoneName);
        }

        /**
         * 获取状态中文名称
         *
         * @param status 状态英文名称
         * @return 状态中文名称，如果未找到则返回原始名称
         */
        public static String getStatusZh(String status) {
            return STATUS_MAP.getOrDefault(status, status);
        }

        /**
         * 将API返回的区域信息转换为中文区域信息
         *
         * @param apiZoneInfo API返回的区域信息
         * @return 包含中文信息的区域对象
         */
        public static ZoneInfoWithChinese convertToZoneInfoWithChinese(Object apiZoneInfo) {
            try {
                // 使用反射获取属性值
                Class<?> clazz = apiZoneInfo.getClass();
                String id = (String) clazz.getMethod("getId").invoke(apiZoneInfo);
                String name = (String) clazz.getMethod("getName").invoke(apiZoneInfo);
                String description = (String) clazz.getMethod("getDescription").invoke(apiZoneInfo);
                String status = (String) clazz.getMethod("getStatus").invoke(apiZoneInfo);
                String regionUrl = (String) clazz.getMethod("getRegion").invoke(apiZoneInfo);

                String regionName = extractRegionNameFromUrl(regionUrl);

                ZoneInfoWithChinese zoneInfoWithChinese = new ZoneInfoWithChinese();
                zoneInfoWithChinese.setId(id);
                zoneInfoWithChinese.setName(name);
                zoneInfoWithChinese.setNameZh(getZoneNameZh(name));
                zoneInfoWithChinese.setDescription(description);
                zoneInfoWithChinese.setStatus(status);
                zoneInfoWithChinese.setStatusZh(getStatusZh(status));
                zoneInfoWithChinese.setRegion(regionName);
                zoneInfoWithChinese.setRegionZh(getRegionNameZh(regionName));

                return zoneInfoWithChinese;
            } catch (Exception e) {
                throw new RuntimeException("转换区域信息失败", e);
            }
        }

        /**
         * 可用区信息类
         */
        public static class ZoneInfo {
            // 可用区英文名称
            private final String zoneName;
            // 可用区中文名称
            private final String zoneNameZh;

            /**
             * 构造函数
             *
             * @param zoneName   可用区英文名称
             * @param zoneNameZh 可用区中文名称
             */
            public ZoneInfo(String zoneName, String zoneNameZh) {
                this.zoneName = zoneName;
                this.zoneNameZh = zoneNameZh;
            }

            /**
             * 获取可用区英文名称
             */
            public String getZoneName() {
                return zoneName;
            }

            /**
             * 获取可用区中文名称
             */
            public String getZoneNameZh() {
                return zoneNameZh;
            }

            @Override
            public String toString() {
                return zoneNameZh + " (" + zoneName + ")";
            }
        }

        /**
         * 带中文翻译的区域信息DTO
         */
        @Data
        @ToString
        public static class ZoneInfoWithChinese {
            private String id;
            private String name;
            private String nameZh;
            private String description;
            private String status;
            private String statusZh;
            private String region;
            private String regionZh;
        }
}
