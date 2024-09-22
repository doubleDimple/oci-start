package com.doubledimple.ociserver.config;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.oracle.bmc.core.model.Shape;

import java.io.IOException;

import static com.oracle.bmc.core.model.Shape.BillingType.*;

/**
 * @author doubleDimple
 * @date 2024:09:21日 23:37
 */
/*public class CustomShapeBillingTypeDeserializer extends JsonDeserializer<Shape.BillingType> {
    @Override
    public Shape.BillingType deserialize(JsonParser p, DeserializationContext ctxt) throws IOException {
        String value = p.getText();
        switch (value.toUpperCase()) {  // 转为大写以匹配
            case "PAID":
                return Paid;
            case "ALWAYSFREE":
                return AlwaysFree;
            case "LIMITEDFREE":
                return LimitedFree;
            default:
                return UnknownEnumValue; // 默认值
        }
    }
}*/
