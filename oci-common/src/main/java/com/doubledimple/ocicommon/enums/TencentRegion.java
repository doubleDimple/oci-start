package com.doubledimple.ocicommon.enums;

public enum TencentRegion {
    AP_BEIJING("ap-beijing", "北京"),
    AP_SHANGHAI("ap-shanghai", "上海"),
    AP_GUANGZHOU("ap-guangzhou", "广州"),
    AP_SINGAPORE("ap-singapore", "新加坡"),
    NA_ASHBURN("na-ashburn", "弗吉尼亚"),
    EU_FRANKFURT("eu-frankfurt", "法兰克福");

    private final String code;
    private final String name;

    TencentRegion(String code, String name) {
        this.code = code;
        this.name = name;
    }

    public String getCode() {
        return code;
    }
    public String getName() {
        return name;
    }
    public static TencentRegion getByCode(String code) {
        for (TencentRegion value : values()) {
            if (value.code.equals(code)) {
                return value;
            }
        }
        return null;
    }
}
