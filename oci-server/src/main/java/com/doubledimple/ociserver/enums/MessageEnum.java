package com.doubledimple.ociserver.enums;

import com.oracle.bmc.core.model.Shape;

import static com.oracle.bmc.core.model.Shape.BillingType.AlwaysFree;
import static com.oracle.bmc.core.model.Shape.BillingType.LimitedFree;

public enum MessageEnum {


    TELEGRAM("TELEGRAM"),

    DING_DING("DING_DING"),

    ;

    MessageEnum(String type){
        this.type = type;
    }
    private String type;


    public String getType(){
        return type;
    }

}
