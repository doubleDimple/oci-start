package com.doubledimple.ociserver.pojo.response;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import lombok.Builder;
import lombok.Data;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * @version 1.0.0
 * @ClassName PingResult
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 13:13
 */
@Data
@Builder
public class PingResult {
    private String location;    // Ping的地点
    private String ip;         // 响应IP
    private int ttl;          // TTL
    private String loss;      // 丢包率
    private String latency;   // 响应时间
    private String min;       // 最小值
    private String max;       // 最大值

    public static Map<String, List<PingResult>> parsePingResults(String content) {
        List<PingResult> results = new ArrayList<>();
        Pattern pattern = Pattern.compile("parent\\.call_ping\\((.*?)\\);");
        Matcher matcher = pattern.matcher(content);

        // 四个运营商的结果集合
        Map<String, List<PingResult>> carrierResults = new HashMap<>();
        carrierResults.put("电信", new ArrayList<>());
        carrierResults.put("联通", new ArrayList<>());
        carrierResults.put("移动", new ArrayList<>());
        carrierResults.put("其他", new ArrayList<>());



        while (matcher.find()) {
            String jsonStr = matcher.group(1);
            JsonObject jsonObject = JsonParser.parseString(jsonStr).getAsJsonObject();

            // 过滤min和max为0的记录
            double min = jsonObject.get("rtt_min").getAsDouble();
            double max = jsonObject.get("rtt_max").getAsDouble();
            if(min == 0 || max == 0) {
                continue;
            }

            PingResult result = PingResult.builder()
                    .location(jsonObject.get("name").getAsString())
                    .ip(jsonObject.get("ip").getAsString())
                    .ttl(jsonObject.get("ttl").getAsInt())
                    .loss(jsonObject.get("loss").getAsString())
                    .latency(jsonObject.get("rtt_avg").getAsString() + " - 路由跟踪")
                    .min(jsonObject.get("rtt_min").getAsString())
                    .max(jsonObject.get("rtt_max").getAsString())
                    .build();

            // 根据location判断运营商
            String location = result.getLocation().toLowerCase();
            if (location.contains("电信")) {
                carrierResults.get("电信").add(result);
            } else if (location.contains("联通")) {
                carrierResults.get("联通").add(result);
            } else if (location.contains("移动")) {
                carrierResults.get("移动").add(result);
            } else {
                carrierResults.get("其他").add(result);
            }
        }

        return carrierResults;
    }
}
