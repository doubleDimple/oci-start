package com.doubledimple.ociserver.pojo.enums;

public enum BootInstanceStatusEnum {

    //0 : 未开机 1:开机中  2:已开机
    BOOT_NOT_START(0,"未开机"),

    BOOT_STARTING(1,"开机中"),

    BOOT_STARTED(2,"已开机"),

    ;

    BootInstanceStatusEnum(int code,String type){
        this.code = code;
        this.type = type;
    }
    private String type;

    private int code;


    public String getType(){
        return type;
    }

    public int getCode() {
        return code;
    }
}
