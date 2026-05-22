package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.pojo.request.PingNode;
import com.doubledimple.ociserver.pojo.response.PingResult;
import com.doubledimple.ociserver.pojo.response.ProvinceCarrierResult;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * @version 1.0.0
 * @ClassName PingConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 13:01
 */
public class PingConfig {
    public static List<PingNode> getNodes() {
        List<PingNode> nodes = new ArrayList<>();
        nodes.add(new PingNode("ct", "电信", "100017", "china"));
        nodes.add(new PingNode("cu", "联通", "100026", "china"));
        nodes.add(new PingNode("cm", "移动", "100025", "china"));
        nodes.add(new PingNode("hmt", "港澳台", null, "hmt"));
        nodes.add(new PingNode("asia", "亚洲", null, "asia"));
        nodes.add(new PingNode("europe", "欧洲", null, "europe"));
        nodes.add(new PingNode("africa", "非洲", null, "africa"));
        nodes.add(new PingNode("na", "北美洲", null, "na"));
        nodes.add(new PingNode("sa", "南美洲", null, "sa"));
        nodes.add(new PingNode("da", "大洋洲", null, "da"));
        return nodes;
    }

    public static final String BASE_URL = "https://tools.ipip.net/ping.php";

    // 定义省份列表
    private static final List<String> PROVINCES = Arrays.asList(
            "北京", "天津", "河北", "山西", "内蒙古",
            "辽宁", "吉林", "黑龙江", "上海", "江苏",
            "浙江", "安徽", "福建", "江西", "山东",
            "河南", "湖北", "湖南", "广东", "广西",
            "海南", "重庆", "四川", "贵州", "云南",
            "西藏", "陕西", "甘肃", "青海", "宁夏",
            "新疆", "香港", "澳门", "台湾"
    );

    public static Map<String, Map<String, ProvinceCarrierResult>> parseAndGroupByProvince(String content) {
        // 初始化结果Map: 省份 -> (运营商 -> 最佳结果)
        Map<String, Map<String, ProvinceCarrierResult>> provinceResults = new HashMap<>();
        PROVINCES.forEach(province -> {
            Map<String, ProvinceCarrierResult> carrierMap = new HashMap<>();
            carrierMap.put("电信", null);
            carrierMap.put("联通", null);
            carrierMap.put("移动", null);
            provinceResults.put(province, carrierMap);
        });

        Pattern pattern = Pattern.compile("parent\\.call_ping\\((.*?)\\);");
        Matcher matcher = pattern.matcher(content);

        while (matcher.find()) {
            JsonObject json = JsonParser.parseString(matcher.group(1)).getAsJsonObject();

            // 过滤无效记录
            double min = json.get("rtt_min").getAsDouble();
            double max = json.get("rtt_max").getAsDouble();
            if (min == 0 || max == 0) {
                continue;
            }

            String location = json.get("name").getAsString();

            // 确定省份
            String matchedProvince = PROVINCES.stream()
                    .filter(p -> location.contains(p))
                    .findFirst()
                    .orElse(null);

            if (matchedProvince == null) {
                continue;
            }

            // 确定运营商
            String carrier = null;
            if (location.contains("电信")) {
                carrier = "电信";
            } else if (location.contains("联通")) {
                carrier = "联通";
            } else if (location.contains("移动")) {
                carrier = "移动";
            } else {
                continue;
            }

            ProvinceCarrierResult result = ProvinceCarrierResult.builder()
                    .province(matchedProvince)
                    .carrier(carrier)
                    .location(location)
                    .ip(json.get("ip").getAsString())
                    .ttl(json.get("ttl").getAsInt())
                    .loss(json.get("loss").getAsString())
                    .latency(json.get("rtt_avg").getAsString() + " - 路由跟踪")
                    .min(json.get("rtt_min").getAsDouble())
                    .max(json.get("rtt_max").getAsDouble())
                    .build();

            // 更新最佳结果
            Map<String, ProvinceCarrierResult> provinceMap = provinceResults.get(matchedProvince);
            ProvinceCarrierResult currentBest = provinceMap.get(carrier);
            if (currentBest == null || result.getMin() < currentBest.getMin()) {
                provinceMap.put(carrier, result);
            }
        }

        return provinceResults;
    }

    // 将通用的 PingResult 转换为按省份分类的结果
    public static Map<String, Map<String, ProvinceCarrierResult>> convertToProvinceResults(Map<String, List<PingResult>> carrierResults) {
        // 初始化省份结果Map
        Map<String, Map<String, ProvinceCarrierResult>> provinceResults = new HashMap<>();
        PROVINCES.forEach(province -> {
            Map<String, ProvinceCarrierResult> carrierMap = new HashMap<>();
            carrierMap.put("电信", null);
            carrierMap.put("联通", null);
            carrierMap.put("移动", null);
            provinceResults.put(province, carrierMap);
        });

        // 处理每个运营商的结果
        carrierResults.forEach((carrier, pingResults) -> {
            for (PingResult pingResult : pingResults) {
                // 跳过min或max为0的记录
                try {
                    double min = Double.parseDouble(pingResult.getMin());
                    double max = Double.parseDouble(pingResult.getMax());
                    if (min == 0 || max == 0) {
                        continue;
                    }
                } catch (NumberFormatException e) {
                    continue;
                }

                // 确定省份
                String location = pingResult.getLocation();
                String matchedProvince = PROVINCES.stream()
                        .filter(p -> location.contains(p))
                        .findFirst()
                        .orElse(null);

                if (matchedProvince == null) {
                    continue;
                }

                // 确定运营商分类
                String actualCarrier;
                if (carrier.equals("其他")) {
                    continue; // 跳过非三网节点
                } else {
                    actualCarrier = carrier;
                }

                // 创建 ProvinceCarrierResult 对象
                ProvinceCarrierResult result = ProvinceCarrierResult.builder()
                        .province(matchedProvince)
                        .carrier(actualCarrier)
                        .location(location)
                        .ip(pingResult.getIp())
                        .ttl(pingResult.getTtl())
                        .loss(pingResult.getLoss())
                        .latency(pingResult.getLatency())
                        .min(Double.parseDouble(pingResult.getMin()))
                        .max(Double.parseDouble(pingResult.getMax()))
                        .build();

                // 更新最佳结果
                Map<String, ProvinceCarrierResult> provinceMap = provinceResults.get(matchedProvince);
                ProvinceCarrierResult currentBest = provinceMap.get(actualCarrier);
                if (currentBest == null || result.getMin() < currentBest.getMin()) {
                    provinceMap.put(actualCarrier, result);
                }
            }
        });

        return provinceResults;
    }
}
