package com.doubledimple.ocicommon.utils;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.annotation.PostConstruct;
import javax.servlet.http.HttpServletRequest;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.URL;
import java.util.Enumeration;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

/**
 * @version 1.0.0
 * @ClassName IpUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-01 23:39
 */
@Slf4j
@Component
public class IpUtils {

    // 公网IP缓存
    private static final AtomicReference<String> publicIpCache = new AtomicReference<>();
    // 本地IP缓存
    private static final AtomicReference<String> localIpCache = new AtomicReference<>();
    // 缓存锁
    private static final ReadWriteLock cacheLock = new ReentrantReadWriteLock();
    // 缓存过期时间（毫秒）
    private static final long CACHE_EXPIRE_TIME = TimeUnit.HOURS.toMillis(1);
    // 上次更新时间
    private static long lastUpdateTime = 0;

    // 公网IP获取服务URL列表（按优先级排序）
    private static final String[] PUBLIC_IP_SERVICES = {
            "http://checkip.amazonaws.com",
            "https://api.ipify.org",
            "https://icanhazip.com",
            "http://myexternalip.com/raw",
            "http://ipinfo.io/ip"
    };

    /**
     * 初始化时预加载IP地址
     */
    @PostConstruct
    public void init() {
        // 异步预加载，避免影响应用启动
        new Thread(() -> {
            try {
                log.info("预加载服务器IP地址...");
                getPublicIp();
                getLocalIp();
                log.info("服务器IP地址加载完成：公网IP={}，本地IP={}",
                        publicIpCache.get(), localIpCache.get());
            } catch (Exception e) {
                log.warn("预加载服务器IP地址失败：{}", e.getMessage());
            }
        }).start();
    }

    /**
     * 获取服务器公网IP地址
     * @return 公网IP地址，获取失败返回本地IP或localhost
     */
    public static String getPublicIp() {
        if (isCacheValid() && publicIpCache.get() != null) {
            return publicIpCache.get();
        }
        cacheLock.writeLock().lock();
        try {
            if (isCacheValid() && publicIpCache.get() != null) {
                return publicIpCache.get();
            }
            for (String service : PUBLIC_IP_SERVICES) {
                try {
                    String ip = getIpFromService(service);
                    if (isValidIp(ip)) {
                        updateCache(ip);
                        return ip;
                    }
                } catch (Exception e) {
                    log.debug("从{}获取公网IP失败: {}", service, e.getMessage());
                }
            }
            String localIp = getLocalIp();
            log.warn("无法获取公网IP，使用本地IP: {}", localIp);
            return localIp;
        } finally {
            cacheLock.writeLock().unlock();
        }
    }

    /**
     * 获取服务器本地IP地址
     * @return 本地IP地址，获取失败返回localhost
     */
    public static String getLocalIp() {
        // 检查缓存
        if (localIpCache.get() != null) {
            return localIpCache.get();
        }

        try {
            // 尝试获取非回环地址
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                NetworkInterface networkInterface = interfaces.nextElement();
                // 跳过禁用或回环接口
                if (networkInterface.isLoopback() || !networkInterface.isUp()) {
                    continue;
                }

                Enumeration<InetAddress> addresses = networkInterface.getInetAddresses();
                while (addresses.hasMoreElements()) {
                    InetAddress address = addresses.nextElement();
                    // 只使用IPv4地址
                    if (address.getHostAddress().indexOf(':') == -1) {
                        String ip = address.getHostAddress();
                        localIpCache.set(ip);
                        return ip;
                    }
                }
            }

            // 如果没有找到合适的接口，使用常规方法
            InetAddress localHost = InetAddress.getLocalHost();
            String ip = localHost.getHostAddress();
            localIpCache.set(ip);
            return ip;
        } catch (Exception e) {
            log.warn("获取本地IP失败: {}", e.getMessage());
            return "localhost";
        }
    }

    /**
     * 从指定服务获取公网IP
     */
    private static String getIpFromService(String serviceUrl) throws Exception {
        URL url = new URL(serviceUrl);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(5000);
        connection.setReadTimeout(5000);
        connection.setRequestMethod("GET");

        try (BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream()))) {
            String ip = reader.readLine();
            if (ip != null) {
                return ip.trim();
            }
        } finally {
            connection.disconnect();
        }

        throw new Exception("无法从服务获取IP");
    }

    /**
     * 检查缓存是否有效
     */
    private static boolean isCacheValid() {
        return System.currentTimeMillis() - lastUpdateTime < CACHE_EXPIRE_TIME;
    }

    /**
     * 更新缓存
     */
    private static void updateCache(String ip) {
        publicIpCache.set(ip);
        lastUpdateTime = System.currentTimeMillis();
        log.info("更新公网IP缓存: {}, 缓存时间: {}小时", ip, CACHE_EXPIRE_TIME / 3600000);
    }

    /**
     * 手动刷新IP缓存
     * @return 刷新后的公网IP
     */
    public static String refreshIpCache() {
        cacheLock.writeLock().lock();
        try {
            publicIpCache.set(null);
            lastUpdateTime = 0;
            return getPublicIp();
        } finally {
            cacheLock.writeLock().unlock();
        }
    }

    /**
     * 检查IP地址是否有效
     */
    private static boolean isValidIp(String ip) {
        if (ip == null || ip.isEmpty()) {
            return false;
        }

        // 简单的IP格式验证
        String ipPattern = "^([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\." +
                "([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\." +
                "([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\." +
                "([01]?\\d\\d?|2[0-4]\\d|25[0-5])$";

        return ip.matches(ipPattern) && !ip.equals("127.0.0.1");
    }


    /**
     * 获取客户端真实IP（支持多级反向代理）
     *
     * @param request HttpServletRequest
     * @return 客户端真实IP，无法识别时返回 "unknown"
     */
    public static String getClientIpAddress(HttpServletRequest request) {
        if (request == null) {
            return "unknown";
        }

        // 依次检查常见的代理头部
        String[] headerNames = {
                "X-Forwarded-For",
                "Proxy-Client-IP",
                "WL-Proxy-Client-IP",
                "HTTP_CLIENT_IP",
                "HTTP_X_FORWARDED_FOR",
                "X-Real-IP"
        };

        String ip = null;

        for (String header : headerNames) {
            String value = request.getHeader(header);
            if (StringUtils.hasText(value) && !"unknown".equalsIgnoreCase(value)) {
                ip = value;
                break;
            }
        }

        if (!StringUtils.hasText(ip) || "unknown".equalsIgnoreCase(ip)) {
            ip = request.getRemoteAddr();
        }

        // X-Forwarded-For 可能有多个IP，第一个才是真实来源
        if (ip != null && ip.contains(",")) {
            ip = ip.split(",")[0].trim();
        }

        // 本地访问的特殊处理
        if ("0:0:0:0:0:0:0:1".equals(ip)) {
            ip = "127.0.0.1";
        }
        return ip;
    }

    /**
     * 静态工具方法：访问外部服务获取本机公网IP
     */
    public static String getPublicIp2() {
        try {
            URL url = new URL("http://checkip.amazonaws.com");
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(2000);
            connection.setReadTimeout(2000);
            try (BufferedReader in = new BufferedReader(new InputStreamReader(connection.getInputStream()))) {
                return in.readLine().trim();
            }
        } catch (Exception e) {
            return "获取超时(请检查网络)";
        }
    }
}
