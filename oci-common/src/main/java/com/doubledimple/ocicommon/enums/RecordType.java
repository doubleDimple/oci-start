package com.doubledimple.ocicommon.enums;

/**
 * DNS记录类型枚举
 */
public  enum RecordType {
    A("A"),
    AAAA("AAAA"),
    CNAME("CNAME"),
    MX("MX"),
    TXT("TXT"),
    NS("NS"),
    SRV("SRV"),
    PTR("PTR"),
    SOA("SOA"),
    CAA("CAA"),
    //加速域名类型
    SP_DOMAIN("SP_DOMAIN")

    ;


    private final String value;

    RecordType(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }

    public static RecordType fromValue(String value) {
        for (RecordType type : RecordType.values()) {
            if (type.value.equals(value)) {
                return type;
            }
        }
        return null;
    }
}
