package com.doubledimple.ocicommon.utils;

import com.doubledimple.ocicommon.param.ScriptResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.jcraft.jsch.Channel;
import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.JSchException;
import com.jcraft.jsch.Session;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.io.IOUtils;
import org.springframework.http.MediaType;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/**
 * @version 1.0.0
 * @ClassName JschUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-04 17:01
 */
@Slf4j
public class JschUtils {

    private static final int TIMEOUT = 60000;  // 连接超时时间 1分钟
    private static final int EXEC_TIMEOUT = 30 * 60 * 1000;  // 脚本执行超时时间 30分钟

    /**
    * 原arm 系统镜像下载地址
    */
    public static final String SOURCE_DOWNLOAD_IMAGE_URL = "wget --no-check-certificate https://github.com/honorcnboy/BlogDatas/releases/download/OracleRescueKit/dabian10.arm.img.gz -O /root/dabian10.arm.img.gz";

    /**
    * 自用系统镜像下载地址
    */
    public static final String MYSELF_DOWNLOAD_IMAGE_URL = "wget --no-check-certificate https://github.com/doubleDimple/shell-tools/releases/download/image/dabian10.arm.img.gz -O /root/dabian10.arm.img.gz";

    /**
    * sdb执行
    */
    private static final String SCREEN_CMD_SDB = "screen -dmS rescue bash -c '" +
            "rm -f /root/rescue_status/* && " +
            "echo \"writing\" > /root/rescue_status/status && " +
            "gzip -dc /root/dabian10.arm.img.gz | dd of=/dev/sdb bs=4M && " +
            "if [ $? -eq 0 ]; then echo \"completed\" > /root/rescue_status/status; else echo \"failed\" > /root/rescue_status/status; fi'";

    //dd执行
    public static final String DD_SCRIPT = "curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_\n";

    //public static final String DD_SCRIPT_PARAM = "curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && (echo \"%s\"; echo \"%s\") | bash reinstall.sh %s %s";

    public static final String DD_SCRIPT_PARAM =
            "(command -v curl >/dev/null 2>&1 || apt update -y && apt install -y curl wget || yum install -y curl wget || dnf install -y curl wget) && " +
                    "curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || " +
                    "wget -O reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && " +
                    "(echo \"%s\"; echo \"%s\") | bash reinstall.sh %s %s";

    public static final String AMD_DD_SCRIPT =
            "(command -v curl >/dev/null 2>&1 || apt update -y && apt install -y curl wget || yum install -y curl wget || dnf install -y curl wget) && " +
                    "curl -fsSLo reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || " +
                    "wget -O reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && " +
                    "(echo '%s'; echo '%s') | bash reinstall.sh %s %s && " +
                    "if [ \"$(uname -m)\" = \"x86_64\" ]; then " +
                    "echo '🔧 AMD detected — fixing EFI boot...' && " +
                    "(mount /dev/sda2 /mnt 2>/dev/null || mount /dev/vda2 /mnt || mount /dev/nvme0n1p2 /mnt) && " +
                    "(mount /dev/sda1 /mnt/boot/efi 2>/dev/null || mount /dev/vda1 /mnt/boot/efi || mount /dev/nvme0n1p1 /mnt/boot/efi) && " +
                    "for fs in dev proc sys; do mount --bind /$fs /mnt/$fs; done && " +
                    "chroot /mnt /bin/bash -c 'apt update -y || dnf makecache -y; " +
                    "apt install -y grub-efi-amd64 shim-signed isc-dhcp-client || dnf install -y grub2-efi-x64 shim-x64 dhclient; " +
                    "(grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck || " +
                    "grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=OL --recheck); " +
                    "(update-grub || grub2-mkconfig -o /boot/grub2/grub.cfg); " +
                    "echo \"auto ens3\\niface ens3 inet dhcp\" > /etc/network/interfaces.d/ens3.cfg; " +
                    "(systemctl enable ssh || systemctl enable sshd || true);' && " +
                    "umount -R /mnt && echo '✅ EFI boot fixed, rebooting...' && reboot; " +
                    "else echo 'ARM detected — skipping EFI fix, rebooting...' && reboot; fi";



    public static final String DEBIAN_INSTALL_SCRIPT =
            "bash <(curl -sSL https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh) " +
                    "-debian %s --nomemcheck -pwd '%s' --network \"static\"  && reboot";





    //重启命令
    public static final String REBOOT_CMD = "reboot";

    //分区处理后执行DD脚本
    public static final String DF_SCRIPT= "#!/bin/bash\n"
            + "SYSTEM_PARTITION=$(mount | grep \" / \" | cut -d' ' -f1)\n"
            + "echo \"系统分区是: $SYSTEM_PARTITION\"\n"
            + "echo \"开始扩展系统分区文件系统...\"\n"
            + "resize2fs $SYSTEM_PARTITION\n"
            + "echo \"扩展完成，当前分区大小：\"\n"
            + "df -h $SYSTEM_PARTITION\n";


    public static final String UPGRADE_AND_INIT_SCRIPT = "bash << 'EOF'\n" +
            "export DEBIAN_FRONTEND=noninteractive\n" +
            "export NEEDRESTART_MODE=a\n" +
            "export NEEDRESTART_SUSPEND=1\n" +
            "apt install -y cloud-guest-utils || true\n"+
            "resize2fs /dev/sda2 || true\n"+
            "apt upgrade -y && apt full-upgrade -y && apt --purge autoremove -y && \\\n" +
            "echo 'deb http://deb.debian.org/debian bullseye main contrib non-free\n" +
            "deb http://security.debian.org/debian-security bullseye-security main contrib non-free\n" +
            "deb http://deb.debian.org/debian bullseye-updates main contrib non-free' > /etc/apt/sources.list && \\\n" +
            "apt update && apt upgrade --without-new-pkgs -y && apt full-upgrade -y && apt update && \\\n" +
            "apt install lsb-release sudo wget curl -y && \\\n" +
            "wget -O upgrade_and_init.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/upgrade_and_init.sh && \\\n" +
            "chmod +x upgrade_and_init.sh && \\\n" +
            "./upgrade_and_init.sh\n" +
            "EOF";

