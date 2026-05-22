package com.doubledimple.ociserver.pojo.response;

import com.doubledimple.ocicommon.enums.oci.SubscriptionStatus;
import lombok.Data;

/**
 *
 */
@Data
public class RegionSubscriptionResult {

    private boolean success;
    private String message;
    private String regionKey;
    private String regionName;
    private SubscriptionStatus status;
    private String subscriptionId;

    public RegionSubscriptionResult(boolean success, String message) {
        this.success = success;
        this.message = message;
    }

    public RegionSubscriptionResult(boolean success, String message, String regionKey, String regionName) {
        this.success = success;
        this.message = message;
        this.regionKey = regionKey;
        this.regionName = regionName;
    }
}
