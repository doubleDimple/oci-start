package com.doubledimple.ocicommon.param;

/**
 * @version 1.0.0
 * @ClassName PingResult
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-04 17:32
 */
public class PingResult {

    private String ip;
    private boolean reachable;
    private String statistics;

    private PingStats stats; // 新增统计信息



    public PingResult(String ip, boolean reachable, String statistics) {
        this.ip = ip;
        this.reachable = reachable;
        this.statistics = statistics;
    }

    public PingResult(String ip, boolean reachable, String statistics, PingStats stats) {
        this.ip = ip;
        this.reachable = reachable;
        this.statistics = statistics;
        this.stats = stats;
    }

    public String getIp() {
        return ip;
    }

    public boolean isReachable() {
        return reachable;
    }

    public String getStatistics() {
        return statistics;
    }

    public PingStats getStats() {
        return stats;
    }

    @Override
    public String toString() {
        return ip + " - " + (reachable ? "可达" : "不可达");
    }
}
