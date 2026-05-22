package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * @author doubleDimple
 * @date 2024:11:14日 23:42
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class IpVnicSwitchRequest {

    private String instanceId;
    private String vnicId;
    //实际是instancedetails的主键
    private Long tenantId;
    private String compartmentId;
    private List<String> cidrRanges;
    private String preferredIp;
}
