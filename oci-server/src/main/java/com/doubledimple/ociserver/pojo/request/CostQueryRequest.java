package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName CostQueryRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-30 10:09
 */
@Data
public class CostQueryRequest {

    private String tenantId;

    private String startDate;  // 开始日期
    private String endDate;    // 结束日期
}
