package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.jcraft.jsch.ChannelShell;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import java.io.IOException;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.ConsoleTest;

/**
 * @version 1.0.0
 * @ClassName BiosUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-04-08 09:05
 */
@Slf4j
public class BiosUtils {

    public static TerminalSession autoEnterBios(Tenant tenant, String instanceId) {
        log.info("开始自动化进入实例BIOS: " + instanceId);

        try {
            // 1. 创建控制台连接
            String connectionString = ConsoleTest(tenant, instanceId);

            // 解析连接字符串，获取SSH连接信息
            Pattern pattern = Pattern.compile("ssh -i (.*?) -o .* ([^@]+@[^ ]+)");
            Matcher matcher = pattern.matcher(connectionString);

            if (!matcher.find()) {
                throw new IllegalArgumentException("无法解析连接字符串: " + connectionString);
            }

            String privateKeyPath = matcher.group(1);
            String hostInfo = matcher.group(2);

            // 分割用户名和主机
            String[] userHost = hostInfo.split("@");
            String user = userHost[0];
            String host = userHost[1];
            int port = 22; // 默认SSH端口

            // 2. 使用JSch创建SSH会话
            JSch jsch = new JSch();
            jsch.addIdentity(privateKeyPath);
            Session session = jsch.getSession(user, host, port);
            session.setConfig("StrictHostKeyChecking", "no");
            session.connect();

            // 3. 创建Shell通道
            ChannelShell channel = (ChannelShell)session.openChannel("shell");

            // 设置IO流
            PipedOutputStream shellInput = new PipedOutputStream();
            PipedInputStream shellIn = new PipedInputStream(shellInput);
            PipedOutputStream shellOutput = new PipedOutputStream();
            PipedInputStream shellOut = new PipedInputStream(shellOutput);

            channel.setInputStream(shellIn);
            channel.setOutputStream(shellOutput);

            // 连接通道
            channel.connect();

            // 4. 发送重启命令
            log.info("发送重启命令");
            shellInput.write("sudo reboot\n".getBytes());
            shellInput.flush();

            // 5. 监控输出，等待BIOS提示并自动按键
            Thread monitorThread = new Thread(() -> {
                try {
                    byte[] buffer = new byte[1024];
                    StringBuilder consoleOutput = new StringBuilder();
                    boolean biosCaptured = false;

                    while (!biosCaptured) {
                        int bytesRead = shellOut.read(buffer);
                        if (bytesRead > 0) {
                            String output = new String(buffer, 0, bytesRead);
                            consoleOutput.append(output);
                            log.debug("控制台输出: " + output);

                            // 检查是否出现进入BIOS的提示 (各种可能的提示文本)
                            if (containsBiosPrompt(consoleOutput.toString())) {
                                log.info("检测到BIOS提示，发送进入BIOS的按键");
                                // 尝试不同的BIOS按键组合
                                sendBiosKeys(shellInput);
                                biosCaptured = true;
                            }

                            // 限制缓冲区大小，防止内存溢出
                            if (consoleOutput.length() > 50000) {
                                consoleOutput.delete(0, 25000);
                            }
                        }
                    }

                    log.info("成功进入BIOS界面");

                } catch (Exception e) {
                    log.error("监控控制台输出失败: " + e.getMessage(), e);
                }
            });

            monitorThread.start();
            // 设置超时，防止无限等待
            monitorThread.join(120000); // 等待最多2分钟

            if (monitorThread.isAlive()) {
                log.warn("等待进入BIOS超时");
                monitorThread.interrupt();
            }

            // 返回会话和通道，以便调用者可以继续交互
            return new TerminalSession(session, channel, shellInput, shellOut);

        } catch (Exception e) {
            log.error("自动进入BIOS失败: " + e.getMessage(), e);
            throw new RuntimeException("自动进入BIOS失败", e);
        }
    }

    // 检查控制台输出是否包含BIOS提示
    private static boolean containsBiosPrompt(String consoleOutput) {
        // 各种可能的BIOS提示文本
        String[] biosPrompts = {
                "Press F2 to enter BIOS",
                "Press DEL to enter Setup",
                "Press Esc to enter BIOS settings",
                "Press F12 for boot menu",
                "Press <Tab> to show POST screen",
                "BIOS Configuration Utility",
                "Setup: Enter for BIOS settings",
                // Oracle VM特定提示
                "Oracle VM BIOS",
                "Press F1 to enter BIOS setup"
        };

        for (String prompt : biosPrompts) {
            if (consoleOutput.contains(prompt)) {
                return true;
            }
        }
        return false;
    }

    // 发送进入BIOS的按键组合
    private static void sendBiosKeys(PipedOutputStream shellInput) throws IOException, InterruptedException {
        // 尝试各种可能的BIOS按键
        // 注意：通过SSH发送特殊按键需要使用特定的转义序列

        // 尝试F2
        shellInput.write(new byte[] {27, 79, 81}); // F2的ANSI转义序列
        shellInput.flush();
        Thread.sleep(200);

        // 尝试DEL键
        shellInput.write(new byte[] {127});
        shellInput.flush();
        Thread.sleep(200);

        // 尝试ESC键
        shellInput.write(new byte[] {27});
        shellInput.flush();
        Thread.sleep(200);

        // 尝试Tab键
        shellInput.write(new byte[] {9});
        shellInput.flush();
        Thread.sleep(200);

        // 尝试F1键
        shellInput.write(new byte[] {27, 79, 80}); // F1的ANSI转义序列
        shellInput.flush();
    }

    // 用于存储和返回会话信息的数据类
    @Data
    public static class TerminalSession {
        private final Session sshSession;
        private final ChannelShell channel;
        private final PipedOutputStream input;
        private final PipedInputStream output;
    }
}
