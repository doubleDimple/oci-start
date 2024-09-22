package com.doubledimple.ociserver.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.module.SimpleModule;
import com.oracle.bmc.core.model.Shape;

/**
 * @author doubleDimple
 * @date 2024:09:21日 23:39
 */
/*public class CustomObjectMapperFactory {
    public static ObjectMapper createCustomObjectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        SimpleModule module = new SimpleModule();
        module.addDeserializer(Shape.BillingType.class, new CustomShapeBillingTypeDeserializer());
        mapper.registerModule(module);
        return mapper;
    }
}*/
