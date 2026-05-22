package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName AuditLogRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-31 13:50
 */
@Data
public class AuditLogRequest {

    private String tenantId;
    private int days;
    private String pageToken;

    private String startDate;  // 开始日期
    private String endDate;    // 结束日期
}
