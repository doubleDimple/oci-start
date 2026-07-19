package com.doubledimple.ociserver.config.socket;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Websockify 进程管理：把本机 VNC(TCP) 转成 WebSocket，供 noVNC 使用。
 * <p>
 * 注意：探测端口必须用 {@code 127.0.0.1}，不要用 {@code localhost}
 * （部分环境 localhost 解析到 IPv6 ::1，而 SSH -L 只监听 IPv4）。
 * <p>
 * 若配置了反代，需类似：
 * <pre>
 * location ~ ^/websockify/(\d+)$ {
 *     proxy_pass http://127.0.0.1:$1;
 *     proxy_http_version 1.1;
 *     proxy_set_header Upgrade $http_upgrade;
 *     proxy_set_header Connection "upgrade";
 *     proxy_read_timeout 86400;
 * }
 * </pre>
 */
@Slf4j
@Service
public class WebsockifyConfig {

    private static final String LOOPBACK = "127.0.0.1";

    private final ConcurrentHashMap<String, Process> websockifyProcesses = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, Integer> sessionPorts = new ConcurrentHashMap<>();

    /**
     * 启动 websockify：0.0.0.0:wsPort → 127.0.0.1:vncPort
     *
     * @param sessionId 会话 ID
     * @param vncPort   本机 VNC/SSH 隧道端口（通常 5900 或动态端口）
     * @return websockify 监听端口；失败返回 -1
     */
    public int startWebsockifyProxy(String sessionId, int vncPort) {
        try {
            log.info("开始检测本机 VNC 端口 127.0.0.1:{}", vncPort);

            // ① 等待 SSH 隧道 / VNC 在 IPv4 回环上可连（避免 localhost→::1）
            if (!waitPortConnectable(LOOPBACK, vncPort, 15000)) {
                log.error("❌ 等待 15 秒后 127.0.0.1:{} 仍不可连接，放弃启动 Websockify（检查 SSH -L 是否绑到 127.0.0.1）", vncPort);
                return -1;
            }
            log.info("✅ VNC 端口 127.0.0.1:{} 可连接，准备启动 Websockify", vncPort);

            int websockifyPort = findAvailableHighPort();
            if (websockifyPort == -1) {
                log.error("❌ 无可用 Websockify 端口");
                return -1;
            }

            String binary = resolveWebsockifyBinary();
            if (binary == null) {
                log.error("❌ 未找到 websockify 命令（请安装: pip3 install websockify / apt install websockify）");
                return -1;
            }

            // 目标固定 127.0.0.1，与 SSH -L 127.0.0.1:port 对齐；监听 0.0.0.0 供本机/反代接入
            String command = String.format(
                    "%s --web=/tmp 0.0.0.0:%d %s:%d",
                    shellQuote(binary), websockifyPort, LOOPBACK, vncPort
            );
            log.info("会话 {}: 启动 Websockify {} → {}:{}  cmd={}", sessionId, websockifyPort, LOOPBACK, vncPort, command);

            ProcessBuilder pb = new ProcessBuilder("bash", "-c", command);
            pb.redirectErrorStream(true);
            enrichPath(pb);

            Process process = pb.start();
            websockifyProcesses.put(sessionId, process);

            final AtomicBoolean started = new AtomicBoolean(false);
            final StringBuilder bootLog = new StringBuilder();
            Thread reader = new Thread(() -> {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        log.info("Websockify[{}]: {}", sessionId, line);
                        if (bootLog.length() < 2000) {
                            bootLog.append(line).append('\n');
                        }
                        if (line.contains("WebSocket server settings")
                                || line.contains("listening on")
                                || line.contains("Accepting connections")
                                || line.contains("proxying from")) {
                            started.set(true);
                        }
                        if (line.toLowerCase().contains("error")
                                || line.contains("failed")
                                || line.contains("Address already in use")
                                || line.contains("No such file")) {
                            log.error("❌ Websockify 错误: {}", line);
                        }
                    }
                } catch (Exception e) {
                    log.error("读取 Websockify 输出失败: {}", e.getMessage());
                }
            }, "websockify-out-" + sessionId);
            reader.setDaemon(true);
            reader.start();

            // 最长等 10 秒就绪
            for (int i = 0; i < 20; i++) {
                Thread.sleep(500);
                if (!process.isAlive()) {
                    break;
                }
                if (started.get() || isPortConnectable(LOOPBACK, websockifyPort)) {
                    break;
                }
            }

