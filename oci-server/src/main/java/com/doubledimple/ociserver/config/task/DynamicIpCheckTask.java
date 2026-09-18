package com.doubledimple.ociserver.config.task;

import org.springframework.stereotype.Component;

/**
 * Compatibility entry for old settings. Network quality now uses explicit agent-side
 * measurements. Neither startup nor saving old settings may schedule IP replacement.
 */
@Component
public class DynamicIpCheckTask {

    /**
     * 更新IP检测间隔
     * @param interval 检测间隔（小时）
     * @param enabled 是否启用
     */
    public void updateCheckInterval(int interval, boolean enabled) {
        if (interval <= 0 || interval > 24) {
            throw new IllegalArgumentException("检测间隔必须在1-24小时之间");
        }

        // Intentionally no scheduler and no checkAllInstancesIpQuality invocation.
    }
}