    public static final String MERGE_DF_AND_DD_SCRIPT = "#!/bin/bash\n"
            + "# 先执行分区扩展以确保有足够空间进行系统重装\n"
            + "SYSTEM_PARTITION=$(mount | grep \" / \" | cut -d' ' -f1)\n"
            + "echo \"系统分区是: $SYSTEM_PARTITION\"\n"
            + "echo \"开始扩展系统分区文件系统...\"\n"
            + "resize2fs $SYSTEM_PARTITION\n"
            + "echo \"扩展完成，当前分区大小：\"\n"
            + "df -h $SYSTEM_PARTITION\n"
            + "# 分区扩展完成后，执行系统重装\n"
            + "echo \"开始执行系统重装...\"\n"
            + "bash <(curl -sSL https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh) -debian 12 --nomemcheck -pwd 'OciStart2025' --network \"static\" -setdisk \"all\"";

    private static final ObjectMapper objectMapper = new ObjectMapper();

    public static ScriptResult executeScriptJsch(String host, String username, String password,int port, String scriptContent) {
        log.debug("开始执行远程连接,host:{},username:{},password:{}", host, username,password);

        JSch jsch = new JSch();
        Session session = null;

        try {
            // 创建SSH会话
            session = jsch.getSession(username, host, port); // 使用默认的22端口，如需自定义可以添加端口参数
            session.setPassword(password);

            // 设置SSH连接属性
            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no"); // 不验证主机密钥
            session.setConfig(config);

            // 设置连接超时时间
            session.setConfig("ConnectTimeout", String.valueOf(TIMEOUT));

            // 建立连接
            log.debug("正在连接到服务器...");
            session.connect(TIMEOUT);
            log.debug("服务器连接成功");

            // 创建执行通道
            Channel channel = session.openChannel("exec");
            ((ChannelExec) channel).setCommand(scriptContent);

            // 获取输入输出流
            InputStream stdout = channel.getInputStream();
            InputStream stderr = ((ChannelExec) channel).getErrStream();

            // 使用Future来处理超时
            ExecutorService executor = Executors.newSingleThreadExecutor();
            Future<ScriptResult> future = executor.submit(() -> {
                try {
                    // 连接通道并执行命令
                    log.debug("开始执行脚本...");
                    channel.connect();

                    // 读取输出
                    String output = IOUtils.toString(stdout, StandardCharsets.UTF_8);
                    String error = IOUtils.toString(stderr, StandardCharsets.UTF_8);

                    // 等待命令执行完成
                    while (!channel.isClosed()) {
                        try {
                            Thread.sleep(100);
                        } catch (Exception e) {
                            break;
                        }
                    }

                    // 获取退出状态
                    int exitStatus = channel.getExitStatus();

                    log.debug("脚本执行完成，退出状态: {}", exitStatus);
                    if (!error.isEmpty()) {
                        log.debug("错误输出: {}", error);
                    }

                    return ScriptResult.builder()
                            .success(exitStatus == 0)
                            .exitCode(exitStatus)
                            .output(output)
                            .error(error)
                            .build();
                } catch (Exception e) {
                    log.error("执行脚本过程中发生错误", e);
                    return ScriptResult.builder()
                            .success(false)
                            .exitCode(-1)
                            .error("执行脚本失败: " + e.getMessage())
                            .build();
                } finally {
                    if (channel != null) {
                        channel.disconnect();
                    }
                }
            });

            try {
                // 等待执行完成或超时
                return future.get(EXEC_TIMEOUT, TimeUnit.MILLISECONDS);
            } catch (TimeoutException e) {
                log.error("脚本执行超时: {} 分钟", EXEC_TIMEOUT / 60000);
                future.cancel(true);
                return ScriptResult.builder()
                        .success(false)
                        .exitCode(-1)
                        .error("执行超时: " + (EXEC_TIMEOUT / 60000) + " 分钟")
                        .build();
            } finally {
                executor.shutdownNow();
            }
        } catch (JSchException e) {
            if (e.getMessage().contains("connect failed") || e.getMessage().contains("Connection refused")) {
                log.error("无法连接到服务器: {}", e.getMessage());
                return ScriptResult.builder()
                        .success(false)
                        .exitCode(-1)
                        .error("无法连接到服务器: " + e.getMessage())
                        .build();
            } else if (e.getMessage().contains("Auth fail")) {
                log.error("认证失败: 请检查用户名和密码");
                return ScriptResult.builder()
                        .success(false)
                        .exitCode(-1)
                        .error("认证失败: 请检查用户名和密码")
                        .build();
            } else {
                log.error("SSH执行失败", e);
                return ScriptResult.builder()
                        .success(false)
                        .exitCode(-1)
                        .error("SSH执行失败: " + e.getMessage())
                        .build();
            }
        } catch (Exception e) {
            log.error("执行过程中发生未知错误", e);
            return ScriptResult.builder()
                    .success(false)
                    .exitCode(-1)
                    .error("执行过程中发生未知错误: " + e.getMessage())
                    .build();
        } finally {
            if (session != null && session.isConnected()) {
                session.disconnect();
                log.debug("SSH连接已断开");
            }
        }
    }

