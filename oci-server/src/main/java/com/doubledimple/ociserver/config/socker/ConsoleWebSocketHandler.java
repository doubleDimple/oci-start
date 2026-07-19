package com.doubledimple.ociserver.config.socker;

import com.doubledimple.dao.entity.ConsoleConnection;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.ConsoleConnectionRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.config.socket.WebsockifyConfig;
import com.doubledimple.ociserver.service.oracle.OciNetBootService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciConsoleUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.jcraft.jsch.Session;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.PosixFilePermission;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Component("consoleWebSocketHandler")
@Qualifier("consoleWebSocketHandler")
public class ConsoleWebSocketHandler extends TextWebSocketHandler {

    @Value("${baseFile.filePath}")
    private String baseFilePath;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OracleInstanceService oracleInstanceService;

    @Resource
    private WebsockifyConfig websockifyService;

    @Resource
    private ConsoleConnectionRepository consoleConnectionRepository;

    @Resource
    private OciNetBootService ociNetBootService;

    private final Map<String, Session> sshSessions = new ConcurrentHashMap<>();
    private final Map<String, OutputStream> outputStreams = new ConcurrentHashMap<>();
    private final Map<String, String> connectionIds = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Map<String, Object> sessionLocks = new ConcurrentHashMap<>();
    private final Map<String, SshTunnelProcess> sshTunnelProcesses = new ConcurrentHashMap<>();
    private final Map<String, Thread> netbootThreads = new ConcurrentHashMap<>();

    private static class SshTunnelProcess {
        final Process process;
        final Thread stdoutReader;
        final Thread stderrReader;

        SshTunnelProcess(Process process, Thread stdoutReader, Thread stderrReader) {
            this.process = process;
            this.stdoutReader = stdoutReader;
            this.stderrReader = stderrReader;
        }

        void destroy() {
            if (stdoutReader != null) stdoutReader.interrupt();
            if (stderrReader != null) stderrReader.interrupt();
            if (process != null) process.destroyForcibly();
        }
    }

    // 添加服务器公网IP缓存
    private String serverPublicIp = null;

