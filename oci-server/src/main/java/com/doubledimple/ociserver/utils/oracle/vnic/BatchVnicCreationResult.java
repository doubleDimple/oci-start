package com.doubledimple.ociserver.utils.oracle.vnic;

import lombok.Data;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName BatchVnicCreationResult
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-16 16:36
 */
@Data
public class BatchVnicCreationResult {
    private String instanceId;
    private String instanceDisplayName;
    private int requestedVnicCount;
    private int requestedIpv6CountPerVnic;
    private int successfulVnicCount;
    private int totalIpv6Count;
    private List<VnicCreationResult> vnicResults;
    private boolean allSuccessful;
    private String summary;
    private Instant createdAt;
    private long totalExecutionTimeMs;

    public BatchVnicCreationResult() {
        this.vnicResults = new ArrayList<>();
        this.allSuccessful = true;
        this.createdAt = Instant.now();
    }
}