    public static ScriptResult executeDDScript(String host, String username, String password, int port, String scriptContent) {
        log.debug("开始执行 DD 重装, host:{}, username:{}, password:{}", host, username, password);

        JSch jsch = new JSch();
        Session session = null;

        try {
            session = jsch.getSession(username, host, port);
            session.setPassword(password);

            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no");
            session.setConfig(config);

            log.info("正在连接服务器...");
            session.connect(TIMEOUT);
            log.info("DD 重装模式：连接成功");

            ChannelExec channel = (ChannelExec) session.openChannel("exec");
            channel.setCommand(scriptContent);
            channel.setPty(true); // DD 脚本执行需要伪终端环境，必须开启

            InputStream input = channel.getInputStream();
            InputStream error = channel.getErrStream();

            channel.connect();

            StringBuilder logBuffer = new StringBuilder();
            byte[] buffer = new byte[1024];
            int len;

            log.info("开始监听输出... 只要看到 reboot 字样，视为成功");

            while (true) {
                // 读取标准输出
                while (input.available() > 0 && (len = input.read(buffer)) != -1) {
                    String msg = new String(buffer, 0, len, StandardCharsets.UTF_8);
                    logBuffer.append(msg);
                    log.info(msg.trim());

                    // ✅ 成功特征 1：脚本输出「reboot」
                    if (msg.toLowerCase().contains("reboot")) {
                        log.info("检测到系统即将重启 → DD 重装成功");
                        return ScriptResult.builder()
                                .success(true)
                                .exitCode(0)
                                .output(logBuffer.toString())
                                .build();
                    }
                }

                // 读取错误输出（但不视为失败）
                while (error.available() > 0 && (len = error.read(buffer)) != -1) {
                    String msg = new String(buffer, 0, len, StandardCharsets.UTF_8);
                    logBuffer.append(msg);
                    log.warn(msg.trim());
                }

                if (channel.isClosed()) {
                    int status = channel.getExitStatus();
                    log.info("通道关闭 exitStatus={}", status);
                    return ScriptResult.builder()
                            .success(true)
                            .exitCode(status)
                            .output(logBuffer.toString())
                            .build();
                }

                Thread.sleep(200);
            }

        } catch (Exception e) {
            log.error("DD 执行异常", e);
            return ScriptResult.builder()
                    .success(false)
                    .exitCode(-1)
                    .error("执行异常: " + e.getMessage())
                    .build();
        } finally {
            if (session != null && session.isConnected()) {
                session.disconnect();
            }
        }
    }



    /**
     * 生成动态ping脚本
     * @param ipAddresses 要ping的IP地址列表
     * @return 脚本内容
     */
    public static String generatePingScript(List<String> ipAddresses, int count) {
        StringBuilder script = new StringBuilder();

        // 添加脚本头部
        script.append("#!/bin/bash\n\n");
        script.append("echo \"开始执行ping测试...\"\n");
        script.append("echo \"----------------------------------------\"\n\n");

        // 为每个IP添加ping命令
        for (String ip : ipAddresses) {
            script.append("echo \"正在ping ").append(ip).append("...\"\n");
            script.append("ping -c ").append(count).append(" ").append(ip).append("\n");
            script.append("if [ $? -eq 0 ]; then\n");
            script.append("    echo \"✓ 成功: ").append(ip).append(" 可达\"\n");
            script.append("else\n");
            script.append("    echo \"✗ 失败: ").append(ip).append(" 不可达\"\n");
            script.append("fi\n");
            script.append("echo \"----------------------------------------\"\n\n");
        }

        script.append("echo \"ping测试完成！\"\n");

        return script.toString();
    }


    /**
    * @Description: oci救援脚本执行
    */
    public static RescueStatus executeOciRescueCommands(String host, String username, String password, WebSocketSession webSocketSession) {
        JSch jsch = new JSch();
        Session session = null;
        RescueStatus status = new RescueStatus();

        try {
            // 1. 建立 SSH 连接
            sendMessage(webSocketSession, "[连接] 正在连接到救援服务器...\r\n");
            session = jsch.getSession(username, host, 22);
            session.setPassword(password);
            session.setConfig("StrictHostKeyChecking", "no");
            session.connect(30000);
            log.info("SSH connected to {}@{}", username, host);
            sendMessage(webSocketSession, "[连接] 成功连接到救援服务器\r\n");


            // 2. 检查并安装screen
            sendMessage(webSocketSession, "[环境检查] 正在检查并安装必要的软件...\r\n");
            log.info("检查 screen 是否已安装...");
            executeCommand(session, "which screen || apt-get update && apt-get install -y screen");
            sendMessage(webSocketSession, "[环境检查] 环境准备完成\r\n");


            // 3. 执行 lsblk 命令检查设备
            sendMessage(webSocketSession, "[设备检查] 正在检查可用设备...\r\n");
            String lsblkResult = executeCommand(session, "lsblk");
            log.info("设备列表:\n{}", lsblkResult);
            //sendMessage(webSocketSession, "[设备信息] 设备列表:\r\n" + lsblkResult + "\r\n");


            if (!lsblkResult.contains("sdb")) {
                sendMessage(webSocketSession, "[错误] ❌ 未找到 /dev/sdb 设备，无法继续\r\n");
                status.setStatus("failed");
                status.setMessage("未找到 /dev/sdb 设备");
                return status;
            }
            sendMessage(webSocketSession, "[设备检查] ✅ 已找到目标设备 /dev/sdb\r\n");


            // 4. 下载救援镜像
            sendMessage(webSocketSession, "[准备工作] 开始下载救援镜像，这可能需要几分钟...\r\n");
            log.info("开始下载救援镜像...");
            status.setStatus("downloading");
            executeCommand(session,
                    MYSELF_DOWNLOAD_IMAGE_URL);
            sendMessage(webSocketSession, "[准备工作] ✅ 救援镜像下载完成\r\n");

            // 5. 创建标志文件目录
            sendMessage(webSocketSession, "[准备工作] 创建状态监控目录...\r\n");
            executeCommand(session, "mkdir -p /root/rescue_status");
            sendMessage(webSocketSession, "[准备工作] ✅ 状态监控目录创建完成\r\n");

            sendMessage(webSocketSession, "[写入过程] ⏳ 开始将救援镜像写入磁盘，这将在后台进行...\r\n");
            // 6. 在 screen 中启动写入命令，并在完成后创建标志文件
            String screenCmd = "screen -dmS rescue bash -c '" +
                    "rm -f /root/rescue_status/* && " +  // 清除旧的状态文件
                    "echo \"writing\" > /root/rescue_status/status && " +
                    "gzip -dc /root/dabian10.arm.img.gz | dd of=/dev/sdb bs=4M && " +
                    "if [ $? -eq 0 ]; then " +
                    "   echo \"completed\" > /root/rescue_status/status; " +
                    "else " +
                    "   echo \"failed\" > /root/rescue_status/status; " +
                    "fi'";

            executeCommand(session, screenCmd);
            log.info("在 screen 会话中启动写入命令");
            status.setStatus("writing");

            sendMessage(webSocketSession, "[写入过程] 写入已开始，正在检查进度...\r\n");
            // 轮询几次来获取初始进度，每5秒一次，最多3次
            for (int i = 0; i < 3; i++) {
                try {
                    Thread.sleep(5000);
                    String progress = executeCommand(session, "ps aux | grep dd | grep -v grep || echo '未找到写入进程'");
                    //sendMessage(webSocketSession, "[写入进度] " + progress + "\r\n");
                } catch (Exception e) {
                    log.warn("检查进度时出错", e);
                }
            }

            // 7. 返回当前状态
            //sendMessage(webSocketSession, "[写入过程] 📝 后台写入继续进行中，系统将定期检查状态\r\n");
            status.setMessage("写入进程已在后台启动");
            return status;

        } catch (Exception e) {
            log.error("执行救援命令失败", e);
            sendMessage(webSocketSession, "[错误] ❌ 执行救援命令失败: " + e.getMessage() + "\r\n");
            status.setStatus("failed");
            status.setMessage("执行救援命令失败: " + e.getMessage());
            return status;
        } finally {
            if (session != null) {
                session.disconnect();
            }
        }
    }

