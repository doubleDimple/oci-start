package com.doubledimple.ocicommon.enums.oci;

public enum TrafficPeriod {

    /**
     * 按天聚合
     */
    ONE_DAY("1d"),

    /**
     * 按小时聚合
     */
    ONE_HOUR("1h"),

    /**
     * 按 10 分钟聚合
     */
    TEN_MINUTES("10m"),

    /**
     * 按 5 分钟聚合
     */
    FIVE_MINUTES("5m"),

    /**
     * 按 1 分钟聚合
     */
    ONE_MINUTE("1m");

    private final String value;

    TrafficPeriod(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
