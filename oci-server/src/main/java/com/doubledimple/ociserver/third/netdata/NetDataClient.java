package com.doubledimple.ociserver.third.netdata;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import java.util.AbstractMap;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.stream.Collectors;

/**
 * NetData API客户端服务
 * 用于获取Master和所有Child节点的监控数据
 */
@Service
@Slf4j
public class NetDataClient {


    @Resource
    private ThreadPoolExecutor executorService;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    public NetDataClient() {
        this.restTemplate = new RestTemplate();
        this.objectMapper = new ObjectMapper();
    }

    /**
     * 获取Master节点URL
     */
    private String getMasterUrl(String masterHost, int masterPort) {
        return String.format("http://%s:%d", masterHost, masterPort);
    }

    /**
     * 获取所有连接的主机列表
     */
    public List<String> getAllHosts(String masterHost, int masterPort) {
        try {
            String url = getMasterUrl(masterHost, masterPort) + "/api/v1/charts";
            String response = restTemplate.getForObject(url, String.class);

            JsonNode root = objectMapper.readTree(response);
            Set<String> hosts = new HashSet<>();

            // 遍历所有charts，提取host信息
            Iterator<String> chartNames = root.fieldNames();
            while (chartNames.hasNext()) {
                String chartName = chartNames.next();
                JsonNode chart = root.get(chartName);
                if (chart.has("host")) {
                    String host = chart.get("host").asText();
                    hosts.add(host);
                }
            }

            List<String> hostList = new ArrayList<>(hosts);
            log.info("发现 {} 个主机节点: {}", hostList.size(), hostList);
            return hostList;

        } catch (Exception e) {
            log.error("获取主机列表失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 获取指定主机的基本信息
     * (可以查询到host)
     * http://27.106.122.104:19999/api/v1/info
     */
    public HostInfo getHostInfo(String masterHost, int masterPort, String hostname) {
        try {
            String url = getMasterUrl(masterHost, masterPort) + "/api/v1/info";
            if (hostname != null && !hostname.isEmpty()) {
                url += "?host=" + hostname;
            }

            String response = restTemplate.getForObject(url, String.class);
            JsonNode root = objectMapper.readTree(response);

            HostInfo hostInfo = new HostInfo();
            hostInfo.setHostname(hostname);
            hostInfo.setVersion(root.path("version").asText());
            hostInfo.setOs(root.path("os_name").asText());
            hostInfo.setKernel(root.path("kernel_name").asText());
            hostInfo.setUptime(root.path("uptime").asLong());

            return hostInfo;

        } catch (Exception e) {
            log.error("获取主机 {} 信息失败", hostname, e);
            return null;
        }
    }

    /**
     * 获取指定主机的CPU使用率
     */
    public MonitoringData getCpuUsage(String masterHost, int masterPort, String hostname, int points) {
        return getChartData(masterHost, masterPort, hostname, "system.cpu", points);
    }

    /**
     * 获取指定主机的内存使用情况
     */
    public MonitoringData getMemoryUsage(String masterHost, int masterPort, String hostname, int points) {
        return getChartData(masterHost, masterPort, hostname, "system.ram", points);
    }

    /**
     * 获取指定主机的磁盘使用情况
     */
    public MonitoringData getDiskUsage(String masterHost, int masterPort, String hostname, int points) {
        return getChartData(masterHost, masterPort, hostname, "disk_space._", points);
    }

    /**
     * 获取指定主机的网络流量
     */
    public MonitoringData getNetworkTraffic(String masterHost, int masterPort, String hostname, int points) {
        return getChartData(masterHost, masterPort, hostname, "system.net", points);
    }

    /**
     * 获取指定图表的数据
     */
    public MonitoringData getChartData(String masterHost, int masterPort, String hostname, String chart, int points) {
        try {
            String url = getMasterUrl(masterHost, masterPort) + "/api/v1/data";
            url += "?chart=" + chart;
            url += "&points=" + points;
            if (hostname != null && !hostname.isEmpty()) {
                url += "&host=" + hostname;
            }

            String response = restTemplate.getForObject(url, String.class);
            JsonNode root = objectMapper.readTree(response);

            MonitoringData data = new MonitoringData();
            data.setHostname(hostname);
            data.setChart(chart);
            data.setPoints(points);

            // 解析labels和data
            if (root.has("labels")) {
                List<String> labels = new ArrayList<>();
                for (JsonNode label : root.get("labels")) {
                    labels.add(label.asText());
                }
                data.setLabels(labels);
            }

            if (root.has("data")) {
                List<List<Double>> dataPoints = new ArrayList<>();
                for (JsonNode dataPoint : root.get("data")) {
                    List<Double> point = new ArrayList<>();
                    for (JsonNode value : dataPoint) {
                        if (value.isNull()) {
                            point.add(null);
                        } else {
                            point.add(value.asDouble());
                        }
                    }
                    dataPoints.add(point);
                }
                data.setData(dataPoints);
            }

            return data;

        } catch (Exception e) {
            log.error("获取图表数据失败: hostname={}, chart={}", hostname, chart, e);
            return null;
        }
    }

    /**
     * 获取所有主机的CPU使用率
     */
    public Map<String, MonitoringData> getAllHostsCpuUsage(String masterHost, int masterPort, int points) {
        List<String> hosts = getAllHosts(masterHost, masterPort);
        return getMultipleHostsData(masterHost, masterPort, hosts, "system.cpu", points);
    }

    /**
     * 获取所有主机的内存使用情况
     */
    public Map<String, MonitoringData> getAllHostsMemoryUsage(String masterHost, int masterPort, int points) {
        List<String> hosts = getAllHosts(masterHost, masterPort);
        return getMultipleHostsData(masterHost, masterPort, hosts, "system.ram", points);
    }

    /**
     * 获取多个主机的相同指标数据（并行获取）
     */
    public Map<String, MonitoringData> getMultipleHostsData(String masterHost, int masterPort, List<String> hosts, String chart, int points) {
        List<CompletableFuture<AbstractMap.SimpleEntry<String, MonitoringData>>> futures = hosts.stream()
                .map(host -> CompletableFuture.supplyAsync(() -> {
                    MonitoringData data = getChartData(masterHost, masterPort, host, chart, points);
                    return new AbstractMap.SimpleEntry<>(host, data);
                }, executorService))
                .collect(Collectors.toList());

        return futures.stream()
                .map(CompletableFuture::join)
                .filter(entry -> entry.getValue() != null)
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        Map.Entry::getValue
                ));
    }

    /**
     * 获取完整的集群监控数据
     */
    public ClusterMonitoringData getClusterMonitoringData(String masterHost, int masterPort, int points) {
        List<String> hosts = getAllHosts(masterHost, masterPort);

        ClusterMonitoringData clusterData = new ClusterMonitoringData();
        clusterData.setTimestamp(System.currentTimeMillis());
        clusterData.setTotalHosts(hosts.size());

        // 并行获取所有主机的多种监控数据
        Map<String, CompletableFuture<HostMonitoringData>> futures = hosts.stream()
                .collect(Collectors.toMap(
                        host -> host,
                        host -> CompletableFuture.supplyAsync(() -> {
                            HostMonitoringData hostData = new HostMonitoringData();
                            hostData.setHostname(host);
                            hostData.setHostInfo(getHostInfo(masterHost, masterPort, host));
                            hostData.setCpuData(getCpuUsage(masterHost, masterPort, host, points));
                            hostData.setMemoryData(getMemoryUsage(masterHost, masterPort, host, points));
                            hostData.setNetworkData(getNetworkTraffic(masterHost, masterPort, host, points));
                            return hostData;
                        }, executorService)
                ));

        Map<String, HostMonitoringData> hostsData = futures.entrySet().stream()
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        entry -> entry.getValue().join()
                ));

