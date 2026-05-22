package com.doubledimple.ocicommon.enums;

public enum BootInstanceStatusEnum {

    ////0 : 未开机 1:开机中  2:已开机
    //未开机
    NOT_OPEN (0,"未执行","未开机"),
    OPENING (1,"执行中","开机中"),
    OPENED (2,"已完成","已开机"),

    ;

    private final int type;
    private final String name;
    private final String des;
    BootInstanceStatusEnum(int type, String name, String des) {
        this.type = type;
        this.name = name;
        this.des = des;
    }

    public int getType() {
        return type;
    }

    public String getName() {
        return name;
    }

    public String getDes() {
        return des;
    }


    public static BootInstanceStatusEnum getStatus(int type) {
        for (BootInstanceStatusEnum cloudTypeEnum : BootInstanceStatusEnum.values()) {
            if (cloudTypeEnum.getType() == type) {
                return cloudTypeEnum;
            }
        }
        return null;
    }
}
