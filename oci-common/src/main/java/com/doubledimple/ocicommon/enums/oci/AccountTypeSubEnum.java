package com.doubledimple.ocicommon.enums.oci;

public enum AccountTypeSubEnum {

    PERSONAL("PERSONAL", "个人"),
    CORPORATE("CORPORATE", "公司"),
    CORPORAsTE_SUBMITTED("CORPORATE_SUBMITTED","正在审核中的企业"),

    ;

    private final String code;
    private final String displayName;

    AccountTypeSubEnum(String code, String displayName) {
        this.code = code;
        this.displayName = displayName;
    }

    public String getCode() {
        return code;
    }

    public String getDisplayName() {
        return displayName;
    }

    public static String getByCode(String code) {
        for (AccountTypeSubEnum value : values()) {
            if (value.getCode().equals(code)) {
                return value.displayName;
            }
        }
        return "";
    }
}
