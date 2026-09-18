package com.doubledimple.ociserver.config.socker;

import com.doubledimple.dao.entity.ConsoleConnection;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.ConsoleConnectionRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.config.socket.WebsockifyConfig;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.service.oracle.OciNetBootService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciConsoleUtils;
import com.doubledimple.ociserver.utils.oracle.VncConnectionPlan;
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
import java.net.URLConnection;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.PosixFilePermission;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.StringJoiner;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Pattern;

import static com.doubledimple.ociserver.service.oracle.OciNetBootService.ROOT_PASSWORD;

@Slf4j
@Component("consoleWebSocketHandler")
@Qualifier("consoleWebSocketHandler")
public class ConsoleWebSocketHandler extends TextWebSocketHandler {

    private static final Pattern VNC_PORT_LISTENER_CREATED = Pattern.compile(
            "^debug1: channel [0-9]+: new (?:port-listener )?\\[port listener\\](?: .*)?$");

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
    private final Map<String, ConsolePreparation> consolePreparations = new ConcurrentHashMap<>();
    private final AtomicInteger consoleWorkerSequence = new AtomicInteger();
    private final ThreadPoolExecutor consoleCreationExecutor = new ThreadPoolExecutor(
            2, 4, 60, TimeUnit.SECONDS, new ArrayBlockingQueue<Runnable>(16), task -> {
                Thread thread = new Thread(task, "console-create-" + consoleWorkerSequence.incrementAndGet());
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());

    private static class ConsolePreparation {
        private volatile boolean cancelled;
        private boolean started;
    }

    private ConsolePreparation requireConsoleActive(WebSocketSession session) throws IOException {
        ConsolePreparation preparation = consolePreparations.get(session.getId());
        if (preparation == null || preparation.cancelled || !session.isOpen()) {
            throw new IOException("Console connection cancelled");
        }
        return preparation;
    }

    private void cancelConsolePreparation(String sessionId) {
        ConsolePreparation preparation = consolePreparations.get(sessionId);
        if (preparation != null) {
            synchronized (preparation) { preparation.cancelled = true; }
        }
    }

    private boolean isVncTunnelActive(WebSocketSession session, ConsolePreparation preparation,
                                      SshTunnelProcess tunnel) {
        return !preparation.cancelled && session.isOpen()
                && consolePreparations.get(session.getId()) == preparation
                && sshTunnelProcesses.get(session.getId()) == tunnel
                && !tunnel.destroyed.get() && tunnel.process.isAlive();
    }

    private class SshTunnelProcess {
        final Process process;
        final Thread stdoutReader;
        final Thread stderrReader;
        final WebsockifyConfig.LocalVncPortReservation portReservation;
        final AtomicBoolean listenerReady;
        final AtomicReference<String> lastError;
        final AtomicBoolean destroyed = new AtomicBoolean();
        volatile Thread exitMonitor;

        SshTunnelProcess(Process process, Thread stdoutReader, Thread stderrReader,
                         WebsockifyConfig.LocalVncPortReservation portReservation,
                         AtomicBoolean listenerReady, AtomicReference<String> lastError) {
            this.process = process;
            this.stdoutReader = stdoutReader;
            this.stderrReader = stderrReader;
            this.portReservation = portReservation;
            this.listenerReady = listenerReady;
            this.lastError = lastError;
        }

        void destroy() {
            if (!destroyed.compareAndSet(false, true)) return;
            if (stdoutReader != null) stdoutReader.interrupt();
            if (stderrReader != null) stderrReader.interrupt();
            if (exitMonitor != null && exitMonitor != Thread.currentThread()) exitMonitor.interrupt();
            stopVncProcessAndReleasePort(process, portReservation);
        }

        String failureMessage() {
            String detail = lastError.get();
            String exit = process.isAlive() ? "" : "（退出码 " + process.exitValue() + "）";
            return "VNC SSH 隧道已断开" + exit + (detail == null ? "" : ": " + detail);
        }
    }

    private void stopVncProcessAndReleasePort(Process process, WebsockifyConfig.LocalVncPortReservation reservation) {
        if (process == null) {
            websockifyService.releaseLocalVncPort(reservation);
            return;
        }
        try { process.destroyForcibly(); } catch (RuntimeException e) {
            log.warn("Unable to stop VNC tunnel process immediately", e);
        }
        if (!process.isAlive()) {
            websockifyService.releaseLocalVncPort(reservation);
            return;
        }
        // destroyForcibly is asynchronous. Keep the token until the process has
        // actually exited, without blocking the WebSocket cancellation callback.
        Thread cleanup = new Thread(() -> {
            boolean interrupted = false;
            for (;;) {
                try {
                    process.waitFor();
                    break;
                } catch (InterruptedException e) {
                    interrupted = true;
                }
            }
            websockifyService.releaseLocalVncPort(reservation);
            if (interrupted) Thread.currentThread().interrupt();
        }, "vnc-port-release-" + (reservation == null ? "none" : reservation.getPort()));
        cleanup.setDaemon(true);
        cleanup.start();
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
        consolePreparations.put(session.getId(), new ConsolePreparation());
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        Map<String, Object> request = objectMapper.readValue(message.getPayload(), Map.class);
        String type = (String) request.get("type");

        switch (type) {
            case "create_connection":
                queueCreateAndConnect(session, (Map<String, Object>) request.get("data"));
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
                sendJson(session, heartbeatResponse);
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
                sendJson(session, pongResponse);
                break;
            case "auto_netboot":
                handleAutoNetBoot(session, (Map<String, Object>) request.get("data"));
                break;
            default:
                log.warn("Unknown message type: {}", type);
        }
    }

    /**
     * Keep the WebSocket callback free to receive cancellation and heartbeats.
     */
    private void queueCreateAndConnect(WebSocketSession webSocketSession, Map<String, Object> data) {
        try {
            ConsolePreparation preparation = requireConsoleActive(webSocketSession);
            boolean duplicate;
            synchronized (preparation) {
                requireConsoleActive(webSocketSession);
                duplicate = preparation.started;
                preparation.started = true;
            }
            if (duplicate) {
                sendError(webSocketSession, "当前会话已发起创建，请勿重复提交");
                return;
            }
            Map<String, Object> input = new HashMap<>(data);
            // started is set before enqueueing, including while this task waits.
            consoleCreationExecutor.execute(() -> {
                try {
                    handleCreateAndConnect(webSocketSession, input);
                } finally {
                    // getProvider binds the tenant proxy on this worker. A
                    // reused worker must not keep its proxy or applied-key cache.
                    TenantProxyBinder.clear();
                }
            });
        } catch (RejectedExecutionException e) {
            sendError(webSocketSession, "控制台创建任务繁忙或服务正在关闭，本次未开始创建");
        } catch (Exception e) {
            sendError(webSocketSession, "控制台创建请求无效或会话已关闭");
        }
    }

    /**
     * 处理创建控制台连接请求（仅普通 VNC，保留 Netboot 的既有执行方式）
     */
    private void handleCreateAndConnect(WebSocketSession webSocketSession, Map<String, Object> data) {
        try {
            ConsolePreparation preparation = requireConsoleActive(webSocketSession);
            String instanceDetailsId = (String) data.get("instanceId");
            Long tenantId = Long.valueOf(data.get("tenantId").toString());
            String displayName = (String) data.get("displayName");

            // 1. 获取实例和租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceById(Long.valueOf(instanceDetailsId));
            if (instanceDetails == null || instanceDetails.getCloudType() != 1
                    || instanceDetails.getTenantId() != tenantId.longValue()
                    || instanceDetails.getInstanceId() == null
                    || !instanceDetails.getInstanceId().startsWith("ocid1.instance.")) {
                sendError(webSocketSession, "实例与 OCI 租户信息不匹配");
                return;
            }
            String instanceId = instanceDetails.getInstanceId();
            Optional<Tenant> tenantOpt = tenantRepository.findById(tenantId);

            if (!tenantOpt.isPresent()) {
                sendError(webSocketSession, "未找到租户信息");
                return;
            }

            Tenant tenant = tenantOpt.get();
            if (tenant.getCloudType() != 1) {
                sendError(webSocketSession, "当前租户不是 OCI 账号");
                return;
            }
            requireConsoleActive(webSocketSession);

            // 2. 获取或创建控制台连接
            sendMessage(webSocketSession, "🔍 检查控制台连接...\r\n");
            //ConsoleConnection connection = getOrCreateConsoleConnection(tenant, instanceId, tenantId, displayName);
            ConsoleConnection connection = createNewConsoleConnection(tenant, instanceId, tenantId, displayName, webSocketSession);

            // 3. 保存连接信息到会话
            synchronized (preparation) {
                requireConsoleActive(webSocketSession);
                connectionIds.put(webSocketSession.getId(), connection.getConnectionId());
            }

            sendMessage(webSocketSession, "OCI 控制台资源已激活: " + connection.getConnectionId() + "\r\n");
            sendMessage(webSocketSession, "密钥文件: " + connection.getPrivateKeyPath() + "\r\n");

            // 4. 获取连接字符串并建立VNC连接
            sendMessage(webSocketSession, "获取 VNC 专用连接参数...\r\n");
            String connectionString = OciConsoleUtils.getVncConnectionString(tenant, connection.getConnectionId());
            requireConsoleActive(webSocketSession);

            if (connectionString != null && !connectionString.trim().isEmpty()) {
                establishVncConnectionWithStoredKey(webSocketSession, connectionString, connection.getPrivateKeyPath(), instanceDetails);
            } else {
                sendError(webSocketSession, "OCI 尚未提供可用的 VNC 连接参数，请稍后重试");
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
        // Preserve the existing Netboot call path; VNC supplies its socket below.
        return createNewConsoleConnection(tenant, instanceId, tenantId, displayName, null);
    }

    private ConsoleConnection createNewConsoleConnection(Tenant tenant, String instanceId, Long tenantId,
                                                         String displayName, WebSocketSession webSocketSession) {
        try {
            if (webSocketSession != null) requireConsoleActive(webSocketSession);
            log.info("创建新的控制台连接...");

            // 1. 创建密钥存储目录
            String keyDir = createKeyDirectory(instanceId);
            log.info("密钥存储目录: {}", keyDir);

            // 2. 调用OCI API创建控制台连接（自动生成密钥）
            if (webSocketSession != null) requireConsoleActive(webSocketSession);
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

            // A completed cloud write must retain its key and DB record even
            // if the client closed while OCI was working. Stop before any tunnel.
            if (webSocketSession != null) requireConsoleActive(webSocketSession);
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
            ConsolePreparation preparation = requireConsoleActive(webSocketSession);
            sendMessage(webSocketSession, "正在解析VNC连接字符串...\r\n");

            // 验证密钥文件
            File keyFile = new File(privateKeyPath);
            if (!keyFile.exists() || !keyFile.canRead()) {
                sendError(webSocketSession, "密钥文件不存在或无法读取: " + privateKeyPath);
                return;
            }

            // Preserve OCI's VNC hop/port/forwarding parameters. The serial
            // connection string is reserved for the separate Netboot path.
            VncConnectionPlan plan = VncConnectionPlan.parse(connectionString,
                    instanceDetails.getInstanceId(), connectionIds.get(webSocketSession.getId()));

            // 保存SSH配置到会话
            synchronized (preparation) {
                requireConsoleActive(webSocketSession);
                sessionLocks.put(webSocketSession.getId() + "_target", instanceDetails.getInstanceId());
                sessionLocks.put(webSocketSession.getId() + "_key_file", privateKeyPath);
            }

            // 建立VNC隧道
            sendMessage(webSocketSession, "正在建立VNC隧道连接...\r\n");
            sendMessage(webSocketSession, "使用密钥文件: " + privateKeyPath + "\r\n");

            boolean connected = establishVncTunnel(webSocketSession, plan, privateKeyPath);

            if (!connected) {
                requireConsoleActive(webSocketSession);
                sendMessage(webSocketSession, "自动VNC隧道建立失败，提供手动连接方法\r\n");
                provideVncConnectionInfo(webSocketSession, plan, privateKeyPath);
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
            URLConnection connection = whatismyip.openConnection();
            connection.setConnectTimeout(3000);
            connection.setReadTimeout(3000);
            String ip;
            try (BufferedReader in = new BufferedReader(new InputStreamReader(connection.getInputStream(), StandardCharsets.UTF_8))) {
                String line = in.readLine();
                if (line == null || line.trim().isEmpty()) throw new IOException("Empty public IP response");
                ip = line.trim();
            }

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
                                       VncConnectionPlan plan,
                                       String keyFilePath) {
        Process process = null;
        SshTunnelProcess tunnel = null;
        WebsockifyConfig.LocalVncPortReservation portReservation = null;
        boolean retained = false;
        try {
            ConsolePreparation preparation = requireConsoleActive(webSocketSession);

            String absoluteKeyFilePath = ensureAbsolutePath(keyFilePath);

            // 验证密钥文件
            File keyFile = new File(absoluteKeyFilePath);
            if (!keyFile.exists() || !keyFile.canRead()) {
                sendMessage(webSocketSession, "密钥文件不存在或无法读取: " + absoluteKeyFilePath + "\r\n");
                return false;
            }

            String connectionId = connectionIds.get(webSocketSession.getId());
            String proxyHost = plan.getProxyHost() == null ? plan.getOuterHost() : plan.getProxyHost();

            // 本地 VNC 转发必须绑 127.0.0.1，供 websockify 回环接入。
            // 监听就绪只读取本次 SSH 的确认消息；首次 VNC 连接留给浏览器 RFB。
            String localBind = "127.0.0.1";
            portReservation = websockifyService.reserveLocalVncPort();
            if (portReservation == null) {
                sendMessage(webSocketSession, "无法分配独立的本地 VNC 端口\r\n");
                return false;
            }
            int localVncPort = portReservation.getPort();
            String serverIp = getServerPublicIp();
            requireConsoleActive(webSocketSession);

            sendMessage(webSocketSession, "服务器公网IP: " + serverIp + "\r\n");
            sendMessage(webSocketSession, "代理主机: " + proxyHost + "\r\n");
            sendMessage(webSocketSession, "连接ID: " + connectionId + "\r\n");
            sendMessage(webSocketSession, "VNC SSH 目标: " + plan.getOuterHost() + ":" + plan.getOuterPort() + "\r\n");
            sendMessage(webSocketSession, "密钥文件: " + absoluteKeyFilePath + "\r\n");
            sendMessage(webSocketSession, String.format("本机转发: %s:%d → %s:%d\r\n",
                    localBind, localVncPort, plan.getForwardHost(), plan.getForwardPort()));

            // Both SSH hops share a console-scoped trust store, never the
            // server operator's personal known_hosts. Keep verification on.
            List<String> tunnelArguments = buildVncTunnelArguments(
                    absoluteKeyFilePath, connectionId, plan, localVncPort);
            String vncTunnelCommand = shellCommand(tunnelArguments);

            log.info("生成的VNC隧道命令: {}", vncTunnelCommand);
            sendMessage(webSocketSession, "主机密钥校验: 使用此控制台连接的独立记录，首次登记，后续变更将拒绝连接\r\n");
            sendMessage(webSocketSession, "执行VNC隧道命令...\r\n");

            ProcessBuilder pb = new ProcessBuilder(tunnelArguments);
            pb.directory(new File("/"));

            requireConsoleActive(webSocketSession);
            process = pb.start();
            AtomicReference<String> lastTunnelError = new AtomicReference<>();
            AtomicBoolean listenerReady = new AtomicBoolean();
            Thread[] readers = readProcessOutput(webSocketSession, process, lastTunnelError,
                    localVncPort, listenerReady);
            tunnel = new SshTunnelProcess(process, readers[0], readers[1], portReservation,
                    listenerReady, lastTunnelError);
            synchronized (preparation) {
                requireConsoleActive(webSocketSession);
                // Register before waiting, so close can stop the live process.
                sshTunnelProcesses.put(webSocketSession.getId(), tunnel);
                sessionLocks.put(webSocketSession.getId() + "_vnc_command", vncTunnelCommand);
            }

            sendMessage(webSocketSession, "等待隧道建立...\r\n");
            // Wait for this SSH process's post-listen channel creation message.
            // Never connect to or temporarily bind the forwarded port here.
            boolean portReady = false;
            for (int i = 0; i < 40; i++) {
                requireConsoleActive(webSocketSession);
                Thread.sleep(300);
                requireConsoleActive(webSocketSession);
                if (!isVncTunnelActive(webSocketSession, preparation, tunnel)) {
                    break;
                }
                if (tunnel.listenerReady.get()) {
                    portReady = true;
                    break;
                }
            }

            if (!process.isAlive()) {
                sendMessage(webSocketSession, tunnel.failureMessage() + "\r\n");
                return false;
            }

            if (!portReady) {
                sendMessage(webSocketSession, String.format(
                        "未收到本次 SSH 本地转发的监听就绪消息（%s:%d），不启动 websockify\r\n",
                        localBind, localVncPort));
                return false;
            }
            sendMessage(webSocketSession, String.format("本地转发已监听: %s:%d，尚待浏览器完成 VNC 握手\r\n", localBind, localVncPort));

            if (!sendVncReadyMessage(webSocketSession, localVncPort, vncTunnelCommand, tunnel)) return false;
            requireConsoleActive(webSocketSession);
            monitorTunnelExit(webSocketSession, tunnel);
            retained = true;
            return true;
        } catch (Exception e) {
            log.error("VNC隧道连接失败: {}", e.getMessage(), e);
            sendMessage(webSocketSession, "VNC隧道连接失败: " + e.getMessage() + "\r\n");
            return false;
        } finally {
            if (!retained) {
                websockifyService.stopWebsockifyProxy(webSocketSession.getId());
                if (tunnel != null) {
                    sshTunnelProcesses.remove(webSocketSession.getId(), tunnel);
                    tunnel.destroy();
                } else {
                    stopVncProcessAndReleasePort(process, portReservation);
                }
            }
        }
    }

    /**
     * 读取进程输出和错误流，返回两个 reader 线程的引用以便后续清理
     */
    private Thread[] readProcessOutput(WebSocketSession webSocketSession, Process process,
                                       AtomicReference<String> lastError, int localVncPort,
                                       AtomicBoolean listenerReady) {
        // 读取错误输出
        Thread errorReader = new Thread(() -> {
            try {
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
                boolean awaitingPortListener = false;
                String expectedListener = "debug1: Local forwarding listening on 127.0.0.1 port "
                        + localVncPort + ".";
                String line;
                while ((line = reader.readLine()) != null) {
                    if (listenerReady != null) {
                        // The address announcement can precede bind/listen. It
                        // only identifies our unique -L; channel creation is the
                        // readiness marker. Unknown log formats fail closed.
                        if (line.startsWith("debug1: Local forwarding listening on ")) {
                            awaitingPortListener = expectedListener.equals(line);
                        } else if (awaitingPortListener && VNC_PORT_LISTENER_CREATED.matcher(line).matches()) {
                            listenerReady.set(true);
                            awaitingPortListener = false;
                        }
                        // Keep normal errors and banners while hiding the extra
                        // DEBUG1 output from the console and application log.
                        if (line.startsWith("debug1:") || line.startsWith("debug2:")
                                || line.startsWith("debug3:")) continue;
                        if (line.startsWith("bind [") || line.contains("cannot listen to port")) {
                            awaitingPortListener = false;
                        }
                    }
                    String lower = line.toLowerCase(java.util.Locale.ROOT);
                    if (lower.contains("closed by remote host") || lower.contains("permission denied")
                            || lower.contains("connection refused") || lower.contains("forwarding failed")
                            || lower.contains("could not resolve") || lower.contains("host key verification failed")
                            || lower.contains("remote host identification has changed") || lower.contains("forwarding disabled")
                            || lower.contains("timed out") || lower.contains("no route to host") || lower.contains("connection reset")) {
                        lastError.set(line.substring(0, Math.min(line.length(), 1000)));
                    }
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

        return new Thread[]{outputReader, errorReader};
    }

    /** Watch the actual SSH process after publishing transport readiness. */
    private void monitorTunnelExit(WebSocketSession session, SshTunnelProcess tunnel) {
        Thread monitor = new Thread(() -> {
            try {
                tunnel.process.waitFor();
                // Process exit can precede the final stderr line being consumed.
                if (tunnel.stderrReader != null) tunnel.stderrReader.join(200);
                ConsolePreparation preparation = consolePreparations.get(session.getId());
                if (preparation == null) return;
                synchronized (preparation) {
                    if (preparation.cancelled || tunnel.destroyed.get()
                            || sshTunnelProcesses.get(session.getId()) != tunnel || !session.isOpen()) return;
                    sendError(session, tunnel.failureMessage());
                    handleDisconnect(session);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }, "vnc-tunnel-exit-" + session.getId());
        monitor.setDaemon(true);
        tunnel.exitMonitor = monitor;
        if (!tunnel.destroyed.get()) monitor.start();
    }

    /**
     * 发送VNC连接就绪消息
     */
    private boolean sendVncReadyMessage(WebSocketSession webSocketSession, int vncPort,
                                        String vncCommand, SshTunnelProcess tunnel) throws IOException {
        String sessionId = webSocketSession.getId();
        try {
            ConsolePreparation preparation = requireConsoleActive(webSocketSession);
            if (tunnel.destroyed.get() || !tunnel.process.isAlive()) throw new IOException(tunnel.failureMessage());
            String connectionId = connectionIds.get(sessionId);
            String serverIp = getServerPublicIp();
            requireConsoleActive(webSocketSession);

            Map<String, Object> response = new HashMap<>();
            response.put("type", "vnc_ready");
            response.put("port", vncPort);
            response.put("host", serverIp); // 使用服务器公网IP
            response.put("connectionId", connectionId);
            response.put("command", vncCommand);

            // 启动 websockify：0.0.0.0:wsPort → 127.0.0.1:vncPort
            int websockifyPort = websockifyService.startWebsockifyProxy(sessionId, tunnel.portReservation,
                    () -> tunnel.listenerReady.get() && isVncTunnelActive(webSocketSession, preparation, tunnel));
            requireConsoleActive(webSocketSession);
            // A listening websockify process is not proof that its SSH target
            // survived proxy startup. Never publish a port for an exited tunnel.
            if (tunnel.destroyed.get() || !tunnel.process.isAlive()) throw new IOException(tunnel.failureMessage());

            if (websockifyPort > 0) {
                response.put("websockifyPort", websockifyPort);
                // 客户端用公网 IP + websockify 端口（HTTP 直连）；HTTPS 走 /websockify/{port}
                response.put("vncUrl", String.format("ws://%s:%d/", serverIp, websockifyPort));
                response.put("message", String.format("转发代理已就绪（端口 %d），等待浏览器完成 VNC 握手", websockifyPort));

                sendMessage(webSocketSession, String.format(
                        "websockify 已监听: %s:%d → 127.0.0.1:%d，尚未确认画面连接\r\n",
                        serverIp, websockifyPort, vncPort));
                sendMessage(webSocketSession, "   HTTP: ws://" + serverIp + ":" + websockifyPort + "/\r\n");
                sendMessage(webSocketSession, "   HTTPS 反代: wss://host/websockify/" + websockifyPort + "\r\n");
            } else {
                // 本地转发仅绑 127.0.0.1，外网 VNC 客户端无法直连；明确告知
                sendMessage(webSocketSession, "⚠️ websockify 启动失败，浏览器/Mac 无法显示画面\r\n");
                sendMessage(webSocketSession, "   请检查: 1) 是否安装 websockify  2) 本机 127.0.0.1:"
                        + vncPort + " 是否已绑定  3) 服务端日志 Websockify 错误\r\n");
                websockifyService.stopWebsockifyProxy(sessionId);
                return false;
            }

            synchronized (preparation) {
                // A disconnect must not be followed by an old readiness frame.
                requireConsoleActive(webSocketSession);
                if (tunnel.destroyed.get() || !tunnel.process.isAlive()) throw new IOException(tunnel.failureMessage());
                sendJson(webSocketSession, response);
            }
            return true;

        } catch (IOException | RuntimeException e) {
            // Startup can complete after a close callback has already cleaned up.
            websockifyService.stopWebsockifyProxy(sessionId);
            throw e;
        }
    }

    /**
     * 提供VNC连接信息
     */
    private void provideVncConnectionInfo(WebSocketSession webSocketSession,
                                          VncConnectionPlan plan,
                                          String keyFilePath) {
        try {
            ConsolePreparation preparation = requireConsoleActive(webSocketSession);
            String serverIp = getServerPublicIp();
            requireConsoleActive(webSocketSession);

            sendMessage(webSocketSession, "⚠️ 自动VNC隧道建立失败，提供VNC连接方法\r\n");
            sendMessage(webSocketSession, "\r\n=== Oracle VNC连接 ===\r\n");

            String connectionId = connectionIds.get(webSocketSession.getId());

            String vncCmd = shellCommand(buildVncTunnelArguments(
                    ensureAbsolutePath(keyFilePath), connectionId, plan, 5900));

            sendMessage(webSocketSession, "私钥文件: " + keyFilePath + "\r\n");
            sendMessage(webSocketSession, "VNC隧道命令已准备就绪（需在服务器本机执行）\r\n");
            sendMessage(webSocketSession, "手动命令将监听 127.0.0.1:5900；当前未建立隧道或启动代理\r\n");

            // No tunnel was established for this instance. Never start a proxy
            // against an unrelated process that happens to listen on port 5900.
            Map<String, Object> response = new HashMap<>();
            response.put("type", "vnc_ready");
            response.put("port", 5900);
            response.put("host", serverIp);
            response.put("connectionId", connectionIds.get(webSocketSession.getId()));
            response.put("command", vncCmd);
            response.put("vncUrl", "");
            response.put("message", "自动 VNC 隧道未建立；仅提供手动连接命令，未启动 websockify 代理");
            synchronized (preparation) {
                requireConsoleActive(webSocketSession);
                sendJson(webSocketSession, response);
            }

        } catch (Exception e) {
            log.error("提供VNC连接信息失败", e);
            sendError(webSocketSession, "提供连接信息失败: " + e.getMessage());
        }
    }

    /** Build both automatic and manual tunnels with identical host verification. */
    private List<String> buildVncTunnelArguments(String keyPath, String connectionId,
                                                VncConnectionPlan plan, int localPort) throws IOException {
        if (connectionId == null || !connectionId.matches("ocid1\\.instanceconsoleconnection\\.[A-Za-z0-9._-]+")
                || plan == null
                || localPort < 1 || localPort > 65535) {
            throw new IOException("控制台 SSH 连接参数无效");
        }
        String scope = consoleTrustScope(connectionId);
        Path keyFile = Paths.get(keyPath).toAbsolutePath().normalize();
        Path knownHosts = keyFile.getParent().resolve("known_hosts-" + scope);
        sshPath(keyFile);
        sshPath(knownHosts);
        try {
            Files.createFile(knownHosts);
        } catch (FileAlreadyExistsException ignored) {
            // A reconnect must retain its trusted keys; never truncate or reset.
        }
        if (!Files.isRegularFile(knownHosts, LinkOption.NOFOLLOW_LINKS)
                || !setSecureFilePermissions(knownHosts.toFile())
                || !Files.isReadable(knownHosts) || !Files.isWritable(knownHosts)) {
            throw new IOException("控制台专用主机密钥记录不可用: " + knownHosts);
        }

        // VNC and serial target services can have different ports and host keys;
        // preserve the proxy record and track the VNC target as its own endpoint.
        String outerAlias = plan.getProxyHost() == null ? "oci-console-proxy-" + scope
                : "oci-console-vnc-target-" + plan.getOuterPort() + "-" + scope;
        List<String> command = consoleSshArguments(keyFile, knownHosts, outerAlias);
        command.addAll(Arrays.asList("-o", "LogLevel=DEBUG1"));
        if (plan.getProxyHost() != null) {
            List<String> proxy = consoleSshArguments(keyFile, knownHosts, "oci-console-proxy-" + scope);
            // The readiness marker must come from the outer forwarding client.
            proxy.addAll(Arrays.asList("-o", "LogLevel=INFO"));
            proxy.addAll(Arrays.asList("-p", String.valueOf(plan.getProxyPort()), "-l", plan.getProxyUser()));
            // Escape literal arguments before OpenSSH expands only %h/%p.
            String proxyCommand = shellCommand(proxy).replace("%", "%%")
                    + " -W %h:%p " + shellQuote(plan.getProxyHost());
            command.addAll(Arrays.asList("-o", "ProxyCommand=" + proxyCommand));
        }
        if (plan.getOuterUser() != null) command.addAll(Arrays.asList("-l", plan.getOuterUser()));
        command.addAll(Arrays.asList("-o", "ExitOnForwardFailure=yes", "-p", String.valueOf(plan.getOuterPort()),
                "-N", "-T", "-L", plan.localForward(localPort), plan.getOuterHost()));
        return command;
    }

    private List<String> consoleSshArguments(Path keyFile, Path knownHosts, String hostAlias) throws IOException {
        String hostsPath = sshPath(knownHosts).replace("\\", "\\\\").replace("\"", "\\\"");
        return new ArrayList<>(Arrays.asList("ssh", "-F", "/dev/null", "-i", sshPath(keyFile),
                "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                "-o", "UpdateHostKeys=no",
                "-o", "UserKnownHostsFile=\"" + hostsPath + "\"", "-o", "HostKeyAlias=" + hostAlias,
                "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa", "-o", "HostKeyAlgorithms=+ssh-rsa"));
    }

    private String sshPath(Path path) throws IOException {
        String value = path.toString();
        // OpenSSH versions differ in when -i paths are checked/expanded.
        // Reject token-like paths explicitly instead of silently changing them.
        if (value.contains("\n") || value.contains("\r") || value.contains("%") || value.contains("${")) {
            throw new IOException("控制台文件目录不能包含换行、百分号或 ${，请使用普通目录");
        }
        return value;
    }

    private String consoleTrustScope(String connectionId) throws IOException {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(connectionId.getBytes(StandardCharsets.UTF_8));
            StringBuilder scope = new StringBuilder(digest.length * 2);
            for (byte value : digest) {
                scope.append(Character.forDigit((value >>> 4) & 15, 16));
                scope.append(Character.forDigit(value & 15, 16));
            }
            return scope.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IOException("无法创建控制台主机密钥记录标识", e);
        }
    }

    private String shellQuote(String value) {
        return "'" + value.replace("'", "'\"'\"'") + "'";
    }

    private String shellCommand(List<String> arguments) {
        StringJoiner command = new StringJoiner(" ");
        for (String argument : arguments) command.add(shellQuote(argument));
        return command.toString();
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
        cancelConsolePreparation(sessionId);

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
        try {
            Map<String, Object> response = new HashMap<>();
            response.put("type", "output");
            response.put("data", message);
            sendJson(session, response);
        } catch (IOException e) {
            if (session.isOpen()) log.error("Error sending message to WebSocket", e);
        }
    }

    /**
     * 发送错误消息到WebSocket客户端
     */
    private void sendError(WebSocketSession session, String error) {
        try {
            Map<String, Object> response = new HashMap<>();
            response.put("type", "error");
            response.put("message", error);
            sendJson(session, response);
        } catch (IOException e) {
            if (session.isOpen()) log.error("Error sending error message to WebSocket", e);
        }
    }

    /** One stable lock for output, errors, readiness and heartbeat responses. */
    private void sendJson(WebSocketSession session, Map<String, Object> response) throws IOException {
        Object lock = sessionLocks.get(session.getId());
        if (lock == null) throw new IOException("Console WebSocket is closed");
        synchronized (lock) {
            if (!session.isOpen() || sessionLocks.get(session.getId()) != lock) {
                throw new IOException("Console WebSocket is closed");
            }
            try {
                session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
            } catch (RuntimeException e) {
                throw new IOException("Console WebSocket send failed", e);
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
        cancelConsolePreparation(sessionId);

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
        consolePreparations.remove(sessionId);

        log.info("Console WebSocket connection closed and cleaned up: {}, closeCode={}", sessionId, status.getCode());
    }

    /**
     * 应用关闭时的资源清理
     */
    @PreDestroy
    public void destroy() {
        // Reject new tasks without interrupting an already submitted OCI write.
        // Queued/running tasks observe cancellation before starting any tunnel.
        consoleCreationExecutor.shutdown();
        consolePreparations.keySet().forEach(this::cancelConsolePreparation);
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
        consolePreparations.clear();

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
            // 用户可选自建 TFTP；空则后端直接 HTTP 公网
            String tftpHost = null;
            if (data.get("tftpHost") != null) {
                tftpHost = data.get("tftpHost").toString().trim();
                if (tftpHost.isEmpty()) {
                    tftpHost = null;
                }
            }
            if (tftpHost != null) {
                sendMessage(webSocketSession, "📡 将优先使用您指定的 TFTP 节点: " + tftpHost + "\r\n");
            } else {
                sendMessage(webSocketSession, "📡 未指定 TFTP，将使用公网 HTTP 下载 netboot.xyz\r\n");
            }

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

            sendMessage(webSocketSession, "🔌 系统重置已就绪！\r\n");
            sendMessage(webSocketSession, "🔄 正在向 OCI 发送硬重启 (RESET) 指令...\r\n");
            sendMessage(webSocketSession, "⏳ 正在执行中,请耐心等待，不要关闭窗口...\r\n");

            final String finalTftpHost = tftpHost;
            Thread netbootThread = new Thread(() -> {
                try {
                    boolean success = ociNetBootService.executeAutoNetBoot(
                            tenant,
                            instanceDetails,
                            sshConfig,
                            connection.getPrivateKeyPath(),
                            instanceDetails.getArchitecture(),
                            finalTftpHost
                    );

                    if (success) {
                        sendMessage(webSocketSession, "\r\n🎉 [成功] 🎯 恭喜你,你的系统已经重置成功！\r\n");
                        sendMessage(webSocketSession, "\r\n请根据如下登录信息登录验证\r\n");
                        sendMessage(webSocketSession, "\r\n账户名: root\r\n");
                        sendMessage(webSocketSession, "\r\n密码: \r\n"+ROOT_PASSWORD);

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
