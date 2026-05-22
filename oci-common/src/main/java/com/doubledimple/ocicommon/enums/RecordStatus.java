package com.doubledimple.ocicommon.enums;

public enum RecordStatus {
    ACTIVE("正常","pending"),
    INACTIVE("停用","offline"),
    PENDING("待处理","pending"),
    ERROR("错误","pending"),
    SYNCING("同步中","pending");

    private final String displayName;
    private final String name;

    RecordStatus(String displayName,String name) {
        this.displayName = displayName;
        this.name = name;
    }

    public String getDisplayName() {
        return displayName;
    }

    public String getName() {
        return name;
    }

    public static RecordStatus getByName(String name) {
        for (RecordStatus status : RecordStatus.values()) {
            if (status.getName().equals(name)) {
                return status;
            }
        }
        return RecordStatus.INACTIVE;
    }
}