    /**
    * bootTerminated flase 引导卷未终止,true,引导卷已经终止
     * @Description: oci救援脚本执行2-优化版
    */
    public static RescueStatus executeOciRescueCommands2(String host, String username, String password, WebSocketSession webSocketSession,boolean bootTerminated) {
        JSch jsch = new JSch();
        Session session = null;
        RescueStatus status = new RescueStatus();

        try {
            sendMessage(webSocketSession, "[连接] 正在连接到救援服务器...\r\n");
            session = connectWithRetry(jsch, username, host, password, 5, 30000);
            log.info("SSH connected to {}@{}", username, host);
            sendMessage(webSocketSession, "[连接] 成功连接到救援服务器\r\n");

            // 网络检查
            sendMessage(webSocketSession, "[网络检查] 正在检查网络连通性...\r\n");
            String networkCheck = executeCommand(session, "ping -c 1 -W 1 google.com || echo 'network_down'");
            if (networkCheck.contains("network_down")) {
                sendMessage(webSocketSession, "[警告] ⚠️ 网络尚未连通，某些操作可能失败\r\n");
            } else {
                sendMessage(webSocketSession, "[网络检查] 网络检查执行成功\r\n");
            }

            // 安装 screen
            sendMessage(webSocketSession, "[环境检查] 正在检查并安装必要的软件...\r\n");
            log.info("检查 screen 是否已安装...");
            executeCommand(session, "which screen || (apt-get update && apt-get install -y screen)");
            sendMessage(webSocketSession, "[环境检查] 环境准备成功\r\n");

            // 检查设备
            sendMessage(webSocketSession, "[设备检查] 正在检查可用设备...\r\n");
            String lsblkResult = executeCommand(session, "lsblk");

            if (!lsblkResult.contains("sdb")) {
                    sendMessage(webSocketSession, "[错误] ❌ 未找到 /dev/sdb 设备，无法继续\r\n");
                    status.setStatus("failed");
                    status.setMessage("未找到 /dev/sdb 设备");
                    return status;
            }
            //sendMessage(webSocketSession, "[设备检查] 已成功找到目标设备 /dev/sdb\r\n");


            // 下载救援镜像（带重试）
            sendMessage(webSocketSession, "[准备工作] 开始下载救援镜像，这可能需要几分钟...\r\n");
            boolean downloaded = false;
            for (int i = 0; i < 3; i++) {
                String result = executeCommand(session,
                        MYSELF_DOWNLOAD_IMAGE_URL);
                if (!result.toLowerCase().contains("failed") && !result.toLowerCase().contains("error")) {
                    downloaded = true;
                    break;
                }
                sendMessage(webSocketSession, "[重试] 第 " + (i + 1) + " 次下载失败，3秒后重试...\r\n");
                Thread.sleep(3000);
            }

            if (!downloaded) {
                sendMessage(webSocketSession, "[错误] ❌ 镜像下载失败，终止任务\r\n");
                status.setStatus("failed");
                status.setMessage("救援镜像下载失败");
                return status;
            }

            sendMessage(webSocketSession, "[准备工作] 救援镜像下载成功\r\n");

            // 创建状态目录
            sendMessage(webSocketSession, "[准备工作] 创建状态监控目录...\r\n");
            executeCommand(session, "mkdir -p /root/rescue_status");
            sendMessage(webSocketSession, "[准备工作] 状态监控目录创建成功\r\n");

            // 启动 screen 写入镜像
            //sendMessage(webSocketSession, "[写入过程] ⏳ 开始将救援镜像写入磁盘，这将在后台进行...\r\n");

            executeCommand(session, SCREEN_CMD_SDB);
            status.setStatus("writing");

            sendMessage(webSocketSession, "[写入过程] 写入已开始，正在检查进度...\r\n");

            // 初始写入状态检查
            for (int i = 0; i < 3; i++) {
                try {
                    Thread.sleep(5000);
                    String progress = executeCommand(session, "ps aux | grep dd | grep -v grep || echo '未找到写入进程'");
                    sendMessage(webSocketSession, "[写入过程] 正在写入中,这个过程比较慢,请耐心等待...\r\n");
                } catch (Exception e) {
                    log.warn("检查进度时出错", e);
                }
            }

            sendMessage(webSocketSession, "[写入过程] 📝 后台写入继续进行中，系统将定期检查状态\r\n");
            status.setMessage("写入进程已在后台启动");
            return status;

        } catch (Exception e) {
            log.error("执行救援命令失败", e);
            sendMessage(webSocketSession, "[错误] ❌ 执行救援命令失败: " + e.getMessage() + "\r\n");
            status.setStatus("failed");
            status.setMessage("执行救援命令失败: " + e.getMessage());
            return status;
        } finally {
            if (session != null && session.isConnected()) {
                session.disconnect();
            }
        }
    }

    /**
    * @Description: 链接重试
    */
    private static Session connectWithRetry(JSch jsch, String username, String host, String password, int maxRetries, int timeoutMillis) throws Exception {
        int attempt = 0;
        Exception lastException = null;

        while (attempt < maxRetries) {
            try {
                Session session = jsch.getSession(username, host, 22);
                session.setPassword(password);
                session.setConfig("StrictHostKeyChecking", "no");
                session.connect(timeoutMillis);
                return session;
            } catch (Exception e) {
                lastException = e;
                attempt++;
                if (attempt < maxRetries) {
                    System.err.println("SSH 连接失败，重试中 (" + attempt + "/" + maxRetries + ")... 原因: " + e.getMessage());
                    Thread.sleep(3000);
                }
            }
        }
        throw lastException;
    }



