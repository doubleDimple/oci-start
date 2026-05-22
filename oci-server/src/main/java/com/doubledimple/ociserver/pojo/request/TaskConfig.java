package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName TaskConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-01-03 21:13
 */
@Data
public class TaskConfig {
    private boolean enabled;
    private int executeHour;
    /**
     * 通知秘钥
     */
    private String notificationSecret;

    //账号测活
    private boolean enableAccountCheck;
    //抢机日志
    private boolean enableBootLog;
    //花费检测
    private boolean enableCostCheck;

}
