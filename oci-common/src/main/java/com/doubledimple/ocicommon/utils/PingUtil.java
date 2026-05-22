package com.doubledimple.ocicommon.utils;

import com.doubledimple.ocicommon.param.PingResult;
import com.doubledimple.ocicommon.param.PingStats;
import lombok.extern.slf4j.Slf4j;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName PingUtil
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-04-13 11:01
 */
@Slf4j
public class PingUtil {

    /**
     * 使用操作系统的 ping 命令检查目标 IP 地址是否可达
     *
     * @param ip 目标 IP 地址
     * @param timeout 超时时间，单位毫秒
     * @return 如果 IP 可达返回 true，否则返回 false
     */
    public static PingResult ping(String ip, int timeout) {
        int count = 5;
        String os = System.getProperty("os.name").toLowerCase();
        String command;

        if (os.contains("win")) {
            command = "ping -n " + count + " -w " + timeout + " " + ip;
        } else {
            command = "ping -c " + count + " -W " + (timeout / 1000) + " " + ip;
        }

        try {
            Process process = Runtime.getRuntime().exec(command);

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;

            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }

            int exitCode = process.waitFor();
            String outputStr = output.toString();

            // 解析ping结果
            PingStats stats = parsePingOutput(outputStr, os);

            // 修改判断逻辑：优先使用统计信息，其次使用exitCode
            boolean reachable;
            if (stats != null && stats.getTotalCount() > 0) {
                // 如果有统计信息，基于成功率判断（成功率大于0表示至少有包到达）
                reachable = stats.getSuccessRate() > 0;
                log.debug("基于统计判断 - 成功率:" + stats.getSuccessRate() + ", 可达:" + reachable);
            } else {
                // 备用方案：使用进程退出码
                reachable = exitCode == 0;
                log.debug("基于退出码判断 - exitCode:" + exitCode + ", 可达:" + reachable);
            }

            return new PingResult(ip, reachable, outputStr, stats);

        } catch (IOException | InterruptedException e) {
            return new PingResult(ip, false, "Error: " + e.getMessage(), null);
        }
    }

    /**
     * 检查目标 IP 是否可达，默认超时时间为5000毫秒
     *
     * @param ip 目标 IP 地址
     * @return PingResult
     */
    public static PingResult ping(String ip) {
        return ping(ip, 5000);  // 默认超时 5000ms
    }

    /**
     * 简单的boolean返回方法，兼容原有代码
     */
    public static boolean isReachable(String ip, int timeout) {
        return ping(ip, timeout).isReachable();
    }

    public static boolean isReachable(String ip) {
        return ping(ip).isReachable();
    }


    /**
     * 批量ping测试 - 顺序执行
     *
     * @param ipList IP列表
     * @param timeout 超时时间，单位毫秒
     * @return PingResult列表
     */
    public static List<PingResult> batchPing(List<String> ipList, int timeout) {
        List<PingResult> results = new ArrayList<>();
        for (String ip : ipList) {
            results.add(ping(ip, timeout));
        }
        return results;
    }

    /**
     * 批量ping测试 - 顺序执行，使用默认超时时间
     *
     * @param ipList IP列表
     * @return PingResult列表
     */
    public static List<PingResult> batchPing(List<String> ipList) {
        return batchPing(ipList, 5000);
    }

    /**
     * 批量ping测试 - 并发执行（推荐用于大量IP）
     *
     * @param ipList IP列表
     * @param timeout 超时时间，单位毫秒
     * @param threadCount 线程数量
     * @return PingResult列表
     */
    public static List<PingResult> batchPingConcurrent(List<String> ipList, int timeout, int threadCount) {
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);

        try {
            List<CompletableFuture<PingResult>> futures = ipList.stream()
                    .map(ip -> CompletableFuture.supplyAsync(() -> ping(ip, timeout), executor))
                    .collect(Collectors.toList());

            return futures.stream()
                    .map(CompletableFuture::join)
                    .collect(Collectors.toList());
        } finally {
            executor.shutdown();
        }
    }

    /**
     * 批量ping测试 - 并发执行，使用默认参数
     *
     * @param ipList IP列表
     * @return PingResult列表
     */
    public static List<PingResult> batchPingConcurrent(List<String> ipList) {
        return batchPingConcurrent(ipList, 5000, 5);
    }

    private static PingStats parsePingOutput(String output, String os) {
        PingStats stats = new PingStats();
        List<Long> responseTimes = new ArrayList<>();

        if (os.contains("win")) {
            // 解析Windows ping输出
            return parseWindowsPingOutput(output);
        } else {
            // 解析Linux/macOS ping输出
            return parseUnixPingOutput(output);
        }
    }

    private static PingStats parseWindowsPingOutput(String output) {
        PingStats stats = new PingStats();
        List<Long> responseTimes = new ArrayList<>();

        String[] lines = output.split("\n");
        int totalPackets = 0;
        int successPackets = 0;

        // 解析每行ping结果
        for (String line : lines) {
            line = line.trim();

            // 成功的ping: "来自 8.8.8.8 的回复: 字节=32 时间=14ms TTL=118"
            // 或英文版: "Reply from 8.8.8.8: bytes=32 time=14ms TTL=118"
            if (line.contains("来自") && line.contains("的回复") ||
                    line.contains("Reply from")) {
                successPackets++;
                totalPackets++;

                // 提取响应时间
                Long responseTime = extractResponseTime(line);
                if (responseTime != null) {
                    responseTimes.add(responseTime);
                }
            }
            // 失败的ping: "请求超时" 或 "Request timed out"
            else if (line.contains("请求超时") || line.contains("Request timed out") ||
                    line.contains("目标主机无法访问") || line.contains("Destination host unreachable")) {
                totalPackets++;
            }
            // 统计信息行: "数据包: 已发送 = 4，已接收 = 4，丢失 = 0 (0% 丢失)"
            else if (line.contains("已发送") || line.contains("Packets: Sent")) {
                // 可以从这里提取更准确的统计信息
                parseWindowsStats(line, stats);
            }
        }

        if (totalPackets == 0) totalPackets = 1; // 避免除零

        stats.setTotalCount(totalPackets);
        stats.setSuccessCount(successPackets);
        stats.setSuccessRate((double) successPackets / totalPackets);
        stats.setResponseTimes(responseTimes);
        calculateTimeStats(stats, responseTimes);

        return stats;
    }

    private static PingStats parseUnixPingOutput(String output) {
        PingStats stats = new PingStats();
        List<Long> responseTimes = new ArrayList<>();

        String[] lines = output.split("\n");
        int totalPackets = 0;
        int successPackets = 0;

        for (String line : lines) {
            line = line.trim();

            // 成功的ping: "64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=14.2 ms"
            if (line.contains("bytes from") && line.contains("time=")) {
                successPackets++;
                // 这里不应该增加totalPackets，因为统计行会提供准确的总数

                // 提取响应时间
                Long responseTime = extractResponseTime(line);
                if (responseTime != null) {
                    responseTimes.add(responseTime);
                }
            }
            // 统计信息行: "5 packets transmitted, 5 packets received, 0.0% packet loss"
            else if (line.contains("packets transmitted")) {
                parseUnixStats(line, stats);
                stats.setResponseTimes(responseTimes);
                calculateTimeStats(stats, responseTimes);
                return stats; // 找到统计行就直接返回
            }
            // 如果有round-trip统计行，也可以从中提取时间信息
            else if (line.contains("round-trip") && line.contains("min/avg/max")) {
                parseRoundTripStats(line, stats);
            }
        }

        // 如果没有找到统计行，使用计数的方式（备用方案）
        if (stats.getTotalCount() == 0) {
            stats.setTotalCount(Math.max(totalPackets, successPackets));
            stats.setSuccessCount(successPackets);
            if (stats.getTotalCount() > 0) {
                stats.setSuccessRate((double) successPackets / stats.getTotalCount());
            }
            stats.setResponseTimes(responseTimes);
            calculateTimeStats(stats, responseTimes);
        }

        return stats;
    }

    private static void parseWindowsStats(String statsLine, PingStats stats) {
        try {
            // 示例: "数据包: 已发送 = 4，已接收 = 4，丢失 = 0 (0% 丢失)"
            // 或英文: "Packets: Sent = 4, Received = 4, Lost = 0 (0% loss)"

            Pattern pattern = Pattern.compile("已发送\\s*=\\s*(\\d+).*已接收\\s*=\\s*(\\d+)|Sent\\s*=\\s*(\\d+).*Received\\s*=\\s*(\\d+)");
            Matcher matcher = pattern.matcher(statsLine);

            if (matcher.find()) {
                int sent = 0, received = 0;
                if (matcher.group(1) != null) { // 中文版本
                    sent = Integer.parseInt(matcher.group(1));
                    received = Integer.parseInt(matcher.group(2));
                } else if (matcher.group(3) != null) { // 英文版本
                    sent = Integer.parseInt(matcher.group(3));
                    received = Integer.parseInt(matcher.group(4));
                }

                stats.setTotalCount(sent);
                stats.setSuccessCount(received);
                stats.setSuccessRate((double) received / sent);
            }
        } catch (Exception e) {
            // 解析失败时保持默认值
        }
    }

    private static void parseUnixStats(String statsLine, PingStats stats) {
        try {
            // 示例: "5 packets transmitted, 5 packets received, 0.0% packet loss"
            // 或: "5 packets transmitted, 5 received, 0% packet loss, time 4005ms"
            Pattern pattern = Pattern.compile("(\\d+)\\s+packets transmitted,\\s*(\\d+)\\s+(?:packets\\s+)?received");
            Matcher matcher = pattern.matcher(statsLine);

            if (matcher.find()) {
                int transmitted = Integer.parseInt(matcher.group(1));
                int received = Integer.parseInt(matcher.group(2));

                stats.setTotalCount(transmitted);
                stats.setSuccessCount(received);
                stats.setSuccessRate((double) received / transmitted);

                log.debug("解析统计 - 发送:" + transmitted + ", 接收:" + received +
                        ", 成功率:" + stats.getSuccessRate()); // 调试信息
            }
        } catch (Exception e) {
            log.warn("Debug: 解析统计行失败: " + e.getMessage());
        }
    }

    private static void parseRoundTripStats(String roundTripLine, PingStats stats) {
        try {
            // 示例: "round-trip min/avg/max/stddev = 221.176/231.226/265.051/16.964 ms"
            Pattern pattern = Pattern.compile("min/avg/max(?:/stddev)?\\s*=\\s*([0-9.]+)/([0-9.]+)/([0-9.]+)");
            Matcher matcher = pattern.matcher(roundTripLine);

            if (matcher.find()) {
                long min = Math.round(Double.parseDouble(matcher.group(1)));
                long avg = Math.round(Double.parseDouble(matcher.group(2)));
                long max = Math.round(Double.parseDouble(matcher.group(3)));

                stats.setMinResponseTime(min);
                stats.setAvgResponseTime(avg);
                stats.setMaxResponseTime(max);

                log.info("Debug: 解析时间统计 - min:" + min + ", avg:" + avg + ", max:" + max);
            }
        } catch (Exception e) {
            log.info("Debug: 解析round-trip行失败: " + e.getMessage());
        }
    }

    private static Long extractResponseTime(String line) {
        try {
            // Windows中文: "时间=14ms" 或 Windows英文: "time=14ms"
            // Unix: "time=14.2 ms"
            Pattern pattern = Pattern.compile("(?:时间|time)\\s*=\\s*([0-9.]+)\\s*ms", Pattern.CASE_INSENSITIVE);
            Matcher matcher = pattern.matcher(line);

            if (matcher.find()) {
                return Math.round(Double.parseDouble(matcher.group(1)));
            }
        } catch (Exception e) {
            // 解析失败返回null
        }
        return null;
    }

    private static void calculateTimeStats(PingStats stats, List<Long> responseTimes) {
        if (responseTimes.isEmpty()) {
            return;
        }

        long sum = responseTimes.stream().mapToLong(Long::longValue).sum();
        long min = responseTimes.stream().mapToLong(Long::longValue).min().orElse(0);
        long max = responseTimes.stream().mapToLong(Long::longValue).max().orElse(0);

        stats.setAvgResponseTime(sum / responseTimes.size());
        stats.setMinResponseTime(min);
        stats.setMaxResponseTime(max);
    }
}
