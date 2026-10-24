package com.doubledimple.ociserver.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.stereotype.Component;

import javax.annotation.PreDestroy;
import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * 对齐 easy-dev {@code FrontendDevServerLauncher}：
 * IDEA 点 {@code OciServerApplication} 时自动拉起 oci-start-web 的 pnpm run dev。
 * <p>
 * 行为：
 * - 5173 已被占用 → 复用，不重复启动；
 * - 找不到 oci-start-web（生产 jar）→ 跳过；
 * - node_modules 缺失 → 先 pnpm install；
 * - 前端日志以 [web] 前缀打进后端控制台；
 * - 后端停时一并停前端。
 * 开关：{@code oci.web.auto-start=false}
 */
@Slf4j
@Component
public class FrontendDevServerLauncher implements ApplicationListener<ApplicationReadyEvent> {

    @Value("${oci.web.auto-start:true}")
    private boolean autoStart;

    @Value("${oci.web.port:5173}")
    private int webPort;

    private volatile Process webProcess;

    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        if (!autoStart) {
            return;
        }
        if (isPortInUse(webPort)) {
            log.info("[web] 检测到前端 dev server 已在运行，直接访问 http://localhost:{}", webPort);
            return;
        }
        File webDir = locateWebDir();
        if (webDir == null) {
            log.warn("[web] 未找到 oci-start-web 目录，跳过前端自动启动（仅影响页面，接口正常）");
            return;
        }
        Thread starter = new Thread(new Runnable() {
            @Override
            public void run() {
                startWebDevServer(webDir);
            }
        }, "web-dev-launcher");
        starter.setDaemon(true);
        starter.start();
    }

    private void startWebDevServer(File webDir) {
        try {
            if (!new File(webDir, "node_modules").exists()) {
                log.info("[web] 首次启动，正在安装前端依赖（pnpm install，约 1-2 分钟）...");
                Process install = command(webDir, "pnpm", "install", "--frozen-lockfile=false").start();
                pipe(install, "install");
                if (install.waitFor() != 0) {
                    log.error("[web] pnpm install 失败，请进入 oci-start-web 手动执行排查");
                    return;
                }
                log.info("[web] 前端依赖安装完成");
            }
            webProcess = command(webDir, "pnpm", "run", "dev").start();
            log.info("[web] 前端 dev server 启动中，稍候访问 http://localhost:{}（vite 代理接口到后端 9856）", webPort);
            pipe(webProcess, "dev");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            log.error("[web] 前端自动启动失败：{}，可进入 oci-start-web 手动执行 pnpm run dev", e.getMessage());
        }
    }

    /** 探测 oci-start-web：兼容 IDEA 工作目录为项目根或 oci-server 模块 */
    private File locateWebDir() {
        File dir = new File(System.getProperty("user.dir"));
        for (int i = 0; i < 3 && dir != null; i++) {
            File candidate = new File(dir, "oci-start-web");
            if (new File(candidate, "package.json").exists()) {
                return candidate;
            }
            dir = dir.getParentFile();
        }
        return null;
    }

    private ProcessBuilder command(File workDir, String... cmd) {
        List<String> command = new ArrayList<String>();
        if (System.getProperty("os.name").toLowerCase().contains("win")) {
            command.add("cmd");
            command.add("/c");
        }
        command.addAll(Arrays.asList(cmd));
        ProcessBuilder pb = new ProcessBuilder(command)
                .directory(workDir)
                .redirectErrorStream(true);
        enrichPath(pb);
        return pb;
    }

    /** IDEA 从 Dock 启动时 PATH 往往没有 nvm / pnpm，补上本机常见目录 */
    private void enrichPath(ProcessBuilder pb) {
        String home = System.getProperty("user.home");
        String path = pb.environment().get("PATH");
        if (path == null) {
            path = "";
        }
        StringBuilder extra = new StringBuilder();
        appendPath(extra, home + "/.npm-global/bin");
        appendPath(extra, "/usr/local/bin");
        appendPath(extra, "/opt/homebrew/bin");
        File nvm = new File(home, ".nvm/versions/node");
        File[] versions = nvm.listFiles();
        if (versions != null && versions.length > 0) {
            Arrays.sort(versions);
            for (int i = versions.length - 1; i >= 0; i--) {
                File bin = new File(versions[i], "bin");
                if (bin.isDirectory()) {
                    extra.append(bin.getAbsolutePath()).append(File.pathSeparator);
                    break;
                }
            }
        }
        pb.environment().put("PATH", extra.toString() + path);
    }

    private static void appendPath(StringBuilder extra, String dir) {
        if (new File(dir).isDirectory()) {
            extra.append(dir).append(File.pathSeparator);
        }
    }

    private void pipe(Process process, String tag) {
        Thread reader = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BufferedReader br = new BufferedReader(
                            new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8));
                    try {
                        String line;
                        while ((line = br.readLine()) != null) {
                            if (!line.trim().isEmpty()) {
                                log.info("[web:{}] {}", tag, line);
                            }
                        }
                    } finally {
                        br.close();
                    }
                } catch (Exception ignored) {
                    // 进程结束后流关闭，正常退出
                }
            }
        }, "web-dev-log-" + tag);
        reader.setDaemon(true);
        reader.start();
    }

    private boolean isPortInUse(int port) {
        try {
            Socket socket = new Socket();
            try {
                socket.connect(new InetSocketAddress("127.0.0.1", port), 300);
                return true;
            } finally {
                socket.close();
            }
        } catch (Exception e) {
            return false;
        }
    }

    @PreDestroy
    public void shutdown() {
        Process process = webProcess;
        if (process != null && process.isAlive()) {
            log.info("[web] 正在停止前端 dev server...");
            process.destroy();
            try {
                if (!process.waitFor(5, TimeUnit.SECONDS)) {
                    process.destroyForcibly();
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                process.destroyForcibly();
            }
        }
    }
}
