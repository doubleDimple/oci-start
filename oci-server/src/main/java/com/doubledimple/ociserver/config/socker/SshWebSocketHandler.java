package com.doubledimple.ociserver.config.socker;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.jcraft.jsch.ChannelShell;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import javax.annotation.PreDestroy;
import java.io.*;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Component("sshWebSocketHandler")
@Qualifier("sshWebSocketHandler")
public class SshWebSocketHandler extends TextWebSocketHandler {

    private final Map<String, Session> sshSessions = new ConcurrentHashMap<>();
    private final Map<String, ChannelShell> sshChannels = new ConcurrentHashMap<>();
    private final Map<String, OutputStream> outputStreams = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        log.debug("WebSocket 建立: {}", session.getId());
    }

    @Override
    protected void handleTextMessage(WebSocketSession webSocketSession, TextMessage message) throws Exception {
        Map<String, Object> request = objectMapper.readValue(message.getPayload(), Map.class);
        String type = (String) request.get("type");

        switch (type) {
            case "connect":
                handleConnect(webSocketSession, (Map<String, Object>) request.get("data"));
                break;
            case "input":
                handleInput(webSocketSession, (String) request.get("data"));
                break;
            case "resize":
                handleResize(webSocketSession, (Map<String, Object>) request.get("data"));
                break;
        }
    }

    private void handleConnect(WebSocketSession ws, Map<String, Object> data) {
        try {
            String host = (String) data.get("host");
            int port = (Integer) data.get("port");
            String username = (String) data.get("username");
            String password = (String) data.get("password");

            JSch jsch = new JSch();
            Session ssh = jsch.getSession(username, host, port);

            ssh.setPassword(password);
            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no");
            config.put("TCPKeepAlive", "true");
            config.put("ServerAliveInterval", "30");
            config.put("ServerAliveCountMax", "5");
            ssh.setConfig(config);
            ssh.connect(15000);

            ChannelShell channel = (ChannelShell) ssh.openChannel("shell");

            // ✅ 正确启用 256 色终端（使 xterm.js 丝滑 & 支持 vim/nano）
            channel.setPtyType("xterm-256color");

            channel.connect(3000);
            sshSessions.put(ws.getId(), ssh);
            sshChannels.put(ws.getId(), channel);

            setupIO(ws, channel);

            sendRaw(ws, "\r\n✅ SSH conn success\r\n");

        } catch (Exception e) {
            sendRaw(ws, "\r\n❌ SSH conn error: " + e.getMessage() + "\r\n");
        }
    }

    private void setupIO(WebSocketSession ws, ChannelShell channel) {
        try {
            OutputStream out = channel.getOutputStream();
            InputStream in = channel.getInputStream();
            outputStreams.put(ws.getId(), out);

            new Thread(() -> {
                byte[] buffer = new byte[4096];
                int length;
                try {
                    while ((length = in.read(buffer)) != -1) {
                        sendRaw(ws, new String(buffer, 0, length));
                    }
                } catch (Exception ignored) {
                }
            }).start();

        } catch (Exception e) {
            sendRaw(ws, "❌ IO 初始化失败: " + e.getMessage());
        }
    }

    private void handleInput(WebSocketSession ws, String input) {
        try {
            OutputStream out = outputStreams.get(ws.getId());
            if (out != null) {
                out.write(input.getBytes());
                out.flush();
            }
        } catch (Exception ignored) {}
    }

    private void handleResize(WebSocketSession ws, Map<String, Object> data) {
        try {
            ChannelShell channel = sshChannels.get(ws.getId());
            if (channel != null) {
                channel.setPtySize(
                        (Integer) data.get("cols"),
                        (Integer) data.get("rows"),
                        0, 0
                );
            }
        } catch (Exception ignored) {}
    }

    private void sendRaw(WebSocketSession session, String text) {
        try {
            if (session.isOpen()) {
                session.sendMessage(new TextMessage(text));
            }
        } catch (Exception ignored) {}
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        closeSession(session.getId());
    }

    @PreDestroy
    public void destroy() {
        sshSessions.keySet().forEach(this::closeSession);
    }

    private void closeSession(String sessionId) {
        try { if (sshChannels.get(sessionId) != null) sshChannels.get(sessionId).disconnect(); } catch (Exception ignored) {}
        try { if (sshSessions.get(sessionId) != null) sshSessions.get(sessionId).disconnect(); } catch (Exception ignored) {}
        try { if (outputStreams.get(sessionId) != null) outputStreams.get(sessionId).close(); } catch (Exception ignored) {}

        sshChannels.remove(sessionId);
        sshSessions.remove(sessionId);
        outputStreams.remove(sessionId);

        log.debug("SSH 连接已关闭: {}", sessionId);
    }
}
