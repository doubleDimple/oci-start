package com.doubledimple.ocicommon.enums;

public enum TaskStatusEnum {
    PENDING(1, "待执行"),
    RUNNING(2, "执行中"),
    COMPLETED(3, "已完成"),
    FAILED(4, "执行失败");

    private final Integer code;
    private final String description;

    TaskStatusEnum(int code, String description) {
        this.code = code;
        this.description = description;
    }

    public Integer getCode() {
        return code;
    }

    public String getDescription() {
        return description;
    }

    public static TaskStatusEnum getByCode(int code) {
        for (TaskStatusEnum status : values()) {
            if (status.getCode() == code) {
                return status;
            }
        }
        return PENDING; // 默认返回PENDING状态
    }
}
