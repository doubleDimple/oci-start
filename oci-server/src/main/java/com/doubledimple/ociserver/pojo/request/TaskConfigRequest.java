package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName TaskConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-01-03 21:13
 */
@Data
public class TaskConfigRequest {
    private boolean enabled;
    private int executeHour;
    /**
     * 通知秘钥
     */
    private String notificationSecret;

    private boolean enableAccountCheck;
    private boolean enableBootLog;
    private boolean enableCostCheck;

}
