package com.doubledimple.ociserver.third.openApi.request;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.Size;

/**
 * @version 1.0.0
 * @ClassName AiChatRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-12 10:10
 */
@Data
@Schema(description = "ai聊天请求参数")
public class AiChatRequest {

    @Schema(description = "用户唯一标识", example = "user_12345")
    private String userId;

    @Schema(description = "用户输入的消息", example = "你好，欢饮您")
    private String message;
}
