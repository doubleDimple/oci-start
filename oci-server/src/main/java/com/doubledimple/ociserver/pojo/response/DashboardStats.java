package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:10:26日 19:41
 */
@Data
public class DashboardStats {
    private long totalApiCalls;        // 总API次数
    private long totalBootInstances;   // 总Boot实例数
    private long totalAttempts;        // 总抢机次数
    private long successfulAttempts;   // 成功抢机次数
    private long successRate;   // 抢机成功率
    private long failCounts;    //总失败次数
}
