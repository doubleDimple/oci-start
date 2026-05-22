package com.doubledimple.ociserver.pojo.enums;

import com.oracle.bmc.core.model.Shape;

import static com.oracle.bmc.core.model.Shape.BillingType.AlwaysFree;
import static com.oracle.bmc.core.model.Shape.BillingType.LimitedFree;
import static com.oracle.bmc.core.model.Shape.BillingType.Paid;

public enum AccountTypeEnum {


    TRIAL_PAID_ACCOUNT("TRIAL_PAID_ACCOUNT","试用期账号",LimitedFree),

    UPGRADE_ACCOUNT("UPGRADE_ACCOUNT","升级号",Paid),

    FREE_ACCOUNT("FREE_ACCOUNT","免费账号",AlwaysFree),
    UN_KNOW_ACCOUNT("UN_KNOW_ACCOUNT","未知账号/权限不足",AlwaysFree),
    MANY_REGION_ACCOUNT("MANY_REGION_ACCOUNT","多区号",AlwaysFree),

    ;

    AccountTypeEnum(String type, String shapeDetail, Shape.BillingType billingType){
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

    public static AccountTypeEnum getType(String type){
        AccountTypeEnum[] values = AccountTypeEnum.values();
        for (AccountTypeEnum value : values) {
            if (value.getType().equals(type)){
                return value;
            }
        }
        return null;
    }

    public static AccountTypeEnum getShapeDetail(String shapeDetail){
        AccountTypeEnum[] values = AccountTypeEnum.values();
        for (AccountTypeEnum value : values) {
            if (value.getShapeDetail().equals(shapeDetail)){
                return value;
            }
        }
        return null;
    }
}
