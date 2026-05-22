package com.doubledimple.ociserver.utils.oracle.vnic;

import lombok.Data;

import java.time.Instant;

/**
 * IPv6创建结果模型
 */
@Data
public class Ipv6CreationResult {
    private String ipv6Id;
    private String ipv6Address;
    private String vnicId;
    private boolean success;
    private String errorMessage;
    private Instant createdAt;

    public Ipv6CreationResult() {
        this.success = false;
        this.createdAt = Instant.now();
    }
}
