package com.doubledimple.ociserver.config.socket;

import com.doubledimple.ociserver.config.socker.ConsoleWebSocketHandler;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * Oracle Cloud 控制台连接 WebSocket 配置
 *
 * @author doubleDimple
 * @date 2025-05-24
 */
@Configuration
@EnableWebSocket
public class ConsoleWebSocketConfig implements WebSocketConfigurer {

    private final ConsoleWebSocketHandler consoleWebSocketHandler;

    public ConsoleWebSocketConfig(@Qualifier("consoleWebSocketHandler") ConsoleWebSocketHandler consoleWebSocketHandler) {
        this.consoleWebSocketHandler = consoleWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        // 添加控制台 WebSocket处理器
        registry.addHandler(consoleWebSocketHandler, "/ws/console")
                .setAllowedOrigins("*");
    }
}
