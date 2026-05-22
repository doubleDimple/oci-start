package com.doubledimple.ociserver.config.socker;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import javax.annotation.PreDestroy;
import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArraySet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * @version 1.0.0
 * @ClassName LogWebSocketHandler
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-18 09:19
 */
@Slf4j
@Component("logWebSocketHandler")  // 指定一个唯一的名称
@Qualifier("logWebSocketHandler")
public class LogWebSocketHandler extends TextWebSocketHandler {

    private static final String LOG_RELATIVE_PATH = "logs/application.log"; // 日志相对路径

    private static final String LOG_FILE = System.getProperty("user.dir") + File.separator + LOG_RELATIVE_PATH;

    private final Set<WebSocketSession> sessions = new CopyOnWriteArraySet<>();
    private final ExecutorService executorService = Executors.newSingleThreadExecutor();
    private volatile boolean running = true;
    private volatile RandomAccessFile currentLogFile;

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        sessions.add(session);
        if (sessions.size() == 1) { // 第一个连接时启动日志监控
            startLogMonitor();
        }
        // 发送最近的日志
        sendRecentLogs(session);
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        sessions.remove(session);
        if (sessions.isEmpty()) { // 没有连接时停止监控
            running = false;
            closeLogFile();
        }
    }

    private void startLogMonitor() {
        running = true;
        executorService.submit(() -> {
            try {
                RandomAccessFile file = new RandomAccessFile(LOG_FILE, "r");
                currentLogFile = file;
                try {
                    long filePointer = file.length();
                    while (running && !Thread.currentThread().isInterrupted()) {
                        try {
                            long length = file.length();
                            if (length < filePointer) {
                                // 日志文件被重置
                                filePointer = 0;
                            } else if (length > filePointer) {
                                // 有新的日志
                                file.seek(filePointer);
                                String line;
                                while ((line = file.readLine()) != null) {
                                    // 转换字符编码
                                    String logLine = new String(line.getBytes("ISO-8859-1"), "UTF-8");
                                    broadcastLog(logLine);
                                }
                                filePointer = file.getFilePointer();
                            }
                            Thread.sleep(1000); // 每秒检查一次
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            break;
                        } catch (IOException e) {
                            if (running) {
                                log.warn("日志读取异常: {}", e.getMessage());
                            }
                            break;
                        }
                    }
                } finally {
                    try {
                        file.close();
                    } catch (IOException ignored) {
                    }
                    currentLogFile = null;
                }
            } catch (IOException e) {
                log.error("无法打开日志文件: {}", LOG_FILE, e);
            }
        });
    }

    private void closeLogFile() {
        RandomAccessFile file = currentLogFile;
        if (file != null) {
            try {
                file.close();
            } catch (IOException ignored) {
            }
        }
    }

    private void broadcastLog(String logMessage) {
        TextMessage message = new TextMessage(logMessage);
        for (WebSocketSession session : sessions) {
            try {
                if (session.isOpen()) {
                    session.sendMessage(message);
                }
            } catch (IOException e) {
                log.debug("广播日志消息失败: {}", e.getMessage());
            }
        }
    }

    private void sendRecentLogs(WebSocketSession session) {
        Process process = null;
        try {
            process = Runtime.getRuntime().exec("tail -n 100 " + LOG_FILE);
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    session.sendMessage(new TextMessage(line));
                }
            }
        } catch (IOException e) {
            log.error("发送最近日志失败", e);
        } finally {
            if (process != null) {
                process.destroyForcibly();
            }
        }
    }

    @PreDestroy
    public void destroy() {
        running = false;
        closeLogFile();
        sessions.forEach(session -> {
            try {
                session.close();
            } catch (IOException e) {
                log.error("Error closing session", e);
            }
        });
        sessions.clear();
        executorService.shutdownNow();
    }
}
