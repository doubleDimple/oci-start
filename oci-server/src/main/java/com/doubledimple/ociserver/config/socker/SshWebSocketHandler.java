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
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Component("sshWebSocketHandler")
@Qualifier("sshWebSocketHandler")
public class SshWebSocketHandler extends TextWebSocketHandler {

    private final Map<String, SshConnection> connections = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper = new ObjectMapper();

    /** Registered before a connect request so a closing WebSocket can cancel it. */
    private static final class SshConnection {
        private final WebSocketSession webSocket;
        private final Object inputLock = new Object();
        private Session ssh;
        private ChannelShell channel;
        private InputStream input;
        private OutputStream output;
        private boolean connecting;
        private volatile boolean ready;
        private volatile boolean closed;

        private SshConnection(WebSocketSession webSocket) {
            this.webSocket = webSocket;
        }
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        connections.put(session.getId(), new SshConnection(session));
        log.debug("WebSocket 建立: {}", session.getId());
    }

    @Override
    @SuppressWarnings("unchecked")
    protected void handleTextMessage(WebSocketSession ws, TextMessage message) {
        SshConnection connection = connections.get(ws.getId());
        if (connection == null || !isActive(connection)) return;
        try {
            Map<String, Object> request = objectMapper.readValue(message.getPayload(), Map.class);
            Object type = request.get("type");
            if ("connect".equals(type)) {
                handleConnect(connection, (Map<String, Object>) request.get("data"));
            } else if ("input".equals(type)) {
                handleInput(connection, (String) request.get("data"));
            } else if ("resize".equals(type)) {
                handleResize(connection, (Map<String, Object>) request.get("data"));
            } else {
                throw new IllegalArgumentException("Invalid SSH message");
            }
        } catch (Exception ignored) {
            // Never echo the input frame: it may contain a password or command.
            sendConnectionError(connection, "Invalid SSH message");
            closeConnection(connection, CloseStatus.BAD_DATA, true);
        }
    }

    private boolean isActive(SshConnection connection) {
        return !connection.closed && connection.webSocket.isOpen()
                && connections.get(connection.webSocket.getId()) == connection;
    }

    private void requireActive(SshConnection connection) throws IOException {
        if (!isActive(connection)) throw new IOException("SSH connection cancelled");
    }

    private void handleConnect(SshConnection connection, Map<String, Object> data) {
        Session ssh = null;
        ChannelShell channel = null;
        InputStream input = null;
        OutputStream output = null;
        String password = null;
        boolean readerStarted = false;
        try {
            synchronized (connection) {
                requireActive(connection);
                if (connection.connecting || connection.ready) {
                    throw new IllegalStateException("SSH connection already started");
                }
                connection.connecting = true;
            }
            String host = (String) data.get("host");
            int port = integer(data.get("port"), 1, 65535);
            String username = (String) data.get("username");
            password = (String) data.get("password");
            if (host == null || host.trim().isEmpty() || username == null || username.trim().isEmpty()
                    || password == null) throw new IllegalArgumentException("Invalid SSH configuration");

            ssh = new JSch().getSession(username, host, port);
            ssh.setPassword(password);
            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no");
            config.put("TCPKeepAlive", "true");
            config.put("ServerAliveInterval", "30");
            config.put("ServerAliveCountMax", "5");
            ssh.setConfig(config);
            synchronized (connection) {
                requireActive(connection);
                connection.ssh = ssh;
            }
            ssh.connect(15000);
            // A client can close during connect(). Recheck after every stage;
            // finally also releases local references if JSch completes late.
            requireActive(connection);
            channel = (ChannelShell) ssh.openChannel("shell");
            channel.setPtyType("xterm-256color");
            synchronized (connection) {
                requireActive(connection);
                connection.channel = channel;
            }
            input = channel.getInputStream();
            output = channel.getOutputStream();
            synchronized (connection) {
                requireActive(connection);
                connection.input = input;
                connection.output = output;
            }
            channel.connect(3000);
            synchronized (connection) {
                requireActive(connection);
                connection.ready = true;
                connection.connecting = false;
            }
            // IO is initialized before the unchanged raw ACK. Start the reader
            // afterwards so shell output can never overtake the success frame.
            sendRaw(connection, "\r\n✅ SSH conn success\r\n");
            requireActive(connection);
            startOutputReader(connection, input);
            readerStarted = true;
        } catch (Exception e) {
            String detail = e.getMessage() == null ? "SSH connection failed" : e.getMessage();
            if (password != null && !password.isEmpty()) detail = detail.replace(password, "[redacted]");
            sendConnectionError(connection, detail);
            closeConnection(connection, CloseStatus.SERVER_ERROR, true);
        } finally {
            if (!readerStarted || !isActive(connection)) {
                // A prior close may have disconnected a still-connecting Session.
                // Repeat cleanup after it returns; no late SSH connection survives.
                disconnect(channel, ssh, input, output);
            }
        }
    }

