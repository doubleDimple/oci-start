package com.doubledimple.ociserver.enums;

import com.oracle.bmc.core.model.Shape;

import static com.oracle.bmc.core.model.Shape.BillingType.AlwaysFree;
import static com.oracle.bmc.core.model.Shape.BillingType.LimitedFree;

public enum ArchitectureEnum {


    AMD("AMD","VM.Standard.E2.1.Micro",AlwaysFree),

    ARM("ARM","VM.Standard.A1.Flex",LimitedFree),

    ;

    ArchitectureEnum(String type,String shapeDetail,Shape.BillingType billingType){
        this.type = type;
        this.shapeDetail = shapeDetail;
        this.billingType = billingType;
    }
    private String type;

    private String shapeDetail;

    private Shape.BillingType billingType;

    public String getType(){
        return type;
    }

    public String getShapeDetail(){
        return shapeDetail;
    }

    public Shape.BillingType getBillingType(){
        return billingType;
    }

    public static ArchitectureEnum getType(String type){
        ArchitectureEnum[] values = ArchitectureEnum.values();
        for (ArchitectureEnum value : values) {
            if (value.getType().equals(type)){
                return value;
            }
        }
        return null;
    }
}