    @PostConstruct
    private void initializeBasePath() {
        if (baseFilePath != null) {
            try {
                File baseFile = new File(baseFilePath);
                String canonicalPath = baseFile.getCanonicalPath();
                if (!canonicalPath.endsWith("/")) {
                    canonicalPath += "/";
                }

                log.debug("baseFilePath 格式化: {} -> {}", baseFilePath, canonicalPath);
                this.baseFilePath = canonicalPath;
            } catch (IOException e) {
                log.error("格式化 baseFilePath 失败", e);
            }
        }
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        log.info("New Console WebSocket connection established: {}", session.getId());
        sessionLocks.put(session.getId(), new Object());
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        Map<String, Object> request = objectMapper.readValue(message.getPayload(), Map.class);
        String type = (String) request.get("type");

        switch (type) {
            case "create_connection":
                handleCreateAndConnect(session, (Map<String, Object>) request.get("data"));
                break;
            case "input":
                handleUserInput(session, (String) request.get("data"));
                break;
            case "disconnect":
                handleDisconnect(session);
                break;
            case "heartbeat":
                // 响应心跳
                Map<String, Object> heartbeatResponse = new HashMap<>();
                heartbeatResponse.put("type", "heartbeat_response");
                heartbeatResponse.put("timestamp", System.currentTimeMillis());
                if (session.isOpen()) {
                    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(heartbeatResponse)));
                }
                break;
            case "heartbeat_response":
                // 客户端心跳响应，只记录日志
                log.debug("收到客户端心跳响应");
                break;
            case "ping":
                // 保活ping，发送pong响应
                Map<String, Object> pongResponse = new HashMap<>();
                pongResponse.put("type", "pong");
                pongResponse.put("timestamp", System.currentTimeMillis());
                if (session.isOpen()) {
                    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(pongResponse)));
                }
                break;
            case "auto_netboot":
                handleAutoNetBoot(session, (Map<String, Object>) request.get("data"));
                break;
            default:
                log.warn("Unknown message type: {}", type);
        }
    }

    /**
     * 处理创建控制台连接请求
     */
    private void handleCreateAndConnect(WebSocketSession webSocketSession, Map<String, Object> data) {
        try {
            String instanceDetailsId = (String) data.get("instanceId");
            Long tenantId = Long.valueOf(data.get("tenantId").toString());
            String displayName = (String) data.get("displayName");

            // 1. 获取实例和租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceById(Long.valueOf(instanceDetailsId));
            String instanceId = instanceDetails.getInstanceId();
            Optional<Tenant> tenantOpt = tenantRepository.findById(tenantId);

            if (!tenantOpt.isPresent()) {
                sendError(webSocketSession, "未找到租户信息");
                return;
            }

            Tenant tenant = tenantOpt.get();

            // 2. 获取或创建控制台连接
            sendMessage(webSocketSession, "🔍 检查控制台连接...\r\n");
            //ConsoleConnection connection = getOrCreateConsoleConnection(tenant, instanceId, tenantId, displayName);
            ConsoleConnection connection = createNewConsoleConnection(tenant, instanceId, tenantId, displayName);

            // 3. 保存连接信息到会话
            connectionIds.put(webSocketSession.getId(), connection.getConnectionId());

            sendMessage(webSocketSession, "控制台连接就绪: " + connection.getConnectionId() + "\r\n");
            sendMessage(webSocketSession, "密钥文件: " + connection.getPrivateKeyPath() + "\r\n");

            // 4. 获取连接字符串并建立VNC连接
            sendMessage(webSocketSession, "获取连接字符串...\r\n");
            String connectionString = OciConsoleUtils.getConsoleConnectionString(tenant, connection.getConnectionId());

            if (connectionString != null) {
                establishVncConnectionWithStoredKey(webSocketSession, connectionString, connection.getPrivateKeyPath(), instanceDetails);
            } else {
                sendError(webSocketSession, "控制台连接尚未激活，请稍后重试");
            }

        } catch (Exception e) {
            log.error("Create and connect error", e);
            sendError(webSocketSession, "创建连接失败: " + e.getMessage());
        }
    }

    /**
     * 获取或创建连接信息 - 数据库版本
     */
    private ConsoleConnection getOrCreateConsoleConnection(Tenant tenant, String instanceId, Long tenantId, String displayName) {
        try {
            // 1. 先查询数据库中是否有记录
            Optional<ConsoleConnection> existingOpt = consoleConnectionRepository.findByInstanceIdAndTenantId(instanceId, tenantId);

            if (existingOpt.isPresent()) {
                ConsoleConnection existing = existingOpt.get();

                // 2. 验证Oracle控制台连接是否还存在
                if (OciConsoleUtils.validateConsoleConnection(tenant, existing.getConnectionId())) {
                    log.info("使用现有的控制台连接: {}", existing.getConnectionId());

                    // 验证密钥文件是否还存在
                    File keyFile = new File(existing.getPrivateKeyPath());
                    if (keyFile.exists() && keyFile.canRead()) {
                        return existing;
                    } else {
                        log.warn("密钥文件丢失，重新创建连接");
                        consoleConnectionRepository.delete(existing);
                    }
                } else {
                    log.warn("Oracle控制台连接已失效，重新创建");
                    cleanupOldConnection(existing);
                }
            }

            // 3. 创建新的连接
            return createNewConsoleConnection(tenant, instanceId, tenantId, displayName);

        } catch (Exception e) {
            log.error("获取或创建控制台连接失败", e);
            throw new RuntimeException("获取控制台连接失败: " + e.getMessage(), e);
        }
    }

    /**
     * 创建新的控制台连接 - 数据库版本
     */
    private ConsoleConnection createNewConsoleConnection(Tenant tenant, String instanceId, Long tenantId, String displayName) {
        try {
            log.info("创建新的控制台连接...");

            // 1. 创建密钥存储目录
            String keyDir = createKeyDirectory(instanceId);
            log.info("密钥存储目录: {}", keyDir);

            // 2. 调用OCI API创建控制台连接（自动生成密钥）
            OciConsoleUtils.ConsoleConnectionResult result =
                    OciConsoleUtils.createConsoleConnectionWithAutoKey(tenant, instanceId, displayName);

            if (result == null || result.getKeyPair() == null) {
                throw new RuntimeException("创建控制台连接或生成密钥失败");
            }

            log.info("控制台连接创建成功，ID: {}", result.getConnectionId());

            // 3. 验证密钥内容
            String privateKeyContent = result.getKeyPair().getPrivateKey();
            if (privateKeyContent == null || privateKeyContent.trim().isEmpty()) {
                throw new RuntimeException("私钥内容为空");
            }

            // 4. 保存私钥文件
            String privateKeyPath = savePrivateKey(keyDir, instanceId, privateKeyContent);
            log.info("私钥文件已保存: {}", privateKeyPath);

            // 5. 验证文件保存成功
            File keyFile = new File(privateKeyPath);
            if (!keyFile.exists() || !keyFile.canRead()) {
                throw new RuntimeException("私钥文件保存失败或无法读取: " + privateKeyPath);
            }

            // 6. 保存到数据库
            ConsoleConnection connection = ConsoleConnection.builder()
                    .instanceId(instanceId)
                    .tenantId(tenantId)
                    .connectionId(result.getConnectionId())
                    .privateKeyPath(privateKeyPath)
                    .build();

            ConsoleConnection savedConnection = consoleConnectionRepository.save(connection);
            log.info("控制台连接已保存到数据库，连接ID: {}", savedConnection.getConnectionId());

            return savedConnection;

        } catch (Exception e) {
            log.error("创建控制台连接失败", e);
            throw new RuntimeException("创建控制台连接失败: " + e.getMessage(), e);
        }
    }

    /**
     * 清理旧的连接信息
     */
    private void cleanupOldConnection(ConsoleConnection connection) {
        try {
            // 1. 删除密钥文件
            if (connection.getPrivateKeyPath() != null) {
                File keyFile = new File(connection.getPrivateKeyPath());
                if (keyFile.exists() && keyFile.delete()) {
                    log.info("已删除旧密钥文件: {}", connection.getPrivateKeyPath());
                }
            }

            // 2. 删除数据库记录
            consoleConnectionRepository.delete(connection);
            log.info("已删除数据库记录: {}", connection.getConnectionId());

        } catch (Exception e) {
            log.error("清理旧连接信息失败", e);
        }
    }

    /**
     * 创建密钥存储目录
     */
    private String createKeyDirectory(String instanceId) {
        try {
            Path keyDirPath = Paths.get(baseFilePath, "console-keys", instanceId);

            log.info("创建密钥目录: {}", keyDirPath);

            // 确保目录存在
            if (!Files.exists(keyDirPath)) {
                Files.createDirectories(keyDirPath);
            }

            // 获取规范化的绝对路径
            File keyDirFile = keyDirPath.toFile();
            String absolutePath = keyDirFile.getAbsolutePath();

            // 验证目录
            if (!keyDirFile.exists() || !keyDirFile.isDirectory() || !keyDirFile.canWrite()) {
                throw new RuntimeException("密钥目录创建失败或无写入权限: " + absolutePath);
            }

            log.info("密钥目录创建成功: {}", absolutePath);
            return absolutePath;

        } catch (Exception e) {
            log.error("创建密钥目录失败", e);
            throw new RuntimeException("创建密钥目录失败: " + e.getMessage(), e);
        }
    }

    private String ensureAbsolutePath(String path) {
        if (path == null || path.isEmpty()) {
            return path;
        }

        File file = new File(path);
        String absolutePath = file.getAbsolutePath();

        if (!path.equals(absolutePath)) {
            log.info("路径转换: {} -> {}", path, absolutePath);
        }

        return absolutePath.replace("./","");
    }

    /**
     * 保存私钥文件 - 增强版
     */
    private String savePrivateKey(String keyDir, String instanceId, String privateKey) {
        if (privateKey == null || privateKey.trim().isEmpty()) {
            throw new RuntimeException("私钥内容为空，无法保存");
        }

        try {
            String fileName = String.format("console-key-%s-%d.pem", instanceId, System.currentTimeMillis());

            Path keyFilePath = Paths.get(keyDir, fileName);

            log.info("正在保存私钥到: {}", keyFilePath);

            // 保存文件
            Files.write(keyFilePath, privateKey.getBytes());

            // 获取文件对象并验证
            File keyFile = keyFilePath.toFile();
            if (!keyFile.exists() || keyFile.length() == 0) {
                throw new RuntimeException("文件创建失败或内容为空: " + keyFilePath);
            }

            // 设置权限
            setSecureFilePermissions(keyFile);

            // 返回绝对路径
            String absolutePath = keyFile.getAbsolutePath();
            log.info("私钥文件保存成功: {}, 大小: {} 字节", absolutePath, keyFile.length());

            return absolutePath;

        } catch (IOException e) {
            log.error("保存私钥文件失败", e);
            throw new RuntimeException("保存私钥文件失败: " + e.getMessage(), e);
        }
    }

    /**
     * 使用存储的密钥建立VNC连接
     */
    private void establishVncConnectionWithStoredKey(WebSocketSession webSocketSession,
                                                     String connectionString,
                                                     String privateKeyPath,
                                                     InstanceDetails instanceDetails) {
        try {
            sendMessage(webSocketSession, "正在解析VNC连接字符串...\r\n");

            // 验证密钥文件
            File keyFile = new File(privateKeyPath);
            if (!keyFile.exists() || !keyFile.canRead()) {
                sendError(webSocketSession, "密钥文件不存在或无法读取: " + privateKeyPath);
                return;
            }

            // 解析SSH连接字符串
            Map<String, String> sshConfig = parseConnectionString(connectionString);
            if (sshConfig.isEmpty()) {
                sendError(webSocketSession, "无法解析控制台连接字符串");
                return;
            }

            // 保存SSH配置到会话
            sessionLocks.put(webSocketSession.getId() + "_ssh_config", sshConfig);
            sessionLocks.put(webSocketSession.getId() + "_target", sshConfig.get("target"));
            sessionLocks.put(webSocketSession.getId() + "_key_file", privateKeyPath);

            // 建立VNC隧道
            sendMessage(webSocketSession, "正在建立VNC隧道连接...\r\n");
            sendMessage(webSocketSession, "使用密钥文件: " + privateKeyPath + "\r\n");

            boolean connected = establishVncTunnel(webSocketSession, sshConfig, privateKeyPath);

            if (!connected) {
                sendMessage(webSocketSession, "自动VNC隧道建立失败，提供手动连接方法\r\n");
                provideVncConnectionInfo(webSocketSession, sshConfig, privateKeyPath);
            }

        } catch (Exception e) {
            log.error("Establish VNC connection error", e);
            sendError(webSocketSession, "建立VNC连接失败: " + e.getMessage());
        }
    }

    /**
     * 获取服务器的公网IP地址
     */
    private String getServerPublicIp() {
        // 如果已缓存，直接返回
        if (serverPublicIp != null && !serverPublicIp.isEmpty()) {
            return serverPublicIp;
        }

        // 尝试通过网络API获取公网IP
        try {
            URL whatismyip = new URL("http://checkip.amazonaws.com");
            BufferedReader in = new BufferedReader(new InputStreamReader(whatismyip.openStream()));
            String ip = in.readLine().trim();
            in.close();

            // 缓存IP地址
            serverPublicIp = ip;
            log.info("获取到服务器公网IP: {}", serverPublicIp);
            return ip;
        } catch (Exception e) {
            log.warn("无法获取服务器公网IP，使用localhost作为默认值: {}", e.getMessage());
            return "localhost"; // 如果获取失败，返回localhost作为默认值
        }
    }

    /**
     * 建立VNC隧道
     */
    private boolean establishVncTunnel(WebSocketSession webSocketSession,
                                       Map<String, String> sshConfig,
                                       String keyFilePath) {
        try {
            String target = sshConfig.get("target");
            String proxyCommand = sshConfig.get("proxyCommand");

            String absoluteKeyFilePath = ensureAbsolutePath(keyFilePath);

            // 验证密钥文件
            File keyFile = new File(absoluteKeyFilePath);
            if (!keyFile.exists() || !keyFile.canRead()) {
                sendMessage(webSocketSession, "密钥文件不存在或无法读取: " + absoluteKeyFilePath + "\r\n");
                return false;
            }

            // 提取连接信息
            String connectionId = extractConnectionId(proxyCommand);
            String proxyHost = extractProxyHost(proxyCommand);

            if (connectionId == null || proxyHost == null) {
                sendMessage(webSocketSession, "无法解析连接信息\r\n");
                return false;
            }

            // 本地 VNC 转发必须绑 127.0.0.1，供 websockify 回环接入。
            // 生产环境若绑公网 IP，websockify 探测 127.0.0.1:5900 会失败（Mac/Web 画面都黑）。
            String localBind = "127.0.0.1";
            int localVncPort = websockifyService.allocateLocalVncPort();
            if (localVncPort <= 0) {
                localVncPort = 5900;
            }
            String serverIp = getServerPublicIp();

            sendMessage(webSocketSession, "服务器公网IP: " + serverIp + "\r\n");
            sendMessage(webSocketSession, "代理主机: " + proxyHost + "\r\n");
            sendMessage(webSocketSession, "连接ID: " + connectionId + "\r\n");
            sendMessage(webSocketSession, "目标实例: " + target + "\r\n");
            sendMessage(webSocketSession, "密钥文件: " + absoluteKeyFilePath + "\r\n");
            sendMessage(webSocketSession, String.format("本机转发: %s:%d → 实例:5900\r\n", localBind, localVncPort));

            // SSH -L 127.0.0.1:localPort:localhost:5900（websockify 再暴露给客户端）
            String vncTunnelCommand = String.format(
                    "ssh -i %s -o StrictHostKeyChecking=no " +
                            "-o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa " +
                            "-o ProxyCommand='ssh -i %s -o StrictHostKeyChecking=no " +
                            "-o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa " +
                            "-W %%h:%%p -p 443 %s@%s' " +
                            "-N -L %s:%d:localhost:5900 %s",
                    absoluteKeyFilePath,
                    absoluteKeyFilePath,
                    connectionId,
                    proxyHost,
                    localBind,
                    localVncPort,
                    target
            );

            log.info("生成的VNC隧道命令: {}", vncTunnelCommand);
            sendMessage(webSocketSession, "执行VNC隧道命令...\r\n");

            ProcessBuilder pb = new ProcessBuilder("/bin/bash", "-c", vncTunnelCommand);
            pb.directory(new File("/"));

            Process process = pb.start();
            Thread[] readers = readProcessOutput(webSocketSession, process);

            sendMessage(webSocketSession, "等待隧道建立...\r\n");
            // 等进程存活 + 本地端口可连（最多 ~12s）
            boolean portReady = false;
            for (int i = 0; i < 40; i++) {
                Thread.sleep(300);
                if (!process.isAlive()) {
                    break;
                }
                if (websockifyService.isPortConnectable(localBind, localVncPort)) {
                    portReady = true;
                    break;
                }
            }

            if (!process.isAlive()) {
                int exitCode = process.exitValue();
                sendMessage(webSocketSession, "SSH进程已退出，退出码: " + exitCode + "\r\n");
                return false;
            }

            sshTunnelProcesses.put(webSocketSession.getId(),
                    new SshTunnelProcess(process, readers[0], readers[1]));
            sessionLocks.put(webSocketSession.getId() + "_vnc_command", vncTunnelCommand);

            if (portReady) {
                sendMessage(webSocketSession, String.format("VNC隧道已建立: %s:%d (本机)\r\n", localBind, localVncPort));
            } else {
                sendMessage(webSocketSession, String.format(
                        "⚠️ SSH 进程在跑，但 %s:%d 尚未可连，仍尝试启动 websockify…\r\n",
                        localBind, localVncPort));
            }

            sendVncReadyMessage(webSocketSession, localVncPort, vncTunnelCommand);
            return true;
        } catch (Exception e) {
            log.error("VNC隧道连接失败: {}", e.getMessage(), e);
            sendMessage(webSocketSession, "VNC隧道连接失败: " + e.getMessage() + "\r\n");
            return false;
        }
    }

    /**
     * 读取进程输出和错误流，返回两个 reader 线程的引用以便后续清理
     */
    private Thread[] readProcessOutput(WebSocketSession webSocketSession, Process process) {
        // 读取错误输出
        Thread errorReader = new Thread(() -> {
            try {
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    sendMessage(webSocketSession, "SSH: " + line + "\r\n");
                    log.info("SSH: {}", line);
                }
            } catch (Exception ignored) {
            }
        });
        errorReader.setName("ssh-stderr-" + webSocketSession.getId());
        errorReader.setDaemon(true);
        errorReader.start();

        // 读取标准输出
        Thread outputReader = new Thread(() -> {
            try {
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    sendMessage(webSocketSession, "SSH输出: " + line + "\r\n");
                    log.info("SSH输出: {}", line);
                }
            } catch (Exception ignored) {
            }
        });
        outputReader.setName("ssh-stdout-" + webSocketSession.getId());
        outputReader.setDaemon(true);
        outputReader.start();

        return new Thread[]{errorReader, outputReader};
    }

    /**
     * 发送VNC连接就绪消息
     */
    private void sendVncReadyMessage(WebSocketSession webSocketSession, int vncPort, String vncCommand) {
        try {
            String sessionId = webSocketSession.getId();
            String connectionId = connectionIds.get(sessionId);
            String serverIp = getServerPublicIp();

            Map<String, Object> response = new HashMap<>();
            response.put("type", "vnc_ready");
            response.put("port", vncPort);
            response.put("host", serverIp); // 使用服务器公网IP
            response.put("connectionId", connectionId);
            response.put("command", vncCommand);

            // 启动 websockify：0.0.0.0:wsPort → 127.0.0.1:vncPort
            int websockifyPort = websockifyService.startWebsockifyProxy(sessionId, vncPort);

            if (websockifyPort > 0) {
                response.put("websockifyPort", websockifyPort);
                // 客户端用公网 IP + websockify 端口（HTTP 直连）；HTTPS 走 /websockify/{port}
                response.put("vncUrl", String.format("ws://%s:%d/", serverIp, websockifyPort));
                response.put("message", String.format("SSH隧道已建立，websockify代理端口: %d", websockifyPort));

                sendMessage(webSocketSession, String.format(
                        "✅ websockify 已启动: %s:%d → 127.0.0.1:%d\r\n",
                        serverIp, websockifyPort, vncPort));
                sendMessage(webSocketSession, "   HTTP: ws://" + serverIp + ":" + websockifyPort + "/\r\n");
                sendMessage(webSocketSession, "   HTTPS 反代: wss://host/websockify/" + websockifyPort + "\r\n");
            } else {
                // 本地转发仅绑 127.0.0.1，外网 VNC 客户端无法直连；明确告知
                response.put("vncUrl", "");
                response.put("message", "SSH隧道已建立，websockify启动失败");
                sendMessage(webSocketSession, "⚠️ websockify 启动失败，浏览器/Mac 无法显示画面\r\n");
                sendMessage(webSocketSession, "   请检查: 1) 是否安装 websockify  2) 本机 127.0.0.1:"
                        + vncPort + " 是否可连  3) 服务端日志 Websockify 错误\r\n");
            }

            if (webSocketSession.isOpen()) {
                webSocketSession.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
            }

        } catch (IOException e) {
            log.error("Error sending VNC ready message", e);
        }
    }

    /**
     * 提供VNC连接信息
     */
    private void provideVncConnectionInfo(WebSocketSession webSocketSession,
                                          Map<String, String> sshConfig,
                                          String keyFilePath) {
        try {
            String target = sshConfig.get("target");
            String proxyCommand = sshConfig.get("proxyCommand");
            String bindingIp = getBindingIp();
            String serverIp = getServerPublicIp();

            sendMessage(webSocketSession, "⚠️ 自动VNC隧道建立失败，提供VNC连接方法\r\n");
            sendMessage(webSocketSession, "\r\n=== Oracle VNC连接 ===\r\n");

            String connectionId = extractConnectionId(proxyCommand);
            String proxyHost = extractProxyHost(proxyCommand);

            String vncCmd = String.format(
                    "ssh -i %s -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa " +
                            "-o ProxyCommand='ssh -i %s -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa " +
                            "-W %%h:%%p -p 443 %s@%s' " +
                            "-N -L %s:5900:localhost:5900 %s",
                    keyFilePath,
                    keyFilePath,
                    connectionId,
                    proxyHost,
                    bindingIp, // 使用适合环境的绑定IP
                    target
            );

            sendMessage(webSocketSession, "私钥文件: " + keyFilePath + "\r\n");
            sendMessage(webSocketSession, "VNC隧道命令已准备就绪（需在服务器本机执行）\r\n");
            sendMessage(webSocketSession, "本机监听 127.0.0.1:5900；画面仍依赖 websockify\r\n");

            sendVncReadyMessage(webSocketSession, 5900, vncCmd);

        } catch (Exception e) {
            log.error("提供VNC连接信息失败", e);
            sendError(webSocketSession, "提供连接信息失败: " + e.getMessage());
        }
    }

    /**
     * 解析控制台连接字符串
     */
    private Map<String, String> parseConnectionString(String connectionString) {
        Map<String, String> config = new HashMap<>();
        try {
            log.info("解析连接字符串: {}", connectionString);

            if (connectionString.contains("ProxyCommand")) {
                // 提取完整的代理命令
                int proxyStart = connectionString.indexOf("ProxyCommand=") + 13;
                char quoteChar = connectionString.charAt(proxyStart);
                if (quoteChar == '\'' || quoteChar == '"') {
                    proxyStart++;
                    int proxyEnd = connectionString.indexOf(quoteChar, proxyStart);
                    if (proxyEnd > proxyStart) {
                        String proxyCommand = connectionString.substring(proxyStart, proxyEnd);
                        config.put("proxyCommand", proxyCommand);
                    }
                }

                // 提取目标实例OCID
                String[] cmdParts = connectionString.trim().split("\\s+");
                String target = cmdParts[cmdParts.length - 1];
                config.put("target", target);
                config.put("username", target);
                config.put("port", "22");

                log.info("解析得到配置: {}", config);
            }
        } catch (Exception e) {
            log.error("Error parsing connection string: {}", connectionString, e);
        }
        return config;
    }
    private String extractConnectionId(String proxyCommand) {
        if (proxyCommand == null || proxyCommand.isEmpty()) {
            return null;
        }

        try {
            String[] parts = proxyCommand.split("\\s+");
            for (String part : parts) {
                if (part.startsWith("ocid1.instanceconsoleconnection")) {
                    return part.split("@")[0];
                }
            }
        } catch (Exception e) {
            log.debug("提取连接ID失败: {}", e.getMessage());
        }
        return null;
    }
    /**
     * 从代理命令中提取代理主机
     */
    private String extractProxyHost(String proxyCommand) {
        if (proxyCommand == null || proxyCommand.isEmpty()) {
            return null;
        }

        try {
            String[] parts = proxyCommand.split("\\s+");
            for (String part : parts) {
                if (part.contains("@instance-console") && part.contains(".oci.oraclecloud.com")) {
                    String[] hostParts = part.split("@");
                    if (hostParts.length == 2) {
                        return hostParts[1];
                    }
                }
            }

            for (String part : parts) {
                if (part.contains("ocid1.instanceconsoleconnection")) {
                    String[] ocidParts = part.split("\\.");
                    if (ocidParts.length >= 4) {
                        String region = ocidParts[3];
                        return "instance-console." + region + ".oci.oraclecloud.com";
                    }
                }
            }
        } catch (Exception e) {
            log.debug("提取代理主机失败: {}", e.getMessage());
        }
        return null;
    }

    /**
     * 设置安全的文件权限
     */
    private boolean setSecureFilePermissions(File file) {
        try {
            if (isPosixSupported()) {
                Path path = file.toPath();
                Set<PosixFilePermission> permissions = EnumSet.of(
                        PosixFilePermission.OWNER_READ,
                        PosixFilePermission.OWNER_WRITE
                );
                Files.setPosixFilePermissions(path, permissions);
                return true;
            }

            // 兼容性方法
            boolean success = true;
            success &= file.setReadable(false, false);
            success &= file.setWritable(false, false);
            success &= file.setExecutable(false, false);
            success &= file.setReadable(true, true);
            success &= file.setWritable(true, true);

            return success;
        } catch (Exception e) {
            log.error("设置文件权限失败: {}", file.getAbsolutePath(), e);
            return false;
        }
    }

    private boolean isPosixSupported() {
        try {
            return Files.getFileStore(Paths.get(".")).supportsFileAttributeView("posix");
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 处理用户输入的命令
     */
    private void handleUserInput(WebSocketSession webSocketSession, String input) {
        try {
            OutputStream outputStream = outputStreams.get(webSocketSession.getId());
            if (outputStream != null) {
                outputStream.write(input.getBytes("UTF-8"));
                outputStream.flush();
                log.debug("用户输入发送成功: {}", input.replace("\r", "\\r").replace("\n", "\\n"));
            } else {
                sendError(webSocketSession, "SSH连接未建立，无法发送输入");
            }
        } catch (IOException e) {
            log.error("发送用户输入失败", e);
            sendError(webSocketSession, "发送输入失败: " + e.getMessage());
        }
    }

    /**
     * 处理断开连接请求
     */
    private void handleDisconnect(WebSocketSession webSocketSession) {
        String sessionId = webSocketSession.getId();

        // 停止websockify代理
        websockifyService.stopWebsockifyProxy(sessionId);

        // 停止SSH隧道进程（含 reader 线程）
        cleanupSshTunnelProcess(sessionId);

        // 停止 netboot 线程
        cleanupNetbootThread(sessionId);

        // 清理连接信息（数据库记录保留以便重用）
        String connectionId = connectionIds.remove(sessionId);
        if (connectionId != null) {
            log.info("Console connection {} retained for reuse", connectionId);
        }

        // 清理其他会话资源
        sessionLocks.remove(sessionId + "_ssh_config");
        sessionLocks.remove(sessionId + "_target");
        sessionLocks.remove(sessionId + "_key_file");
        sessionLocks.remove(sessionId + "_vnc_command");

        cleanupSshSession(sessionId);
        sendMessage(webSocketSession, "控制台连接已断开\r\n");
    }

    /**
     * 清理SSH会话资源
     */
    private void cleanupSshSession(String sessionId) {
        Session sshSession = sshSessions.remove(sessionId);
        if (sshSession != null) {
            sshSession.disconnect();
        }

        Session proxySession = sshSessions.remove(sessionId + "_proxy");
        if (proxySession != null) {
            proxySession.disconnect();
        }

        OutputStream outputStream = outputStreams.remove(sessionId);
        if (outputStream != null) {
            try {
                outputStream.close();
            } catch (IOException e) {
                log.error("Error closing output stream", e);
            }
        }
    }

    /**
     * 清理 SSH 隧道进程及其 reader 线程
     */
    private void cleanupSshTunnelProcess(String sessionId) {
        SshTunnelProcess tunnel = sshTunnelProcesses.remove(sessionId);
        if (tunnel != null) {
            tunnel.destroy();
            log.debug("SSH tunnel process and reader threads cleaned up: {}", sessionId);
        }
    }

    /**
     * 清理 netboot 异步线程
     */
    private void cleanupNetbootThread(String sessionId) {
        Thread thread = netbootThreads.remove(sessionId);
        if (thread != null && thread.isAlive()) {
            thread.interrupt();
            log.debug("Netboot thread interrupted: {}", sessionId);
        }
    }

    /**
     * 发送消息到WebSocket客户端
     */
    private void sendMessage(WebSocketSession session, String message) {
        Object lock = sessionLocks.getOrDefault(session.getId(), new Object());
        synchronized (lock) {
            try {
                Map<String, Object> response = new HashMap<>();
                response.put("type", "output");
                response.put("data", message);

                if (session.isOpen()) {
                    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
                }
            } catch (IOException e) {
                log.error("Error sending message to WebSocket", e);
            }
        }
    }

    /**
     * 发送错误消息到WebSocket客户端
     */
    private void sendError(WebSocketSession session, String error) {
        Object lock = sessionLocks.getOrDefault(session.getId(), new Object());
        synchronized (lock) {
            try {
                Map<String, Object> response = new HashMap<>();
                response.put("type", "error");
                response.put("message", error);

                if (session.isOpen()) {
                    session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
                }
            } catch (IOException e) {
                log.error("Error sending error message to WebSocket", e);
            }
        }
    }

    /**
     * SSH -L 本地绑定地址。
     * <p>
     * 固定 127.0.0.1：websockify 只能可靠连回环口；绑公网 IP 会导致
     * 「隧道看似建立、websockify 探测 localhost/127.0.0.1 失败」。
     * 对外暴露由 websockify 监听 0.0.0.0 或 Nginx /websockify/ 反代完成。
     */
    private String getBindingIp() {
        return "127.0.0.1";
    }

    /**
     * WebSocket连接关闭时的清理工作
     */
    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String sessionId = session.getId();

        // 停止websockify代理
        websockifyService.stopWebsockifyProxy(sessionId);

        // 停止SSH隧道进程（含 reader 线程）
        cleanupSshTunnelProcess(sessionId);

        // 停止 netboot 线程
        cleanupNetbootThread(sessionId);

        // 清理会话资源（不删除数据库记录）
        sessionLocks.remove(sessionId);
        sessionLocks.remove(sessionId + "_ssh_config");
        sessionLocks.remove(sessionId + "_target");
        sessionLocks.remove(sessionId + "_key_file");
        sessionLocks.remove(sessionId + "_vnc_command");
        cleanupSshSession(sessionId);
        connectionIds.remove(sessionId);

        log.info("Console WebSocket connection closed and cleaned up: {}", sessionId);
    }

    /**
     * 应用关闭时的资源清理
     */
    @PreDestroy
    public void destroy() {
        // 停止所有 SSH 隧道进程和 reader 线程
        sshTunnelProcesses.values().forEach(SshTunnelProcess::destroy);
        sshTunnelProcesses.clear();

        // 中断所有 netboot 线程
        netbootThreads.values().forEach(thread -> {
            if (thread.isAlive()) thread.interrupt();
        });
        netbootThreads.clear();

        // 关闭所有SSH会话
        sshSessions.values().forEach(Session::disconnect);

        // 关闭所有输出流
        outputStreams.values().forEach(outputStream -> {
            try {
                outputStream.close();
            } catch (IOException e) {
                log.error("Error closing output stream", e);
            }
        });

        // 清理所有集合
        sessionLocks.clear();
        sshSessions.clear();
        outputStreams.clear();
        connectionIds.clear();

        log.debug("Console WebSocket handler destroyed and all resources cleaned up");
    }

    /**
     * 处理自动化 Netboot (网络引导劫持) 请求
     */
    private void handleAutoNetBoot(WebSocketSession webSocketSession, Map<String, Object> data) {
        try {
            sendMessage(webSocketSession, "🛠️ 开始初始化全自动 Netboot 救援流程...\r\n");

            // 1. 提取请求参数 (与 create_connection 逻辑一致)
            String instanceDetailsId = (String) data.get("instanceId");
            Long tenantId = Long.valueOf(data.get("tenantId").toString());
            String displayName = (String) data.get("displayName");

            // 2. 获取实例和租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceById(Long.valueOf(instanceDetailsId));
            String instanceId = instanceDetails.getInstanceId();
            Optional<Tenant> tenantOpt = tenantRepository.findById(tenantId);

            if (!tenantOpt.isPresent()) {
                sendError(webSocketSession, "未找到租户信息");
                return;
            }
            Tenant tenant = tenantOpt.get();

            sendMessage(webSocketSession, "🔍 正在准备底层串口控制台通道...\r\n");

            // 3. 获取或创建控制台连接 (复用你现有的稳健逻辑)
            //ConsoleConnection connection = getOrCreateConsoleConnection(tenant, instanceId, tenantId, displayName);
            ConsoleConnection connection = createNewConsoleConnection(tenant, instanceId, tenantId, displayName);
            connectionIds.put(webSocketSession.getId(), connection.getConnectionId());

            // 4. 获取连接字符串并解析出 SSH 代理配置
            String connectionString = OciConsoleUtils.getConsoleConnectionString(tenant, connection.getConnectionId());
            if (connectionString == null) {
                sendError(webSocketSession, "控制台连接尚未激活，无法发起劫持，请稍后重试");
                return;
            }

            Map<String, String> sshConfig = parseConnectionString(connectionString);
            if (sshConfig.isEmpty()) {
                sendError(webSocketSession, "无法解析控制台连接字符串，终止任务");
                return;
            }

            sendMessage(webSocketSession, "🔌 串口底层控制通道已就绪！\r\n");
            sendMessage(webSocketSession, "🔄 正在向 OCI 发送硬重启 (RESET) 指令...\r\n");
            sendMessage(webSocketSession, "⏳ 开始拦截引导流，这是一个耗时操作 (预计 1-3 分钟)，请耐心等待，不要关闭窗口...\r\n");

            Thread netbootThread = new Thread(() -> {
                try {
                    boolean success = ociNetBootService.executeAutoNetBoot(
                            tenant,
                            instanceDetails,
                            sshConfig,
                            connection.getPrivateKeyPath(),
                            instanceDetails.getArchitecture()
                    );

                    if (success) {
                        sendMessage(webSocketSession, "\r\n🎉 [成功] 🎯 截获引导流成功，Netboot 引导指令已下发！\r\n");
                        sendMessage(webSocketSession, "👉 您的实例正在从网络加载微型救援系统 (如 netboot.xyz 或 Alpine)。\r\n");
                        sendMessage(webSocketSession, "⏳ 请等待 2-3 分钟网络系统启动完毕后，通过普通的 SSH 客户端连接您的服务器 IP 进行 DD 刷机操作。\r\n");
                    } else {
                        sendMessage(webSocketSession, "\r\n❌ [失败] 截获启动流超时或失败。实例可能未成功重启，或错过了进入 iPXE 的时间窗口。\r\n");
                        sendMessage(webSocketSession, "💡 建议：您可以再次点击尝试，或者前往控制台查看详细日志。\r\n");
                    }
                } catch (Exception e) {
                    if (!Thread.currentThread().isInterrupted()) {
                        log.error("Netboot 异步执行异常", e);
                        sendError(webSocketSession, "Netboot 异步任务执行中断: " + e.getMessage());
                    }
                } finally {
                    netbootThreads.remove(webSocketSession.getId());
                }
            });
            netbootThread.setName("netboot-" + webSocketSession.getId());
            netbootThread.setDaemon(true);
            netbootThreads.put(webSocketSession.getId(), netbootThread);
            netbootThread.start();

        } catch (Exception e) {
            log.error("Netboot 初始化任务崩溃", e);
            sendError(webSocketSession, "Netboot 任务初始化失败: " + e.getMessage());
        }
    }
}