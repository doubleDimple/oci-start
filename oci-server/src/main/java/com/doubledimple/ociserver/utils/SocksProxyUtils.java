package com.doubledimple.ociserver.utils;

import com.doubledimple.dao.entity.VpnProxyRecord;
import lombok.extern.slf4j.Slf4j;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.Socket;
import java.net.SocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * @version 1.0.0
 * @ClassName SocksProxyUtils
 * @Description 通用代理工具类，支持检测 SOCKS5 / HTTP 代理连通性
 * @Author doubleDimple
 * @Date 2025-11-01
 */
@Slf4j
public class SocksProxyUtils {

    private static final int TIMEOUT_MS = 3000;
    private static final String TEST_HOST = "www.oracle.com";
    private static final int TEST_PORT = 443;

    /**
     * 检测代理是否可用
     * 自动识别 SOCKS5 / HTTP
     *
     * @return 是否可用
     */
    public static boolean isProxyAvailable(VpnProxyRecord proxyConfig) {
        final String host = proxyConfig.getProxyHost();
        final Integer port = proxyConfig.getProxyPort();
        final String type = proxyConfig.getProxyType();
        final String proxyUsername = proxyConfig.getProxyUsername();
        final String proxyPassword = proxyConfig.getProxyPassword();
        if (host == null || host.isEmpty() || port <= 0) {
            log.warn("代理参数无效: host={}, port={}", host, port);
            return false;
        }

        try {
            if ("HTTP".equalsIgnoreCase(type) || "HTTPS".equalsIgnoreCase(type)) {
                if (proxyUsername != null && !proxyUsername.isEmpty() && proxyPassword != null && !proxyPassword.isEmpty()){
                    return testHttpProxy(host, port, proxyUsername, proxyPassword);
                }else{
                    return testHttpProxy(host, port);
                }
            } else { // 默认 SOCKS5
                return testSocksProxy(host, port);
            }
        } catch (Exception e) {
            log.warn("代理检测异常: {}:{} [{}] -> {}", host, port, type, e.getMessage());
            return false;
        }
    }

    /**
     * 检测 SOCKS5 代理是否可用
     */
    private static boolean testSocksProxy(String host, int port) {
        Proxy proxy = new Proxy(Proxy.Type.SOCKS, new InetSocketAddress(host, port));
        try (Socket socket = new Socket(proxy)) {
            socket.connect(new InetSocketAddress(TEST_HOST, TEST_PORT), TIMEOUT_MS);
            log.debug("SOCKS5代理可用: {}:{}", host, port);
            return true;
        } catch (IOException e) {
            log.debug("SOCKS5代理不可用: {}:{} -> {}", host, port, e.getMessage());
            return false;
        }
    }

    /**
     * 检测 HTTP 代理是否可用（发送 CONNECT 请求）
     */
    private static boolean testHttpProxy(String host, int port) {
        SocketAddress addr = new InetSocketAddress(host, port);
        try (Socket socket = new Socket()) {
            socket.connect(addr, TIMEOUT_MS);

            String connectCmd = "CONNECT " + TEST_HOST + ":" + TEST_PORT + " HTTP/1.1\r\n"
                    + "Host: " + TEST_HOST + ":" + TEST_PORT + "\r\n"
                    + "User-Agent: ProxyChecker/1.0\r\n"
                    + "Proxy-Connection: Keep-Alive\r\n\r\n";

            OutputStream out = socket.getOutputStream();
            out.write(connectCmd.getBytes());
            out.flush();

            socket.setSoTimeout(TIMEOUT_MS);
            byte[] buffer = new byte[128];
            int read = socket.getInputStream().read(buffer);

            if (read > 0) {
                String response = new String(buffer, 0, read);
                if (response.contains("200")) {
                    log.debug("HTTP代理可用: {}:{}", host, port);
                    return true;
                }
            }

            log.debug("HTTP代理无效响应: {}:{}", host, port);
            return false;
        } catch (IOException e) {
            log.debug("HTTP代理不可用: {}:{} -> {}", host, port, e.getMessage());
            return false;
        }
    }

    private static boolean testHttpProxy(String host, int port, String username, String password) {
        SocketAddress addr = new InetSocketAddress(host, port);
        try (Socket socket = new Socket()) {
            socket.connect(addr, TIMEOUT_MS);

            StringBuilder connectCmd = new StringBuilder();
            connectCmd.append("CONNECT ").append(TEST_HOST).append(":").append(TEST_PORT).append(" HTTP/1.1\r\n")
                    .append("Host: ").append(TEST_HOST).append(":").append(TEST_PORT).append("\r\n")
                    .append("User-Agent: ProxyChecker/1.0\r\n")
                    .append("Proxy-Connection: Keep-Alive\r\n");

            // 如果有用户名和密码，添加认证头
            if (username != null && !username.isEmpty() && password != null && !password.isEmpty()) {
                String auth = username + ":" + password;
                String encodedAuth = Base64.getEncoder().encodeToString(auth.getBytes(StandardCharsets.UTF_8));
                connectCmd.append("Proxy-Authorization: Basic ").append(encodedAuth).append("\r\n");
            }

            connectCmd.append("\r\n");

            OutputStream out = socket.getOutputStream();
            out.write(connectCmd.toString().getBytes(StandardCharsets.UTF_8));
            out.flush();

            socket.setSoTimeout(TIMEOUT_MS);
            byte[] buffer = new byte[256];
            int read = socket.getInputStream().read(buffer);

            if (read > 0) {
                String response = new String(buffer, 0, read, StandardCharsets.UTF_8);
                if (response.contains("200")) {
                    log.debug("HTTP代理可用: {}:{} (用户:{})", host, port, username);
                    return true;
                }
            }

            log.debug("HTTP代理无效响应: {}:{}", host, port);
            return false;
        } catch (IOException e) {
            log.debug("HTTP代理不可用: {}:{} -> {}", host, port, e.getMessage());
            return false;
        }
    }

}
