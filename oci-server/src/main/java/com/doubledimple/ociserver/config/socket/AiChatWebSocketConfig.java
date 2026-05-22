package com.doubledimple.ociserver.config.socket;

import com.doubledimple.ociserver.config.socker.AiChatWebSocketHandler;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * AI对话WebSocket配置
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Configuration
@EnableWebSocket
public class AiChatWebSocketConfig implements WebSocketConfigurer {

    private final AiChatWebSocketHandler aiChatWebSocketHandler;

    public AiChatWebSocketConfig(@Qualifier("aiChatWebSocketHandler") AiChatWebSocketHandler aiChatWebSocketHandler) {
        this.aiChatWebSocketHandler = aiChatWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(aiChatWebSocketHandler, "/ws/aiChat")
                .setAllowedOrigins("*");
    }
}
