package com.doubledimple.ociserver.utils;

import cn.hutool.http.HttpRequest;
import cn.hutool.json.JSONUtil;
import com.alibaba.fastjson2.JSONObject;
import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.pojo.response.PingResult;
import com.doubledimple.ociserver.pojo.response.ProvinceCarrierResult;
import com.maxmind.geoip2.DatabaseReader;
import com.maxmind.geoip2.model.CityResponse;
import lombok.extern.slf4j.Slf4j;

import javax.servlet.http.HttpServletRequest;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ociserver.config.PingConfig.convertToProvinceResults;
import static com.doubledimple.ociserver.pojo.response.PingResult.parsePingResults;

/**
 * @version 1.0.0
 * @ClassName PingUtil
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 13:02
 */
@Slf4j
public class PingUtil {

    private static final String BASE_URL = "https://tools.ipip.net/ping.php";

    private static volatile DatabaseReader GEO_READER;

    private static DatabaseReader getGeoReader() {
        if (GEO_READER == null) {
            synchronized (PingUtil.class) {
                if (GEO_READER == null) {
                    try (InputStream dbStream = PingUtil.class.getClassLoader().getResourceAsStream("GeoLite2-City.mmdb")) {
                        if (dbStream == null) {
                            log.error("GeoLite2-City.mmdb 文件未找到，请放到 resources 目录下");
                            return null;
                        }
                        GEO_READER = new DatabaseReader.Builder(dbStream).build();
                        log.debug("GeoLite2 数据库加载成功");
                    } catch (Exception e) {
                        log.warn("加载 GeoLite2 数据库失败: {}", e.getMessage());
                    }
                }
            }
        }
        return GEO_READER;
    }

    /**
     * 执行 ping 请求
     * @param host 目标主机
     * @param areas 区域列表
     * @return 响应结果
     */
    public static String doPing(String host, String... areas) {
        // 构建请求参数
        Map<String, Object> paramMap = new HashMap<>();
        paramMap.put("v", 4);  // IPv4
        paramMap.put("a", "send");
        paramMap.put("host", host);
        paramMap.put("dns", "");

        // 添加区域参数
        for (String area : areas) {
            paramMap.put("area[]", area);
        }

        try {
            // 发送请求
            return HttpRequest.get(BASE_URL)
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
                    .header("Accept", "application/json, text/javascript, */*; q=0.01")
                    .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
                    .header("X-Requested-With", "XMLHttpRequest")
                    .header("Referer", "https://tools.ipip.net/ping.php")
                    .form(paramMap)  // 使用表单方式提交
                    .execute()
                    .body();
        } catch (Exception e) {
            log.error("Ping request failed for host: {}", host, e);
            return null;
        }
    }

    public static String doPing2(String host, String... areas) {
        try {
            StringBuilder urlBuilder = new StringBuilder(BASE_URL);
            urlBuilder.append("?v=4")
                    .append("&a=send")
                    .append("&host=").append(URLEncoder.encode(host, "UTF-8"))
                    .append("&dns=");

            // 添加多个 area[] 参数
            for (String area : areas) {
                urlBuilder.append("&area[]=").append(URLEncoder.encode(area, "UTF-8"));
            }

            return HttpRequest.get(urlBuilder.toString())
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
                    .header("Accept", "application/json, text/javascript, */*; q=0.01")
                    .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
                    .header("X-Requested-With", "XMLHttpRequest")
                    .header("Referer", "https://tools.ipip.net/ping.php")
                    .execute()
                    .body();
        } catch (Exception e) {
            log.error("Ping request failed for host: {}", host, e);
            return null;
        }
    }

    /**
     * 测试中国和港澳台区域
     */
    public static String pingChinaAndHMT(String host) {
        return doPing2(host, "china", "hmt");
    }

    /**
     * 测试所有区域
     */
    public static String pingAllAreas(String host) {
        return doPing(host,
                "china", "hmt", "asia", "europe",
                "africa", "na", "sa", "da");
    }

    /**
     * 测试自定义区域
     */
    public static String pingCustomAreas(String host, List<String> areas) {
        return doPing(host, areas.toArray(new String[0]));
    }


