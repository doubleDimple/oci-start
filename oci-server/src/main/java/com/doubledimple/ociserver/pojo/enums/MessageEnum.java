package com.doubledimple.ociserver.pojo.enums;


public enum MessageEnum {


    TELEGRAM("TELEGRAM"),

    DING_DING("DING_DING"),

    BARK("bark"),

    ALL_SMS("ALL_SMS"),

    FEISHU("feishu"),

    ;

    MessageEnum(String type){
        this.type = type;
    }
    private String type;


    public String getType(){
        return type;
    }

}
