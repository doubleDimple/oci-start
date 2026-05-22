package com.doubledimple.ociserver.pojo.response;

import lombok.Builder;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName ProvinceCarrierResult
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 13:54
 */
@Data
@Builder
public class ProvinceCarrierResult {
    private String province;       // 省份
    private String carrier;        // 运营商
    private String location;       // 具体地点
    private String ip;            // IP
    private int ttl;             // TTL
    private String loss;         // 丢包率
    private String latency;      // 延迟
    private Double min;          // 最小值(转为double便于比较)
    private Double max;          // 最大值
}
