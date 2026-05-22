package com.doubledimple.ociserver.pojo.domain.query;

import lombok.Data;

import java.time.LocalDateTime;

/**
 * @author doubleDimple
 * @date 2024:11:25日 21:58
 */
@Data
public class BootInstanceQuery {
    private String userName;
    private String instanceId;
    private String state;
    private Long tenantId;
    private LocalDateTime createTime;
    // 根据需要添加其他查询字段
}
