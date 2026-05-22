package com.doubledimple.ociserver.pojo.response;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class CloudCostItem {

    /** 云厂商：oci/aws/tencent/cloudflare… */
    private int cloudType;

    /** 资源唯一 ID */
    private String resourceId;

    /** 资源类型（实例/磁盘/网络） */
    private String resourceType;

    /** 产品类型 / SKU（例如：Standard-A1, Block Volume, Outbound Traffic） */
    private String skuName;

    /** 日期（yyyy-MM-dd） */
    private String day;

    /** 当天费用（美元） */
    private BigDecimal cost;
}
