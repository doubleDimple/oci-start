package com.doubledimple.ociserver.config.socket;

import com.doubledimple.ociserver.config.socker.MonitorWebSocketHandler;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

import javax.annotation.Resource;

/**
 * 监控模块 WebSocket配置
 *
 * @author doubleDimple
 */
@Configuration
@EnableWebSocket
public class MonitorWebSocketConfig implements WebSocketConfigurer {

    @Resource
    private MonitorWebSocketHandler monitorWebSocketHandler;

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(monitorWebSocketHandler, "/ws/monitor")
                .setAllowedOrigins("*");
    }
}
