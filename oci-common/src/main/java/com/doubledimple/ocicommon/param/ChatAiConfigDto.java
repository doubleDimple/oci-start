package com.doubledimple.ocicommon.param;

import lombok.Data;

import java.math.BigDecimal;

@Data
public class ChatAiConfigDto {
    private Long id;
    private String tenantId;
    private String modelId;
    private String showModelId;
    private Integer cloudType;
    private String modelName;
    private String provider;
    private String apiKey;
    private String baseUrl;
    private Boolean enabled;
    private String systemPrompt;
    private Integer maxTokens;
    private BigDecimal temperature;
    private Integer maxHistoryMessages;

    private String region;
    private String userName;
}
