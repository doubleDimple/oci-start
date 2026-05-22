package com.doubledimple.ocicommon.utils;

import com.doubledimple.ocicommon.param.ScriptResult;
import com.jcraft.jsch.JSch;
import lombok.extern.slf4j.Slf4j;
import net.schmizz.sshj.SSHClient;
import net.schmizz.sshj.common.IOUtils;
import net.schmizz.sshj.connection.channel.direct.Session;
import net.schmizz.sshj.transport.verification.PromiscuousVerifier;

import java.nio.file.Paths;
import java.util.Properties;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/**
 * @version 1.0.0
 * @ClassName SshUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-04 16:40
 */
@Slf4j
public class SshUtils {

    private static final int TIMEOUT = 60000;  // 连接超时时间 1分钟
    private static final int EXEC_TIMEOUT = 30 * 60 * 1000;  // 脚本执行超时时间 30分钟

    /**
    * 秘钥连接
    */
    public static ScriptResult executeScript(String host, String username, String privateKeyPathUrl, String scriptContent) {
        log.debug("开始执行远程连接,host:{},username:{},privateKeyPath:{}", host, username, privateKeyPathUrl);

        // 转换私钥路径为绝对路径
        String absoluteKeyPath = convertToAbsolutePath(privateKeyPathUrl);
        log.info("转换后的私钥绝对路径: {}", absoluteKeyPath);

        SSHClient ssh = new SSHClient();
        try {
            // 配置SSH客户端
            ssh.addHostKeyVerifier(new PromiscuousVerifier());
            ssh.loadKnownHosts();

            // 设置连接超时
            ssh.setConnectTimeout(TIMEOUT);
            ssh.setTimeout(TIMEOUT);

            // 连接到服务器
            log.debug("正在连接到服务器...");
            ssh.connect(host);
            log.debug("服务器连接成功");

            // 使用私钥认证
            log.debug("正在进行私钥认证...");
            ssh.authPublickey(username, absoluteKeyPath);
            log.debug("认证成功");

            // 创建会话并执行命令
            try (Session session = ssh.startSession()) {
                log.debug("开始执行脚本...");
                Session.Command cmd = session.exec(scriptContent);

                // 使用Future来处理超时
                ExecutorService executor = Executors.newSingleThreadExecutor();
                Future<ScriptResult> future = executor.submit(() -> {
                    try {
                        // 获取输出
                        String output = IOUtils.readFully(cmd.getInputStream()).toString();
                        String error = IOUtils.readFully(cmd.getErrorStream()).toString();

                        // 等待命令完成
                        cmd.join();

                        // 获取退出状态
                        Integer exitStatus = cmd.getExitStatus();

                        log.debug("脚本执行完成，退出状态: {}", exitStatus);
                        if (!error.isEmpty()) {
                            log.error("错误输出: {}", error);
                        }

                        return ScriptResult.builder()
                                .success(exitStatus != null && exitStatus == 0)
                                .exitCode(exitStatus != null ? exitStatus : -1)
                                .output(output)
                                .error(error)
                                .build();
                    } catch (Exception e) {
                        log.error("执行脚本过程中发生错误", e);
                        throw new RuntimeException("执行脚本失败", e);
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
            }
        } catch (Exception e) {
            log.error("SSH执行失败", e);
            throw new RuntimeException("SSH执行失败: " + e.getMessage(), e);
        } finally {
            try {
                ssh.disconnect();
                log.debug("SSH连接已断开");
            } catch (Exception e) {
                log.error("断开SSH连接时发生错误", e);
            }
        }
    }


    /**
    * 密码连接
    */
    public static ScriptResult executeScriptByPass(String host, String username, String password, String scriptContent) {
        log.debug("开始执行远程连接,host:{},username:{},password:{}", host, username,password);

        SSHClient ssh = new SSHClient();
        try {
            // 配置SSH客户端
            ssh.addHostKeyVerifier(new PromiscuousVerifier());
            ssh.loadKnownHosts();

            // 设置连接超时
            ssh.setConnectTimeout(TIMEOUT);
            ssh.setTimeout(TIMEOUT);

            // 连接到服务器
            log.debug("正在连接到服务器...");
            ssh.connect(host);
            log.debug("服务器连接成功");

            // 使用密码认证
            log.debug("正在进行密码认证...");
            ssh.authPassword(username, password);
            log.debug("认证成功");

            // 创建会话并执行命令
            try (Session session = ssh.startSession()) {
                log.debug("开始执行脚本...");
                Session.Command cmd = session.exec(scriptContent);

                // 使用Future来处理超时
                ExecutorService executor = Executors.newSingleThreadExecutor();
                Future<ScriptResult> future = executor.submit(() -> {
                    try {
                        // 获取输出
                        String output = IOUtils.readFully(cmd.getInputStream()).toString();
                        String error = IOUtils.readFully(cmd.getErrorStream()).toString();

                        // 等待命令完成
                        cmd.join();

                        // 获取退出状态
                        Integer exitStatus = cmd.getExitStatus();

                        log.debug("脚本执行完成，退出状态: {}", exitStatus);
                        if (!error.isEmpty()) {
                            log.error("错误输出: {}", error);
                        }

                        return ScriptResult.builder()
                                .success(exitStatus != null && exitStatus == 0)
                                .exitCode(exitStatus != null ? exitStatus : -1)
                                .output(output)
                                .error(error)
                                .build();
                    } catch (Exception e) {
                        log.error("执行脚本过程中发生错误", e);
                        throw new RuntimeException("执行脚本失败", e);
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
            }
        } catch (Exception e) {
            log.error("SSH执行失败", e);
            return ScriptResult.builder()
                    .success(false)
                    .exitCode(-1)
                    .error("SSH执行失败: " + e.getMessage())
                    .build();
        } finally {
            try {
                ssh.disconnect();
                log.debug("SSH连接已断开");
            } catch (Exception e) {
                log.error("断开SSH连接时发生错误", e);
            }
        }
    }





    private static String convertToAbsolutePath(String path) {
            if (path.startsWith("/")) {
                return path; // 已经是绝对路径
            }

            // 如果以 ./ 开头，移除它
            if (path.startsWith("./")) {
                path = path.substring(2);
            }

            // 获取应用程序的工作目录
            String userDir = System.getProperty("user.dir");
            return Paths.get(userDir, path).toAbsolutePath().normalize().toString();

    }


}
