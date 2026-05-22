package com.doubledimple.ociserver.config.socket;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * @version 1.0.0
 * @ClassName WebsockifyConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-01 08:57
 */
@Slf4j
@Service
public class WebsockifyConfig {
    //如果是配置了反代,需要配置如下配置
    /*
    location ~ ^/websockify/(\d+)$ {
        proxy_pass http://yourIp:$1;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
    */

    private final ConcurrentHashMap<String, Process> websockifyProcesses = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, Integer> sessionPorts = new ConcurrentHashMap<>();

    /**
     * 启动websockify代理
     * @param sessionId 会话ID
     * @param vncPort VNC端口（通常是5900）
     * @return websockify监听端口，失败返回-1
     */
    /**
     * 启动 Websockify 代理（终极稳定版）
     */
    public int startWebsockifyProxy(String sessionId, int vncPort) {
        try {
            log.info("开始检测 VNC 端口 {} 是否可用", vncPort);

            // =============== ① 等待 VNC 真正可连接 ===============
            if (!waitPortConnectable("localhost", vncPort, 12000)) {  // 最长等 12 秒
                log.error("❌ 等待 12 秒后 VNC 端口 {} 仍不可连接，放弃启动 Websockify", vncPort);
                return -1;
            }

            log.info("✅ VNC 端口 {} 已确认可连接，准备启动 Websockify", vncPort);

            // =============== ② 查找可用的 Websockify 端口 ===============
            int websockifyPort = findAvailableHighPort();
            if (websockifyPort == -1) {
                log.error("❌ 无可用 Websockify 端口，启动失败");
                return -1;
            }

            log.info("会话 {}: 准备启动 Websockify {} → {}", sessionId, websockifyPort, vncPort);

            String command = String.format(
                    "websockify --web=/tmp --cert=NONE 0.0.0.0:%d localhost:%d",
                    websockifyPort, vncPort
            );

            ProcessBuilder pb = new ProcessBuilder("bash", "-c", command);
            pb.redirectErrorStream(true);

            Process process = pb.start();
            websockifyProcesses.put(sessionId, process);

            // =============== ③ 异步读取输出，捕获成功/错误 ===============
            final boolean[] started = {false};
            Thread reader = new Thread(() -> {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        log.info("Websockify[{}]: {}", sessionId, line);

                        if (line.contains("WebSocket server settings")
                                || line.contains("listening on")
                                || line.contains("Accepting connections")) {
                            started[0] = true;
                        }

                        if (line.contains("Error") || line.contains("failed") || line.contains("Address already in use")) {
                            log.error("❌ Websockify错误: {}", line);
                        }
                    }
                } catch (Exception e) {
                    log.error("读取 Websockify 输出失败: {}", e.getMessage());
                }
            });
            reader.setDaemon(true);
            reader.start();

            // ===============  等待 Websockify 成功启动 ===============
            for (int i = 0; i < 20; i++) { // 最长 10 秒
                Thread.sleep(500);

                if (started[0]) break;
                if (isPortConnectable("localhost", websockifyPort)) break;
            }

            // ===============  最终判定是否成功 ===============
            if (process.isAlive() && isPortConnectable("localhost", websockifyPort)) {
                sessionPorts.put(sessionId, websockifyPort);
                log.info("Websockify 启动成功: session={}, port={}", sessionId, websockifyPort);
                return websockifyPort;
            } else {
                log.error("❌ Websockify 启动失败");
                process.destroyForcibly();
                return -1;
            }

        } catch (Exception e) {
            log.error("启动 Websockify 失败: {}", e.getMessage(), e);
            return -1;
        }
    }

    public boolean waitPortConnectable(String host, int port, int timeoutMs) {
        int elapsed = 0;
        while (elapsed < timeoutMs) {
            if (isPortConnectable(host, port)) {
                return true;
            }
            try {
                Thread.sleep(300);
            } catch (InterruptedException ignored) {}
            elapsed += 300;
        }
        return false;
    }


    public boolean isPortConnectable(String host, int port) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), 500);
            return true;
        } catch (Exception e) {
            return false;
        }
    }



    private int findAvailableHighPort() {
        // 使用随机高端口避免冲突
        int basePort = 10000 + (int)(Math.random() * 50000);

        for (int i = 0; i < 100; i++) {
            int port = basePort + i;
            if (isPortAvailable(port)) {
                return port;
            }
        }

        return -1;
    }

    private boolean isPortInUse(String host, int port) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), 1000);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 停止websockify代理
     * @param sessionId 会话ID
     */
    public void stopWebsockifyProxy(String sessionId) {
        try {
            Process process = websockifyProcesses.remove(sessionId);
            Integer port = sessionPorts.remove(sessionId);

            if (process != null) {
                log.info("停止websockify代理: 会话={}, 端口={}", sessionId, port);
                process.destroyForcibly();

                // 等待进程结束
                if (process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) {
                    log.info("Websockify代理已停止: {}", sessionId);
                } else {
                    log.warn("Websockify代理停止超时: {}", sessionId);
                }
            }
        } catch (Exception e) {
            log.error("停止websockify失败: sessionId={}, error={}", sessionId, e.getMessage());
        }
    }

    /**
     * 获取会话的websockify端口
     * @param sessionId 会话ID
     * @return 端口号，不存在返回-1
     */
    public int getWebsockifyPort(String sessionId) {
        return sessionPorts.getOrDefault(sessionId, -1);
    }

    /**
     * 查找可用端口
     * @param startPort 起始端口
     * @return 可用端口
     */
    private int findAvailablePort(int startPort) {
        for (int port = startPort; port < startPort + 1000; port++) {
            if (isPortAvailable(port)) {
                return port;
            }
        }
        // 如果都被占用，返回一个随机端口
        return startPort + (int)(Math.random() * 1000);
    }

    /**
     * 检查端口是否可用
     * @param port 端口号
     * @return 是否可用
     */
    private boolean isPortAvailable(int port) {
        try (ServerSocket socket = new ServerSocket(port)) {
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 应用关闭时清理所有websockify进程
     */
    @PreDestroy
    public void cleanup() {
        log.debug("清理所有websockify进程...");

        websockifyProcesses.forEach((sessionId, process) -> {
            try {
                log.debug("停止websockify进程: {}", sessionId);
                process.destroyForcibly();
                process.waitFor(3, java.util.concurrent.TimeUnit.SECONDS);
            } catch (Exception e) {
                log.error("清理websockify进程失败: sessionId={}, error={}", sessionId, e.getMessage());
            }
        });

        websockifyProcesses.clear();
        sessionPorts.clear();

        log.debug("所有websockify进程已清理完成");
    }

    /**
     * 获取所有活跃的websockify会话
     * @return 活跃会话数量
     */
    public int getActiveSessionCount() {
        return websockifyProcesses.size();
    }

    /**
     * 检查指定会话的websockify是否还在运行
     * @param sessionId 会话ID
     * @return 是否在运行
     */
    public boolean isWebsockifyRunning(String sessionId) {
        Process process = websockifyProcesses.get(sessionId);
        return process != null && process.isAlive();
    }
}
