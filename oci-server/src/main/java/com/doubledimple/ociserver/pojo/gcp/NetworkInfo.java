package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * GCP网络信息
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class NetworkInfo {
    private String kind;
    private String id;
    private String creationTimestamp;
    private String name;
    private String description;
    private String selfLink;
    private Boolean autoCreateSubnetworks;
    private List<String> subnetworks;
    private String routingConfig;
    private Integer mtu;
    private String gatewayIPv4;
    private String networkFirewallPolicyEnforcementOrder;
}