        clusterData.setHostsData(hostsData);

        log.info("获取集群监控数据完成，包含 {} 个主机", hostsData.size());
        return clusterData;
    }

    /**
     * 获取可用的图表列表
     */
    public List<String> getAvailableCharts(String masterHost, int masterPort, String hostname) {
        try {
            String url = getMasterUrl(masterHost, masterPort) + "/api/v1/charts";
            if (hostname != null && !hostname.isEmpty()) {
                url += "?host=" + hostname;
            }

            String response = restTemplate.getForObject(url, String.class);
            JsonNode root = objectMapper.readTree(response);

            List<String> charts = new ArrayList<>();
            Iterator<String> chartNames = root.fieldNames();
            while (chartNames.hasNext()) {
                charts.add(chartNames.next());
            }

            return charts;

        } catch (Exception e) {
            log.error("获取图表列表失败: hostname={}", hostname, e);
            return new ArrayList<>();
        }
    }

    // 数据模型类
    @Data
    public static class HostInfo {
        private String hostname;
        private String version;
        private String os;
        private String kernel;
        private Long uptime;
    }

    @Data
    public static class MonitoringData {
        private String hostname;
        private String chart;
        private int points;
        private List<String> labels;
        private List<List<Double>> data;

        // 获取最新数据点
        public List<Double> getLatestData() {
            if (data != null && !data.isEmpty()) {
                return data.get(0);
            }
            return null;
        }

        // 获取平均值
        public Map<String, Double> getAverageValues() {
            if (data == null || data.isEmpty() || labels == null) {
                return new HashMap<>();
            }

            Map<String, Double> averages = new HashMap<>();
            for (int i = 1; i < labels.size(); i++) { // 跳过时间戳列
                String label = labels.get(i);
                double sum = 0;
                int count = 0;

                for (List<Double> dataPoint : data) {
                    if (i < dataPoint.size() && dataPoint.get(i) != null) {
                        sum += dataPoint.get(i);
                        count++;
                    }
                }

                if (count > 0) {
                    averages.put(label, sum / count);
                }
            }

            return averages;
        }
    }

    @Data
    public static class HostMonitoringData {
        private String hostname;
        private HostInfo hostInfo;
        private MonitoringData cpuData;
        private MonitoringData memoryData;
        private MonitoringData networkData;
        private MonitoringData diskData;
    }

    @Data
    public static class ClusterMonitoringData {
        private Long timestamp;
        private int totalHosts;
        private Map<String, HostMonitoringData> hostsData;

        // 获取集群CPU平均使用率
        public double getClusterCpuAverage() {
            return hostsData.values().stream()
                    .filter(host -> host.getCpuData() != null)
                    .mapToDouble(host -> {
                        Map<String, Double> avgValues = host.getCpuData().getAverageValues();
                        return avgValues.values().stream().mapToDouble(Double::doubleValue).sum();
                    })
                    .average()
                    .orElse(0.0);
        }
    }
}
