package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName TelegramConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 12:59
 */
@Data
public class TelegramConfigRequest {
    private String botToken;
    private String chatId;
    private String chatName;
    private boolean enabled;
}