    public static void main(String[] args) {
        /*String result1 = PingUtil.pingChinaAndHMT("64.110.72.221");
        System.out.println("China and HMT result:");
        System.out.println(result1);

        List<PingResult> results = parsePingResults(result1);
        //System.out.println(results);
        final String s = JSONUtil.toJsonPrettyStr(results);
        System.out.println(s);*/

        // 测试所有区域
        /*String result2 = PingUtil.pingAllAreas("64.110.72.221");
        System.out.println("All areas result:");
        System.out.println(result2);
        List<PingResult> resultList = parsePingResults(result2);
        final String s = JSONUtil.toJsonPrettyStr(resultList);
        System.out.println(s);*/

        // 测试自定义区域
        List<String> customAreas = new ArrayList<>();
        customAreas.add("china");
        //customAreas.add("hmt");//港澳台
        String result3 = PingUtil.pingCustomAreas("47.79.95.189", customAreas);
        //String result4 = PingUtil.pingChinaAndHMT("64.110.72.221");
        System.out.println("Custom areas result:");
        //System.out.println(result3);
        final Map<String, List<PingResult>> stringListMap = parsePingResults(result3);
        final Map<String, Map<String, ProvinceCarrierResult>> stringMapMap = convertToProvinceResults(stringListMap);
        final String s = JSONUtil.toJsonPrettyStr(stringMapMap);
        System.out.println(s);
    }

    /**
     * 根据IP获取经纬度（GeoLite2）
     * @param ip IP地址
     * @return double[纬度, 经度]，查询失败返回 null
     */
    public static double[] getLatLonByGeoIP(String ip) {
        try {
            if (ip == null || ip.isEmpty()) {
                log.warn("IP 地址为空");
                return null;
            }

            // 内网 IP 直接忽略
            if (isPrivateIP(ip)) {
                log.debug("内网 IP [{}] 无法获取经纬度", ip);
                return null;
            }

            // 复用单例 DatabaseReader
            DatabaseReader reader = getGeoReader();
            if (reader == null) {
                log.error("GeoLite2-City.mmdb 未加载，无法查询地理信息");
                return null;
            }

            InetAddress ipAddress = InetAddress.getByName(ip);
            CityResponse response = reader.city(ipAddress);

            if (response == null || response.getLocation() == null) {
                log.warn("未查询到 IP [{}] 的地理位置信息", ip);
                return null;
            }

            double latitude = response.getLocation().getLatitude();
            double longitude = response.getLocation().getLongitude();

            return new double[]{latitude, longitude};
        } catch (Exception e) {
            log.error("根据 IP [{}] 获取经纬度失败: {}", ip, e.getMessage());
            return null;
        }
    }

    /**
     * 根据 IP 获取地理位置详细信息（含经纬度 + 国家、省、市）
     * @param ip IP地址
     * @return 位置信息字符串，例如：中国北京市北京市（纬度:39.9042, 经度:116.4074）
     */
    public static String getGeoInfoByIP(String ip) {
        try {
            if (isPrivateIP(ip)) return "内网地址";

            DatabaseReader reader = getGeoReader();
            if (reader == null) return "未知位置";

            InetAddress ipAddress = InetAddress.getByName(ip);
            CityResponse response = reader.city(ipAddress);
            String country = response.getCountry().getNames().getOrDefault("zh-CN", response.getCountry().getName());
            String province = response.getMostSpecificSubdivision().getNames().getOrDefault("zh-CN", response.getMostSpecificSubdivision().getName());
            String city = response.getCity().getNames().getOrDefault("zh-CN", response.getCity().getName());

            return (country == null ? "" : country)
                    + (province == null ? "" : province)
                    + (city == null ? "" : city);
        } catch (Exception e) {
            return "未知位置";
        }
    }



    public static boolean isPrivateIP(String ip) {
        try {
            InetAddress address = InetAddress.getByName(ip);
            return address.isSiteLocalAddress()       // 10.x.x.x, 172.16-31.x.x, 192.168.x.x
                    || address.isLinkLocalAddress()   // 169.254.x.x
                    || address.isLoopbackAddress();   // 127.x.x.x / ::1
        } catch (Exception e) {
            return false;
        }
    }

    /**
    * @Description: 获取ip和ip所属的地理位置
    * @Param: []
    * @return: java.lang.String
    * @Author: doubleDimple
    * @Date: 11/1/25 8:14 AM
    */
    public static String getCurrentPublicIpAndAddress(HttpServletRequest request){
        String geoInfoByIP = "";
        try {
            String publicIp = IpUtils.getClientIpAddress(request);
            geoInfoByIP = publicIp+"/"+getGeoInfoByIP(publicIp);
        } catch (Exception e) {
            log.warn("获取地理位置信息失败");
        }
        return geoInfoByIP;
    }

}
