package com.doubledimple.ocicommon.param;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2025:09:08日 21:27
 */
@Data
public class AiChatMessage {
    private String role; // "user" 或 "assistant"
    private String content;
    private long timestamp;
    private String modelId; // 记录使用的模型

    public AiChatMessage(String role, String content, String modelId) {
        this.role = role;
        this.content = content;
        this.modelId = modelId;
        this.timestamp = System.currentTimeMillis();
    }
}
