package com.doubledimple.ocicommon.enums.oci;

/** 
* @Description:  流量监控类型
* @Param:  
* @return:  
* @Author doubleDimple
* @Date: 3/2/25 10:54 AM
*/
public enum MetricsQueryGranularityEnum {
    HOURLY("1h"),
    DAILY("1d");

    private final String value;

    MetricsQueryGranularityEnum(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
