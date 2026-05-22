package com.doubledimple.ociserver.config.socker;

import com.doubledimple.ocicommon.param.monitor.MonitorReportDTO;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * VPS监控 WebSocket处理器
 * 负责接收前端连接，并将 Controller 收到的 VPS 数据广播给所有前端
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Slf4j
@Component
public class MonitorWebSocketHandler extends TextWebSocketHandler {

    private final Map<String, WebSocketSession> sessions = new ConcurrentHashMap<>();

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        String sessionId = session.getId();
        sessions.put(sessionId, session);

        log.debug("监控面板连接建立: sessionId={}, remoteAddress={}",
                sessionId, session.getRemoteAddress());
        sendMessage(session, "system", "连接成功，等待数据上报...");
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        String payload = message.getPayload();
        if ("ping".equalsIgnoreCase(payload) || payload.contains("ping")) {
            sendMessage(session, "pong", "pong");
        }
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
        log.error("WebSocket传输错误: sessionId={}", session.getId(), exception);
        if (session.isOpen()) {
            session.close();
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) throws Exception {
        String sessionId = session.getId();
        sessions.remove(sessionId);
        log.debug("监控面板连接关闭: sessionId={}, closeStatus={}", sessionId, status);
    }

    /**
     * 核心功能：广播监控数据给所有连接的客户端
     * 该方法由 MonitorApiController 调用
     *
     * @param reportDto 监控数据对象
     */
    public void broadcast(MonitorReportDTO reportDto) {
        if (sessions.isEmpty()) {
            return;
        }

        try {
            String jsonMessage = objectMapper.writeValueAsString(reportDto);
            TextMessage message = new TextMessage(jsonMessage);
            sessions.values().forEach(session -> {
                if (session.isOpen()) {
                    try {
                        // synchronized 避免高并发下多线程同时写入同一个session报错
                        synchronized (session) {
                            session.sendMessage(message);
                        }
                    } catch (IOException e) {
                        log.error("推送监控数据失败: sessionId={}", session.getId(), e);
                    }
                }
            });

        } catch (Exception e) {
            log.error("监控数据序列化失败", e);
        }
    }

    /**
     * 辅助方法：发送简单消息
     */
    private void sendMessage(WebSocketSession session, String type, String content) {
        try {
            if (session.isOpen()) {
                String json = String.format("{\"type\":\"%s\", \"message\":\"%s\"}", type, content);
                session.sendMessage(new TextMessage(json));
            }
        } catch (IOException e) {
            log.error("发送消息失败: sessionId={}", session.getId(), e);
        }
    }

    /**
     * 获取当前在线人数 (用于统计)
     */
    public int getOnlineCount() {
        return sessions.size();
    }
}
