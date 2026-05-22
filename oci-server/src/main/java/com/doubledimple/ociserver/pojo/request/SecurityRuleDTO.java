package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @author doubleDimple
 * @date 2024:11:28日 21:07
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class SecurityRuleDTO {
    private String id;
    private String type; // ingress 或 egress
    private String protocol;
    private String source;
    private String ports;
    private Long tenantId;
    private String icmpType; // 新增的ICMP类型字段

}