    // 获取救援状态的方法
    public static RescueStatus getRescueStatus(String host, String username, String password) {
        JSch jsch = new JSch();
        Session session = null;
        RescueStatus status = new RescueStatus();

        try {
            session = jsch.getSession(username, host, 22);
            session.setPassword(password);
            session.setConfig("StrictHostKeyChecking", "no");
            session.connect(30000);

            // 读取状态文件
            String statusContent = executeCommand(session, "cat /root/rescue_status/status 2>/dev/null || echo 'unknown'");
            status.setStatus(statusContent.trim());

            // 如果正在写入，获取进度
            if ("writing".equals(status.getStatus())) {
                String progress = executeCommand(session, "pkill -USR1 ^dd$ 2>/dev/null; sleep 1; tail -n 1 /proc/`pgrep dd`/fd/2 2>/dev/null || echo ''");
                if (!progress.isEmpty()) {
                    status.setMessage("正在写入: " + progress.trim());
                } else {
                    status.setMessage("正在写入");
                }
            } else if ("completed".equals(status.getStatus())) {
                status.setMessage("救援镜像写入完成");
            } else if ("failed".equals(status.getStatus())) {
                status.setMessage("救援镜像写入失败");
            }

            return status;

        } catch (Exception e) {
            log.error("获取救援状态失败", e);
            status.setStatus("unknown");
            status.setMessage("获取状态失败: " + e.getMessage());
            return status;
        } finally {
            if (session != null) {
                session.disconnect();
            }
        }
    }

    public static void executeDDScriptWithSse(String host, String username, String password, Integer port, String command, SseEmitter emitter) {

        Session session = null;
        ChannelExec channel = null;
        //匹配所有 ANSI 控制符（颜色、光标、清屏、行清除等）
        final String ANSI_FULL_REGEX = "\\u001B\\[[;?0-9]*[a-zA-Z]";

        try {
            JSch jsch = new JSch();
            session = jsch.getSession(username, host, port);
            session.setPassword(password);

            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no");
            session.setConfig(config);
            session.connect(15000);

            channel = (ChannelExec) session.openChannel("exec");
            channel.setCommand(command);

            //禁用伪终端，否则会产生大量清屏和覆盖输出
            channel.setPty(false);

            InputStream input = channel.getInputStream();
            InputStream error = channel.getErrStream();

            channel.connect();

            byte[] buffer = new byte[2048];
            int len;

            while (true) {

                // STDOUT
                while (input.available() > 0 && (len = input.read(buffer)) != -1) {
                    String msg = new String(buffer, 0, len, StandardCharsets.UTF_8);

                    // 移除所有终端控制字符
                    msg = msg.replaceAll(ANSI_FULL_REGEX, "").trim();
                    if (msg.isEmpty()) continue;

                    send(emitter, "log", msg + "\n");

                    // 检测重装完成提示
                    if (msg.toLowerCase().contains("reboot")) {
                        send(emitter, "success", "检测到 reboot，目标服务器即将自动重启...");
                        return;
                    }
                }

                // STDERR
                while (error.available() > 0 && (len = error.read(buffer)) != -1) {
                    String msg = new String(buffer, 0, len, StandardCharsets.UTF_8)
                            .replaceAll(ANSI_FULL_REGEX, "").trim();
                    if (msg.isEmpty()) continue;
                    send(emitter, "log", msg + "\n");
                }

                //脚本执行完成
                if (channel.isClosed()) {
                    break;
                }

                Thread.sleep(200);
            }

        } catch (Exception e) {
            try { send(emitter, "error", "执行失败：" + e.getMessage()); } catch (Exception ignore) {}
            log.warn("executeDDScriptWithSse 执行失败,原因为:{}", e.getMessage());

        } finally {
            if (channel != null && channel.isConnected()) channel.disconnect();
            if (session != null && session.isConnected()) session.disconnect();
        }
    }



    private static void send(SseEmitter emitter, String event, String msg) {
        try {
            if (msg == null || msg.trim().isEmpty() || "undefined".equals(msg)) {
                return;
            }

            emitter.send(
                    SseEmitter.event()
                            .name(event)
                            .data(msg, MediaType.TEXT_PLAIN)
            );
        } catch (Exception ignored) {}
    }



    // 状态类
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class RescueStatus {
        private String status;  // downloading, writing, completed, failed, unknown
        private String message;
    }

    private static String executeCommand(Session session, String command) throws JSchException, IOException {
        ChannelExec channel = null;
        try {
            channel = (ChannelExec) session.openChannel("exec");
            channel.setCommand(command);

            // 获取输出
            ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
            channel.setOutputStream(outputStream);

            // 获取错误输出
            ByteArrayOutputStream errorStream = new ByteArrayOutputStream();
            channel.setErrStream(errorStream);

            channel.connect(30000);

            // 等待命令执行完成
            while (channel.isConnected()) {
                Thread.sleep(100);
            }

            String output = outputStream.toString();
            String error = errorStream.toString();

            // 如果有错误输出，记录日志
            if (!error.isEmpty()) {
                log.warn("Command error output: {}", error);
            }

            return output;

        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        } finally {
            if (channel != null) {
                channel.disconnect();
            }
        }
    }

    // 定义发送消息的辅助方法
    private static void sendMessage(WebSocketSession session, String message) {
        try {
            if (!session.isOpen()) {
                log.warn("Session is closed, cannot send message");
                return;
            }

            // 获取当前时间戳
            String timestamp = java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"));

            // 解析消息类型
            String messageType = "INFO";
            String formattedMessage = message;

            // 根据消息内容确定消息类型和格式化消息
            if (message.contains("成功")) {
                messageType = "SUCCESS";
                formattedMessage = "✅ " + message;
            } else if (message.contains("失败") || message.contains("错误")) {
                messageType = "ERROR";
                formattedMessage = "❌ " + message;
            } else if (message.contains("开始") || message.contains("正在")) {
                messageType = "PROCESS";
                formattedMessage = "⏳ " + message;
            } else if (message.contains("完成")) {
                messageType = "COMPLETE";
                formattedMessage = "✓ " + message;
            }

            Map<String, Object> response = new HashMap<>();
            response.put("type", "output");
            response.put("messageType", messageType);
            response.put("timestamp", timestamp);
            response.put("data", formattedMessage);

            String jsonMessage = objectMapper.writeValueAsString(response);
            session.sendMessage(new TextMessage(jsonMessage));

            log.debug("Message sent successfully: {}", message);
        } catch (IOException e) {
            log.error("Failed to send message", e);
        }
    }

