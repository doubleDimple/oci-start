package com.doubledimple.ocicommon.enums;

import lombok.Getter;

@Getter
public enum DbActionEnum {
    /**
     * 开启数据库
     */
    START("start", "开启数据库"),

    /**
     * 重启数据库
     */
    RESTART("restart", "重启数据库"),

    /**
     * 删除数据库
     */
    DELETE("delete", "删除数据库");

    private final String action;
    private final String description;

    DbActionEnum(String action, String description) {
        this.action = action;
        this.description = description;
    }

    /**
     * 根据字符串获取枚举对象
     */
    public static DbActionEnum fromString(String action) {
        for (DbActionEnum b : DbActionEnum.values()) {
            if (b.action.equalsIgnoreCase(action)) {
                return b;
            }
        }
        return null;
    }
}
