package com.doubledimple.ociserver.pojo.dto;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName AuditEventDto
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-31 11:24
 */
@Data
@AllArgsConstructor
public class OciAuditEventDto {
    private String eventType;       // 事件类型
    private String userName;        // 用户名称
    private String userType;        // 用户类型（authType）
    private String ipAddress;       // 来源IP
    private String clientEnv;       // 客户端环境
    private String eventTime;       // 事件时间
    private String responseStatus;  // 响应状态
}