    private void startOutputReader(SshConnection connection, InputStream input) {
        Thread readerThread = new Thread(() -> {
            try (Reader reader = new InputStreamReader(input, StandardCharsets.UTF_8)) {
                char[] buffer = new char[4096];
                int carry = 0;
                while (isActive(connection)) {
                    int length = reader.read(buffer, carry, buffer.length - carry);
                    if (length == -1) {
                        if (carry != 0) sendRaw(connection, "\uFFFD");
                        closeConnection(connection, CloseStatus.NORMAL, true);
                        return;
                    }
                    int count = carry + length;
                    if (count == 0) continue;
                    // Decode UTF-8 across reads and keep a UTF-16 surrogate pair
                    // in one WebSocket frame for supplementary characters.
                    char last = buffer[count - 1];
                    carry = Character.isHighSurrogate(last) ? 1 : 0;
                    if (count > carry) sendRaw(connection, new String(buffer, 0, count - carry));
                    if (carry != 0) buffer[0] = last;
                }
            } catch (Exception ignored) {
                closeConnection(connection, CloseStatus.SERVER_ERROR, true);
            } finally {
                closeConnection(connection, CloseStatus.NORMAL, true);
            }
        }, "ssh-output-" + connection.webSocket.getId());
        readerThread.setDaemon(true);
        readerThread.start();
    }

    private void handleInput(SshConnection connection, String input) throws IOException {
        if (!connection.ready || input == null) throw new IOException("SSH is not connected");
        synchronized (connection.inputLock) {
            OutputStream output;
            synchronized (connection) {
                requireActive(connection);
                output = connection.output;
            }
            if (output == null) throw new IOException("SSH input is closed");
            output.write(input.getBytes(StandardCharsets.UTF_8));
            output.flush();
        }
    }

    private void handleResize(SshConnection connection, Map<String, Object> data) throws IOException {
        int cols = integer(data.get("cols"), 1, 10000);
        int rows = integer(data.get("rows"), 1, 10000);
        ChannelShell channel;
        synchronized (connection) {
            requireActive(connection);
            channel = connection.channel;
        }
        if (!connection.ready || channel == null) throw new IOException("SSH is not connected");
        channel.setPtySize(cols, rows, 0, 0);
    }

    private int integer(Object value, int min, int max) {
        if (!(value instanceof Number)) throw new IllegalArgumentException("Invalid SSH size or port");
        double number = ((Number) value).doubleValue();
        int integer = ((Number) value).intValue();
        if (number != integer || integer < min || integer > max) {
            throw new IllegalArgumentException("Invalid SSH size or port");
        }
        return integer;
    }

    private void sendRaw(SshConnection connection, String text) throws IOException {
        // Standard Spring WebSocket sessions do not support concurrent sends.
        synchronized (connection.webSocket) {
            requireActive(connection);
            connection.webSocket.sendMessage(new TextMessage(text));
        }
    }

    private void sendConnectionError(SshConnection connection, String detail) {
        try {
            sendRaw(connection, "\r\n❌ SSH conn error: " + detail + "\r\n");
        } catch (Exception ignored) {
            // Caller closes the socket and resources even if reporting fails.
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        SshConnection connection = connections.get(session.getId());
        if (connection != null) closeConnection(connection, status, false);
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        SshConnection connection = connections.get(session.getId());
        if (connection != null) closeConnection(connection, CloseStatus.SERVER_ERROR, true);
    }

    @PreDestroy
    public void destroy() {
        for (SshConnection connection : connections.values()) {
            closeConnection(connection, CloseStatus.GOING_AWAY, true);
        }
    }

    private void closeConnection(SshConnection connection, CloseStatus status, boolean closeWebSocket) {
        Session ssh;
        ChannelShell channel;
        InputStream input;
        OutputStream output;
        synchronized (connection) {
            if (connection.closed) return;
            connection.closed = true;
            connection.ready = false;
            connection.connecting = false;
            ssh = connection.ssh;
            channel = connection.channel;
            input = connection.input;
            output = connection.output;
            connection.ssh = null;
            connection.channel = null;
            connection.input = null;
            connection.output = null;
        }
        connections.remove(connection.webSocket.getId(), connection);
        // Never hold connection/input locks while closing blocking JSch IO.
        disconnect(channel, ssh, input, output);
        if (closeWebSocket) {
            try {
                synchronized (connection.webSocket) {
                    if (connection.webSocket.isOpen()) connection.webSocket.close(status);
                }
            } catch (Exception ignored) { }
        }
        log.debug("SSH 连接已关闭: {}", connection.webSocket.getId());
    }

    private void disconnect(ChannelShell channel, Session ssh, InputStream input, OutputStream output) {
        try { if (channel != null) channel.disconnect(); } catch (Exception ignored) { }
        try { if (ssh != null) ssh.disconnect(); } catch (Exception ignored) { }
        try { if (input != null) input.close(); } catch (Exception ignored) { }
        try { if (output != null) output.close(); } catch (Exception ignored) { }
    }
}