    /**
     * 修改远程服务器root密码
     * @param host 主机地址
     * @param username 用户名
     * @param currentPassword 当前密码
     * @param newPassword 新密码
     * @return 返回操作结果
     */
    public static ScriptResult changeRootPassword(String host, String username, String currentPassword,
                                                  String newPassword) {
        JSch jsch = new JSch();
        Session session = null;

        try {
            // 创建SSH会话
            session = jsch.getSession(username, host, 22);
            session.setPassword(currentPassword);

            // 设置SSH连接属性
            Properties config = new Properties();
            config.put("StrictHostKeyChecking", "no"); // 不验证主机密钥
            session.setConfig(config);

            // 设置连接超时
            session.setConfig("ConnectTimeout", String.valueOf(TIMEOUT));

            // 建立连接
            log.debug("正在连接到服务器进行密码修改...");
            session.connect(TIMEOUT);
            log.debug("服务器连接成功");

            // 创建执行通道执行密码修改命令
            // 使用chpasswd命令修改密码，简化处理避免特殊字符问题
            String command = "echo '" + username + ":" + newPassword + "' | chpasswd";

            ChannelExec channel = null;
            try {
                channel = (ChannelExec) session.openChannel("exec");
                channel.setCommand(command);

                // 获取标准输出和错误输出
                ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
                ByteArrayOutputStream errorStream = new ByteArrayOutputStream();
                channel.setOutputStream(outputStream);
                channel.setErrStream(errorStream);

                // 连接通道
                channel.connect(30000);

                // 等待命令执行完成
                while (channel.isConnected()) {
                    Thread.sleep(100);
                }

                // 检查退出状态
                int exitStatus = channel.getExitStatus();
                String output = outputStream.toString();
                String error = errorStream.toString();

                log.info("命令执行结果: exitStatus={}, output={}, error={}", exitStatus, output, error);

                if (exitStatus == 0) {
                    log.info("密码修改成功");

                    // 验证命令：尝试使用新密码建立连接
                    boolean verificationResult = verifyPasswordChange(host, username, newPassword);

                    if (verificationResult) {
                        return ScriptResult.builder()
                                .success(true)
                                .exitCode(0)
                                .output("密码修改成功并已验证")
                                .build();
                    } else {
                        log.error("密码已修改但验证失败");
                        return ScriptResult.builder()
                                .success(false)
                                .exitCode(-1)
                                .error("密码已修改但验证失败，可能无法使用新密码登录")
                                .build();
                    }
                } else {
                    log.error("密码修改失败: {}, exit code: {}", error, exitStatus);

                    return ScriptResult.builder()
                            .success(false)
                            .exitCode(exitStatus)
                            .error("密码修改失败: " + error)
                            .build();
                }
            } finally {
                if (channel != null) {
                    channel.disconnect();
                }
            }

        } catch (JSchException e) {
            String errorMsg;
            if (e.getMessage().contains("connect failed") || e.getMessage().contains("Connection refused")) {
                errorMsg = "无法连接到服务器: " + e.getMessage();
                log.error(errorMsg);
            } else if (e.getMessage().contains("Auth fail")) {
                errorMsg = "认证失败: 请检查用户名和密码";
                log.error(errorMsg);
            } else {
                errorMsg = "SSH连接失败: " + e.getMessage();
                log.error("SSH连接失败", e);
            }

            return ScriptResult.builder()
                    .success(false)
                    .exitCode(-1)
                    .error(errorMsg)
                    .build();
        } catch (Exception e) {
            String errorMsg = "执行过程中发生未知错误: " + e.getMessage();
            log.error("执行过程中发生未知错误", e);

            return ScriptResult.builder()
                    .success(false)
                    .exitCode(-1)
                    .error(errorMsg)
                    .build();
        } finally {
            if (session != null && session.isConnected()) {
                session.disconnect();
                log.debug("SSH连接已断开");
            }
        }
    }

    public static boolean verifyPasswordChange(String host,String newPassword){
        return verifyPasswordChange(host, "root", newPassword);
    }

    /**
     * 验证密码修改是否成功
     * @param host 主机地址
     * @param username 用户名
     * @param newPassword 新密码
     * @return 验证结果
     */
    public static boolean verifyPasswordChange(String host, String username, String newPassword) {
        JSch jsch = new JSch();
        Session verifySession = null;

        // 最大尝试次数
        final int MAX_ATTEMPTS = 3;
        // 每次尝试之间的延迟时间（毫秒）
        final int RETRY_DELAY = 3000;

        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            try {
                log.debug("尝试第 {} 次连接...", attempt);

                // 尝试使用新密码连接
                verifySession = jsch.getSession(username, host, 22);
                verifySession.setPassword(newPassword);

                Properties config = new Properties();
                config.put("StrictHostKeyChecking", "no");
                verifySession.setConfig(config);

                // 设置较短的超时时间进行验证
                verifySession.setConfig("ConnectTimeout", "5000");
                verifySession.connect(5000);

                // 如果能成功连接，说明密码已经更改成功
                log.debug("验证成功：第 {} 次尝试使用新密码登录成功", attempt);
                return true;
            } catch (JSchException e) {
                log.warn("第 {} 次验证失败：{}", attempt, e.getMessage());

                // 关闭当前会话（如果存在）
                if (verifySession != null && verifySession.isConnected()) {
                    verifySession.disconnect();
                    verifySession = null;
                }

                // 如果不是最后一次尝试，则等待一段时间后再次尝试
                if (attempt < MAX_ATTEMPTS) {
                    log.debug("等待 {} 毫秒后进行第 {} 次尝试...", RETRY_DELAY, attempt + 1);
                    try {
                        Thread.sleep(RETRY_DELAY);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        log.error("线程被中断: {}", ie.getMessage());
                        return false;
                    }
                } else {
                    log.error("验证最终失败：经过 {} 次尝试后仍无法使用新密码登录", MAX_ATTEMPTS);
                }
            }
        }

