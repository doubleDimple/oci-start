package com.doubledimple.ocicommon.enums.oci;

public enum MetricsTypeEnum {
    NETWORK_BYTES_IN("NetworksBytesIn", "Network Receive Bytes","入站"),
    NETWORK_BYTES_OUT("NetworksBytesOut", "Network Transmit Bytes","出站");

    private final String metricName;
    private final String displayName;
    private final String name;

    MetricsTypeEnum(String metricName, String displayName,String name) {
        this.metricName = metricName;
        this.displayName = displayName;
        this.name = name;
    }

    public String getMetricName() {
        return metricName;
    }

    public String getDisplayName() {
        return displayName;
    }
    public String getName() {
        return name;
    }
}
