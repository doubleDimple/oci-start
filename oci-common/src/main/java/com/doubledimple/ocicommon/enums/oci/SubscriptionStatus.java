package com.doubledimple.ocicommon.enums.oci;

public enum SubscriptionStatus {

    READY("READY", "已就绪"),
    IN_PROGRESS("IN_PROGRESS", "进行中"),
    PENDING("PENDING", "等待中"),
    FAILED("FAILED", "失败");

    private final String value;
    private final String description;

    SubscriptionStatus(String value, String description) {
        this.value = value;
        this.description = description;
    }

    public String getValue() {
        return value;
    }

    public String getDescription() {
        return description;
    }
}
