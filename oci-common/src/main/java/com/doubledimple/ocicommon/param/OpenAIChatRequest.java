package com.doubledimple.ocicommon.param;

import lombok.Data;

import java.util.List;
import java.util.Map;


@Data
public class OpenAIChatRequest {
    private String model;
    private List<ChatMessage> messages;
    private Boolean stream;
    private Double temperature;
    private Integer max_tokens;

    private List<Tool> tools;
    private Object tool_choice;

    @Data
    public static class Tool {
        private String type;
        private FunctionDefinition function;
    }

    @Data
    public static class FunctionDefinition {
        private String name;
        private String description;
        private Map<String, Object> parameters;
    }
}
