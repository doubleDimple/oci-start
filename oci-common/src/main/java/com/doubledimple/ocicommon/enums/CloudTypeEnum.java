package com.doubledimple.ocicommon.enums;

public enum CloudTypeEnum {

    ORACLE_CLOUD (1,"ORACLE CLOUD","甲骨文云"),
    GOOGLE_CLOUD (2,"GOOGLE CLOUD","谷歌云"),
    AZURE_CLOUD (3,"AMAZON CLOUD","微软云" ),
    AMAZON_CLOUD (4,"AMAZON CLOUD","亚马逊云" ),

    ;

    private final int type;
    private final String name;
    private final String des;
    CloudTypeEnum(int type,String name,String des) {
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


    public static CloudTypeEnum getCloudTypeEnum(int type) {
        for (CloudTypeEnum cloudTypeEnum : CloudTypeEnum.values()) {
            if (cloudTypeEnum.getType() == type) {
                return cloudTypeEnum;
            }
        }
        return null;
    }
}
