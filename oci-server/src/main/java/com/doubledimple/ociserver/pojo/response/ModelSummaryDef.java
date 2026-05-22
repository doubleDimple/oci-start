package com.doubledimple.ociserver.pojo.response;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.oracle.bmc.generativeai.model.Model;
import com.oracle.bmc.generativeai.model.ModelCapability;
import lombok.Data;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName ModelSummaryDef
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-03 17:23
 */
@Data
public class ModelSummaryDef {

    //租户主键
    private String tenantId;

    //模型id
    private String id;

    //模型名称
    private String displayName;

    //模型版本
    private String version;

    private String name;

    private String description;
    private String provider;
    private String modelName;
    private Boolean enabled;
}