            if (process.isAlive() && isPortConnectable(LOOPBACK, websockifyPort)) {
                sessionPorts.put(sessionId, websockifyPort);
                log.info("Websockify 启动成功: session={}, port={}", sessionId, websockifyPort);
                return websockifyPort;
            }

            log.error("❌ Websockify 启动失败 session={} exitAlive={} portOpen={} log=\n{}",
                    sessionId, process.isAlive(), isPortConnectable(LOOPBACK, websockifyPort), bootLog);
            process.destroyForcibly();
            websockifyProcesses.remove(sessionId);
            return -1;

        } catch (Exception e) {
            log.error("启动 Websockify 失败: {}", e.getMessage(), e);
            return -1;
        }
    }

    /** 本机是否已安装可用的 websockify。 */
    public boolean isWebsockifyAvailable() {
        return resolveWebsockifyBinary() != null;
    }

    /** 当前解析到的启动命令（可能为 {@code python3 -m websockify}）。 */
    public String getResolvedBinary() {
        return resolveWebsockifyBinary();
    }

    /**
     * 在本机自动安装 websockify（供 Mac 本地 / 服务器一键安装）。
     * 优先 pip --user，无需 sudo；失败再尝试 brew（macOS）。
     *
     * @return success / message / installed / binary / log
     */
    public Map<String, Object> installWebsockify() {
        Map<String, Object> result = new LinkedHashMap<>();
        StringBuilder logBuf = new StringBuilder();

        String existing = resolveWebsockifyBinary();
        if (existing != null) {
            result.put("success", true);
            result.put("installed", true);
            result.put("alreadyInstalled", true);
            result.put("binary", existing);
            result.put("message", "websockify 已安装: " + existing);
            result.put("log", "");
            return result;
        }

        List<String[]> attempts = new ArrayList<>();
        // 不依赖 sudo 的安装路径（Mac 本地 + 普通 Linux 用户）
        attempts.add(new String[]{"python3 -m pip install --user websockify", "python3 -m pip install --user websockify"});
        attempts.add(new String[]{"pip3 install --user websockify", "pip3 install --user websockify"});
        attempts.add(new String[]{"python -m pip install --user websockify", "python -m pip install --user websockify"});
        // macOS Homebrew（若已装 brew）
        if (commandExists("brew") || new File("/opt/homebrew/bin/brew").isFile()
                || new File("/usr/local/bin/brew").isFile()) {
            attempts.add(new String[]{"brew install websockify", "brew install websockify"});
        }
        // 有 root 时偶发可用（容器 / 已配 NOPASSWD）；失败可忽略
        if (isRootUser()) {
            attempts.add(new String[]{"apt-get install -y websockify",
                    "command -v apt-get >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y websockify"});
            attempts.add(new String[]{"yum install -y python3-websockify",
                    "command -v yum >/dev/null 2>&1 && yum install -y python3-websockify || yum install -y websockify"});
        }

        String lastError = "未找到可用的安装方式（需要 python3/pip3 或 brew）";
        for (String[] attempt : attempts) {
            String label = attempt[0];
            String cmd = attempt[1];
            log.info("尝试安装 websockify: {}", label);
            logBuf.append("▶ ").append(label).append('\n');
            CmdResult cr = runShell(cmd, 180);
            if (cr.output != null && !cr.output.isEmpty()) {
                logBuf.append(cr.output);
                if (!cr.output.endsWith("\n")) {
                    logBuf.append('\n');
                }
            }
            logBuf.append("  exit=").append(cr.exitCode).append('\n');

            // 安装后重新探测
            String binary = resolveWebsockifyBinary();
            if (binary != null) {
                result.put("success", true);
                result.put("installed", true);
                result.put("alreadyInstalled", false);
                result.put("binary", binary);
                result.put("message", "websockify 安装成功: " + binary);
                result.put("log", trimLog(logBuf.toString()));
                log.info("✅ websockify 安装成功: {}", binary);
                return result;
            }
            if (cr.exitCode != 0) {
                lastError = "「" + label + "」失败 (exit " + cr.exitCode + ")";
            }
        }

        result.put("success", false);
        result.put("installed", false);
        result.put("alreadyInstalled", false);
        result.put("binary", null);
        result.put("message", lastError + "。请手动执行: pip3 install --user websockify");
        result.put("log", trimLog(logBuf.toString()));
        log.error("❌ websockify 自动安装失败: {}", lastError);
        return result;
    }

    /**
     * 解析 websockify 可执行文件；优先 PATH，再常见绝对路径，最后 python -m。
     */
    private String resolveWebsockifyBinary() {
        String[] candidates = {
                "websockify",
                "/opt/homebrew/bin/websockify",
                "/usr/local/bin/websockify",
                "/usr/bin/websockify",
                "/usr/local/bin/websockify.py"
        };
        for (String c : candidates) {
            if ("websockify".equals(c)) {
                if (commandExists("websockify")) {
                    return "websockify";
                }
                continue;
            }
            File f = new File(c);
            if (f.isFile() && f.canExecute()) {
                return c;
            }
        }
        // pip --user 常见脚本路径
        String home = System.getProperty("user.home");
        if (home != null) {
            String[] userBins = {
                    home + "/.local/bin/websockify",
                    home + "/Library/Python/3.12/bin/websockify",
                    home + "/Library/Python/3.11/bin/websockify",
                    home + "/Library/Python/3.10/bin/websockify",
                    home + "/Library/Python/3.9/bin/websockify"
            };
            for (String p : userBins) {
                File f = new File(p);
                if (f.isFile() && f.canExecute()) {
                    return p;
                }
            }
            // 扫描 Library/Python/*/bin/websockify
            File pyRoot = new File(home, "Library/Python");
            if (pyRoot.isDirectory()) {
                File[] vers = pyRoot.listFiles();
                if (vers != null) {
                    for (File ver : vers) {
                        File bin = new File(ver, "bin/websockify");
                        if (bin.isFile() && bin.canExecute()) {
                            return bin.getAbsolutePath();
                        }
                    }
                }
            }
        }
        // python3 -m websockify
        if (commandExists("python3") && moduleExists("python3", "websockify")) {
            return "python3 -m websockify";
        }
        if (commandExists("python") && moduleExists("python", "websockify")) {
            return "python -m websockify";
        }
        return null;
    }

    /** 扩充 PATH，覆盖 GUI/嵌入式 JVM 常见缺失路径（Homebrew、pip --user）。 */
    private void enrichPath(ProcessBuilder pb) {
        String path = pb.environment().get("PATH");
        if (path == null) {
            path = "/usr/bin:/bin";
        }
        String home = System.getProperty("user.home");
        StringBuilder extra = new StringBuilder();
        String[] prefixes = {
                "/opt/homebrew/bin",
                "/usr/local/bin",
                home != null ? home + "/.local/bin" : null,
                home != null ? home + "/Library/Python/3.12/bin" : null,
                home != null ? home + "/Library/Python/3.11/bin" : null,
                home != null ? home + "/Library/Python/3.10/bin" : null,
                home != null ? home + "/Library/Python/3.9/bin" : null
        };
        for (String p : prefixes) {
            if (p != null && !path.contains(p)) {
                extra.append(p).append(':');
            }
        }
        pb.environment().put("PATH", extra + path);
    }

    private boolean isRootUser() {
        try {
            String name = System.getProperty("user.name");
            return "root".equals(name);
        } catch (Exception e) {
            return false;
        }
    }

    private static class CmdResult {
        final int exitCode;
        final String output;

        CmdResult(int exitCode, String output) {
            this.exitCode = exitCode;
            this.output = output;
        }
    }

    private CmdResult runShell(String command, int timeoutSec) {
        try {
            ProcessBuilder pb = new ProcessBuilder("bash", "-c", command);
            pb.redirectErrorStream(true);
            enrichPath(pb);
            // 避免 pip 交互；保证用户级可写
            pb.environment().put("PIP_DISABLE_PIP_VERSION_CHECK", "1");
            pb.environment().put("PYTHONUNBUFFERED", "1");
            Process process = pb.start();
            StringBuilder out = new StringBuilder();
            Thread reader = new Thread(() -> {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        if (out.length() < 4000) {
                            out.append(line).append('\n');
                        }
                        log.info("install-websockify: {}", line);
                    }
                } catch (Exception ignored) {
                    // ignore
                }
            }, "websockify-install");
            reader.setDaemon(true);
            reader.start();
            boolean finished = process.waitFor(timeoutSec, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                return new CmdResult(-1, out + "\n(超时 " + timeoutSec + "s，已终止)\n");
            }
            reader.join(2000);
            return new CmdResult(process.exitValue(), out.toString());
        } catch (Exception e) {
            log.error("执行安装命令失败: {}", e.getMessage());
            return new CmdResult(-1, e.getMessage());
        }
    }

    private static String trimLog(String s) {
        if (s == null) {
            return "";
        }
        if (s.length() <= 3500) {
            return s;
        }
        return s.substring(s.length() - 3500);
    }

    private boolean commandExists(String cmd) {
        try {
            ProcessBuilder pb = new ProcessBuilder("bash", "-c", "command -v " + cmd);
            enrichPath(pb);
            Process p = pb.start();
            if (!p.waitFor(3, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                return false;
            }
            return p.exitValue() == 0;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean moduleExists(String python, String module) {
        try {
            ProcessBuilder pb = new ProcessBuilder("bash", "-c",
                    shellQuote(python) + " -c " + shellQuote("import " + module));
            enrichPath(pb);
            Process p = pb.start();
            if (!p.waitFor(5, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                return false;
            }
            return p.exitValue() == 0;
        } catch (Exception e) {
            return false;
        }
    }

    private static String shellQuote(String s) {
        if (s == null) {
            return "''";
        }
        // 含空格时（如 python3 -m websockify）不要整体 quote
        if (s.contains(" ") && !s.startsWith("/")) {
            return s;
        }
        if (s.matches("^[A-Za-z0-9_./=-]+$")) {
            return s;
        }
        return "'" + s.replace("'", "'\\''") + "'";
    }

    public boolean waitPortConnectable(String host, int port, int timeoutMs) {
        int elapsed = 0;
        while (elapsed < timeoutMs) {
            if (isPortConnectable(host, port)) {
                return true;
            }
            try {
                Thread.sleep(300);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
                return false;
            }
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

    /** 分配本机可用的本地 VNC 转发端口（避免多会话抢 5900）。 */
    public int allocateLocalVncPort() {
        // 优先 5900，再 5901…，再高位随机
        for (int port = 5900; port <= 5920; port++) {
            if (isPortAvailable(port) && !isPortConnectable(LOOPBACK, port)) {
                return port;
            }
        }
        return findAvailableHighPort();
    }

    private int findAvailableHighPort() {
        int basePort = 10000 + (int) (Math.random() * 50000);
        for (int i = 0; i < 200; i++) {
            int port = basePort + i;
            if (port > 65535) {
                port = 10000 + (port % 50000);
            }
            if (isPortAvailable(port)) {
                return port;
            }
        }
        return -1;
    }

    public void stopWebsockifyProxy(String sessionId) {
        try {
            Process process = websockifyProcesses.remove(sessionId);
            Integer port = sessionPorts.remove(sessionId);

            if (process != null) {
                log.info("停止websockify代理: 会话={}, 端口={}", sessionId, port);
                process.destroyForcibly();
                if (process.waitFor(5, TimeUnit.SECONDS)) {
                    log.info("Websockify代理已停止: {}", sessionId);
                } else {
                    log.warn("Websockify代理停止超时: {}", sessionId);
                }
            }
        } catch (Exception e) {
            log.error("停止websockify失败: sessionId={}, error={}", sessionId, e.getMessage());
        }
    }

    public int getWebsockifyPort(String sessionId) {
        return sessionPorts.getOrDefault(sessionId, -1);
    }

    private boolean isPortAvailable(int port) {
        // 绑定所有接口探测占用，避免 0.0.0.0 已被占仍判可用
        try (ServerSocket socket = new ServerSocket()) {
            socket.setReuseAddress(true);
            socket.bind(new InetSocketAddress(port));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    @PreDestroy
    public void cleanup() {
        log.debug("清理所有websockify进程...");
        websockifyProcesses.forEach((sessionId, process) -> {
            try {
                process.destroyForcibly();
                process.waitFor(3, TimeUnit.SECONDS);
            } catch (Exception e) {
                log.error("清理websockify进程失败: sessionId={}, error={}", sessionId, e.getMessage());
            }
        });
        websockifyProcesses.clear();
        sessionPorts.clear();
    }

    public int getActiveSessionCount() {
        return websockifyProcesses.size();
    }

    public boolean isWebsockifyRunning(String sessionId) {
        Process process = websockifyProcesses.get(sessionId);
        return process != null && process.isAlive();
    }
}