        return false;
    }


    /**
     * 启用远程服务器的root密码登录功能
     * 适用于Oracle Cloud实例，特别是从备份还原后无法SSH登录的情况
     *
     * @param host 主机地址
     * @param username 用户名（通常是opc、ubuntu等初始用户）
     * @param password 当前密码
     * @param rootPassword 要设置的root密码，如果为null则只启用root登录但不修改密码
     * @param port SSH端口，通常为22
     * @return 执行结果
     */
    public static ScriptResult enableRootLogin(String host, String username, String password,
                                               String rootPassword, int port) {
        log.debug("开始执行root登录启用操作,host:{},username:{}", host, username);

        // 构建脚本内容
        StringBuilder scriptBuilder = new StringBuilder();
        StringBuilder changePasswordBuilder = new StringBuilder();
        scriptBuilder.append("#!/bin/bash\n\n");

        // 检查权限
        scriptBuilder.append("# 检查是否有ROOT权限\n")
                .append("if [ \"$(id -u)\" -ne 0 ]; then\n")
                .append("    echo \"需要ROOT权限，尝试使用sudo\"\n")
                .append("    SUDO_CMD=\"sudo\"\n")
                .append("else\n")
                .append("    SUDO_CMD=\"\"\n")
                .append("fi\n\n");

        // 备份SSH配置
        scriptBuilder.append("# 备份SSH配置\n")
                .append("echo \"备份当前SSH配置...\"\n")
                .append("$SUDO_CMD cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)\n")
                .append("echo \"已备份SSH配置\"\n\n");

        // 修改SSH配置
        scriptBuilder.append("# 修改SSH配置\n")
                .append("echo \"修改SSH配置允许root密码登录...\"\n")
                .append("$SUDO_CMD sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n")
                .append("$SUDO_CMD sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n")
                .append("$SUDO_CMD sed -i 's/^#\\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config\n")
                .append("$SUDO_CMD sed -i 's/^UsePAM no/UsePAM yes/' /etc/ssh/sshd_config\n\n");

        // 设置root密码（如果提供）
        if (rootPassword != null && !rootPassword.isEmpty()) {
            changePasswordBuilder
                    .append("# 设置root密码\n")
                    .append("echo \"设置root密码...\"\n")
                    .append("echo \"root:").append(rootPassword).append("\" | $SUDO_CMD chpasswd\n")
                    .append("echo \"root密码已设置\"\n\n");

            executeScriptJsch(host, username, password, port, changePasswordBuilder.toString());
        }

        // 检查OS类型并进行特定配置
        scriptBuilder.append("# 检测操作系统类型\n")
                .append("if [ -f /etc/os-release ]; then\n")
                .append("    . /etc/os-release\n")
                .append("    OS=$(echo \"$ID\" | tr '[:upper:]' '[:lower:]')\n")
                .append("    echo \"检测到操作系统类型: $OS\"\n")
                .append("    \n")
                .append("    case $OS in\n")
                .append("        ubuntu|debian)\n")
                .append("            echo \"应用Ubuntu/Debian特定配置\"\n")
                .append("            if [ -f /etc/pam.d/sshd ]; then\n")
                .append("                $SUDO_CMD cp /etc/pam.d/sshd /etc/pam.d/sshd.bak\n")
                .append("                $SUDO_CMD sed -i 's/@include common-auth/#@include common-auth/' /etc/pam.d/sshd\n")
                .append("            fi\n")
                .append("            ;;\n")
                .append("        ol|rhel|centos|almalinux|rocky)\n")
                .append("            echo \"应用Oracle/RHEL/CentOS特定配置\"\n")
                .append("            if command -v getenforce >/dev/null 2>&1; then\n")
                .append("                if [ \"$(getenforce)\" = \"Enforcing\" ]; then\n")
                .append("                    echo \"SELinux处于强制模式，设置为宽容模式\"\n")
                .append("                    $SUDO_CMD setenforce 0\n")
                .append("                    $SUDO_CMD sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config\n")
                .append("                fi\n")
                .append("            fi\n")
                .append("            ;;\n")
                .append("    esac\n")
                .append("else\n")
                .append("    echo \"无法检测到操作系统类型，应用通用配置\"\n")
                .append("fi\n\n");

        // 检查sshd_config.d目录
        scriptBuilder.append("# 检查额外配置目录\n")
                .append("if [ -d /etc/ssh/sshd_config.d/ ]; then\n")
                .append("    echo \"检查 /etc/ssh/sshd_config.d/ 目录...\"\n")
                .append("    for file in /etc/ssh/sshd_config.d/*.conf; do\n")
                .append("        if [ -f \"$file\" ]; then\n")
                .append("            echo \"修改配置文件: $file\"\n")
                .append("            $SUDO_CMD sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' \"$file\"\n")
                .append("            $SUDO_CMD sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' \"$file\"\n")
                .append("            $SUDO_CMD sed -i 's/^#\\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' \"$file\"\n")
                .append("        fi\n")
                .append("    done\n")
                .append("fi\n\n");

        // 创建持久化配置脚本
        scriptBuilder.append("# 创建配置持久化脚本\n")
                .append("echo \"创建自动修复配置的脚本...\"\n")
                .append("$SUDO_CMD cat > /tmp/check-ssh-config.sh << 'EOF'\n")
                .append("#!/bin/bash\n")
                .append("\n")
                .append("# 校验SSH配置并确保root密码登录启用\n")
                .append("if ! grep -q \"^PermitRootLogin yes\" /etc/ssh/sshd_config || \\\n")
                .append("   ! grep -q \"^PasswordAuthentication yes\" /etc/ssh/sshd_config; then\n")
                .append("  # 如果配置不正确，重新应用设置\n")
                .append("  sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n")
                .append("  sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n")
                .append("  sed -i 's/^#\\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config\n")
                .append("  \n")
                .append("  # 检查额外配置目录\n")
                .append("  if [ -d /etc/ssh/sshd_config.d/ ]; then\n")
                .append("    for file in /etc/ssh/sshd_config.d/*.conf; do\n")
                .append("      if [ -f \"$file\" ]; then\n")
                .append("        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' \"$file\"\n")
                .append("        sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' \"$file\"\n")
                .append("        sed -i 's/^#\\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' \"$file\"\n")
                .append("      fi\n")
                .append("    done\n")
                .append("  fi\n")
                .append("  \n")
                .append("  # 重启SSH服务\n")
                .append("  if command -v systemctl >/dev/null 2>&1; then\n")
                .append("    systemctl restart sshd\n")
                .append("  else\n")
                .append("    service sshd restart\n")
                .append("  fi\n")
                .append("fi\n")
                .append("EOF\n\n");

        // 设置脚本权限并移动到最终位置
        scriptBuilder.append("# 设置脚本权限并安装\n")
                .append("$SUDO_CMD chmod +x /tmp/check-ssh-config.sh\n")
                .append("$SUDO_CMD mv /tmp/check-ssh-config.sh /usr/local/bin/\n\n");

        // 创建服务或cron任务
        scriptBuilder.append("# 创建系统服务\n")
                .append("if command -v systemctl >/dev/null 2>&1; then\n")
                .append("    echo \"创建systemd服务...\"\n")
                .append("    $SUDO_CMD cat > /tmp/check-ssh-config.service << 'EOF'\n")
                .append("[Unit]\n")
                .append("Description=Check SSH Configuration for Root Login\n")
                .append("After=network.target sshd.service\n")
                .append("\n")
                .append("[Service]\n")
                .append("Type=oneshot\n")
                .append("ExecStart=/usr/local/bin/check-ssh-config.sh\n")
                .append("\n")
                .append("[Install]\n")
                .append("WantedBy=multi-user.target\n")
                .append("EOF\n")
                .append("    $SUDO_CMD mv /tmp/check-ssh-config.service /etc/systemd/system/\n")
                .append("    $SUDO_CMD systemctl daemon-reload\n")
                .append("    $SUDO_CMD systemctl enable check-ssh-config.service\n")
                .append("    echo \"服务已启用，将在每次启动时运行\"\n")
                .append("else\n")
                .append("    echo \"使用rc.local添加启动项...\"\n")
                .append("    if [ -f /etc/rc.local ]; then\n")
                .append("        if ! grep -q \"check-ssh-config.sh\" /etc/rc.local; then\n")
                .append("            $SUDO_CMD sed -i '/^exit 0/i /usr/local/bin/check-ssh-config.sh' /etc/rc.local\n")
                .append("        fi\n")
                .append("    else\n")
                .append("        $SUDO_CMD echo '#!/bin/bash' > /tmp/rc.local\n")
                .append("        $SUDO_CMD echo '/usr/local/bin/check-ssh-config.sh' >> /tmp/rc.local\n")
                .append("        $SUDO_CMD echo 'exit 0' >> /tmp/rc.local\n")
                .append("        $SUDO_CMD mv /tmp/rc.local /etc/\n")
                .append("        $SUDO_CMD chmod +x /etc/rc.local\n")
                .append("    fi\n")
                .append("    echo \"已添加到rc.local\"\n")
                .append("fi\n\n");

        // 重启SSH服务
        scriptBuilder.append("# 重启SSH服务\n")
                .append("echo \"重启SSH服务以应用更改...\"\n")
                .append("if command -v systemctl >/dev/null 2>&1; then\n")
                .append("    $SUDO_CMD systemctl restart sshd\n")
                .append("else\n")
                .append("    $SUDO_CMD service sshd restart\n")
                .append("fi\n\n");

        // 完成
        scriptBuilder.append("# 完成\n")
                .append("echo \"配置完成！\"\n")
                .append("echo \"现在应该可以使用密码进行SSH登录了\"\n")
                .append("echo \"请检查网络和防火墙设置，确保SSH端口(22)已开放\"\n");


        // 执行脚本
        ScriptResult result = new ScriptResult();
        // 如果设置了root密码，尝试验证
        if (rootPassword != null && !rootPassword.isEmpty()) {
            boolean verified = verifyPasswordChange(host, "root", rootPassword);
            if (verified) {
                executeScriptJsch(host, username, rootPassword, port, scriptBuilder.toString());
                log.debug("root密码验证成功");
                result.setOutput(result.getOutput() + "\nroot密码验证成功，可以使用root用户登录");
                result.setSuccess(true);
            } else {
                log.warn("root密码验证失败，但配置已完成");
                result.setOutput(result.getOutput() + "\nroot密码验证失败，但配置已完成，请稍后再尝试登录");
            }
        }else{
            executeScriptJsch(host, username, password, port, scriptBuilder.toString());
        }
        return result;
    }

    /**
     * 验证 SSH 账密是否可以登录成功
     * 每次失败等待 20 秒，最多尝试 10 次
     *
     * @param host 主机
     * @param username 用户名
     * @param password 密码
     * @param port SSH 端口
     * @return true=连接成功，false=失败
     */
    public static boolean tryConnectWithRetry(String host, String username, String password, int port) {

        final int MAX_ATTEMPTS = 20;
        final int DELAY_SECONDS = 10;

        JSch jsch = new JSch();
        Session session = null;

        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {

            try {
                log.debug("尝试第 {} 次连接 {}@{}...", attempt, username, host);

                session = jsch.getSession(username, host, port);
                session.setPassword(password);

                Properties config = new Properties();
                config.put("StrictHostKeyChecking", "no");
                session.setConfig(config);

                // 设置较短连接超时，避免挂死
                session.connect(10000);

                log.info("第 {} 次连接成功！", attempt);
                return true;

            } catch (Exception e) {

                log.debug("第 {} 次连接失败: {}", attempt, e.getMessage());

                // 如果最后一次直接结束
                if (attempt == MAX_ATTEMPTS) {
                    log.error("连接失败超过最大次数，共尝试 {} 次，放弃", MAX_ATTEMPTS);
                    return false;
                }

                // 等待 20 秒再试
                try {
                    log.info("等待 {} 秒后重试...", DELAY_SECONDS);
                    Thread.sleep(DELAY_SECONDS * 1000L);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    log.error("等待被中断: {}", ie.getMessage());
                    return false;
                }
            } finally {
                if (session != null && session.isConnected()) {
                    session.disconnect();
                }
            }
        }

        return false;
    }

}
