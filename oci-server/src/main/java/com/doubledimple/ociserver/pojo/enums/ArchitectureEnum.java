package com.doubledimple.ociserver.pojo.enums;

import com.oracle.bmc.core.model.Shape;

import static com.oracle.bmc.core.model.Shape.BillingType.AlwaysFree;
import static com.oracle.bmc.core.model.Shape.BillingType.LimitedFree;
import static com.oracle.bmc.core.model.Shape.BillingType.Paid;

public enum ArchitectureEnum {

    //BM.Standard.E5.192  paid  裸金属
    //BM.Standard.E4.128  paid  裸金属
    //VM.Standard.E4.Flex paid
    //VM.Standard3.Flex   paid
    //VM.Standard.E5.Flex paid

    //VM.Standard.A1.Flex LIMITED_FREE
    //

    AMD("AMD","VM.Standard.E2.1.Micro",AlwaysFree,"AMD"),

    ARM("ARM","VM.Standard.A1.Flex",LimitedFree,"ARM"),

    ARM_PAID_A2("ARM_PAID_A2","VM.Standard.A2.Flex",Paid,"ARM"),

    AMD_PAID_E3("AMD_PAID_E3","VM.Standard3.Flex",Paid,"AMD"),
    AMD_PAID_E4("AMD_PAID_E4","VM.Standard.E4.Flex",Paid,"AMD"),
    AMD_PAID_E5("AMD_PAID_E5","VM.Standard.E5.Flex",Paid,"AMD"),

    AMD_PAID_E4_BM("AMD_PAID_E4_BM","BM.Standard.E4.128",Paid,"AMD"),

    AMD_PAID_E5_BM("AMD_PAID_E5_BM","BM.Standard.E5.192",Paid,"AMD"),

    ;

    ArchitectureEnum(String type,String shapeDetail,Shape.BillingType billingType,String backUpName){
        this.type = type;
        this.shapeDetail = shapeDetail;
        this.billingType = billingType;
        this.backUpName = backUpName;
    }
    private String type;

    private String shapeDetail;
    private String backUpName;

    private Shape.BillingType billingType;

    /**
    * free arm:1 free amd:2 paid: 0
    */
    public static Integer freeArmOrAmd(String architecture) {
         ArchitectureEnum type = getType(architecture);
         if (type.equals(ArchitectureEnum.ARM)){
             return 1;
         }else if (type.equals(ArchitectureEnum.AMD)){
             return 2;
        }else{
             return 0;
        }
    }

    public String getType(){
        return type;
    }

    public String getShapeDetail(){
        return shapeDetail;
    }

    public Shape.BillingType getBillingType(){
        return billingType;
    }

    public String getBackUpName(){
        return backUpName;
    }

    public static ArchitectureEnum getType(String type){
        ArchitectureEnum[] values = ArchitectureEnum.values();
        for (ArchitectureEnum value : values) {
            if (value.getType().equals(type)){
                return value;
            }
        }
        return ArchitectureEnum.ARM;
    }

    public static ArchitectureEnum getShapeDetail(String shapeDetail){
        ArchitectureEnum[] values = ArchitectureEnum.values();
        for (ArchitectureEnum value : values) {
            if (value.getShapeDetail().equals(shapeDetail)){
                return value;
            }
        }
        return null;
    }
}
