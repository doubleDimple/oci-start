package com.doubledimple.ociserver.config.socket;

import com.doubledimple.ociserver.config.socker.LogWebSocketHandler;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * @version 1.0.0
 * @ClassName LogWebSocketConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-18 09:18
 */
@Configuration
@EnableWebSocket
public class LogWebSocketConfig implements WebSocketConfigurer {

    private final LogWebSocketHandler logWebSocketHandler;

    public LogWebSocketConfig(@Qualifier("logWebSocketHandler") LogWebSocketHandler logWebSocketHandler) {
        this.logWebSocketHandler = logWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(logWebSocketHandler, "/log/ws")
                .setAllowedOrigins("*");
    }
}
