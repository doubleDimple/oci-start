package com.doubledimple.ocicommon.param;

import com.alibaba.fastjson2.annotation.JSONField;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName OpenRegionNotify
 * @Description
 * @Author doubleDimple
 * @Date 2025-05-18 08:33
 */
@Data
public class OpenRegionNotify {

    private Long id;

    private String region;

    @JSONField(name = "architecture_type")
    private String architectureType;

    @JSONField(name = "open_time", format = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime openTime;

    @JSONField(name = "open_count")
    private Integer openCount;

    @JSONField(name = "update_time", format = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime updateTime;

    @JSONField(name = "create_time", format = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createTime;

    @JSONField(name = "last_notify_time", format = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime lastNotifyTime;

    @JSONField(name = "monthly_open_count")
    private Integer monthlyOpenCount;
}
