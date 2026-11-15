package com.doubledimple.ociserver.third.openApi.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName AiChatRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-12 10:10
 */
@Data
public class AiChatRequest {

    private String userId;

    private String message;
}
