package com.doubledimple.ociserver.config;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.oracle.bmc.identity.model.Compartment;

import java.io.IOException;

/**
 * @author doubleDimple
 * @date 2024:09:21日 22:23
 */
public class CompartmentLifecycleStateDeserializer extends JsonDeserializer<Compartment.LifecycleState> {
    @Override
    public Compartment.LifecycleState deserialize(JsonParser p, DeserializationContext ctxt) throws IOException, IOException {
        String value = p.getValueAsString();
        if (value == null) {
            return null;
        }
        try {
            return Compartment.LifecycleState.valueOf(value.toUpperCase());
        } catch (IllegalArgumentException e) {
            return Compartment.LifecycleState.UnknownEnumValue;
        }
    }
}
