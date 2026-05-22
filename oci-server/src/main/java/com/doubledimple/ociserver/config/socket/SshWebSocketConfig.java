package com.doubledimple.ociserver.config.socket;

import com.doubledimple.ociserver.config.socker.SshWebSocketHandler;
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
public class SshWebSocketConfig implements WebSocketConfigurer {

    private final SshWebSocketHandler sshWebSocketHandler;

    public SshWebSocketConfig(@Qualifier("sshWebSocketHandler") SshWebSocketHandler sshWebSocketHandler) {
        this.sshWebSocketHandler = sshWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {

        // 添加SSH WebSocket处理器
        registry.addHandler(sshWebSocketHandler, "/ws/ssh")
                .setAllowedOrigins("*");
    }
}
