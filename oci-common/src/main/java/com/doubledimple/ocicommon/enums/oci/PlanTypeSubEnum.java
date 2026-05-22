package com.doubledimple.ocicommon.enums.oci;

public enum PlanTypeSubEnum {
    FREE_TIER("FREE_TIER", "免费账号"),
    PAYG("PAYG", "升级账号");

    private final String code;
    private final String displayName;

    PlanTypeSubEnum(String code, String displayName) {
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
        for (PlanTypeSubEnum planTypeEnum : PlanTypeSubEnum.values()) {
            if (planTypeEnum.getCode().equals(code)) {
                return planTypeEnum.getDisplayName();
            }
        }
        return "";
    }
}
