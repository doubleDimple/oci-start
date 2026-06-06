package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class ProxyConfig {
    private boolean enabled;
    private String type = "HTTP"; // HTTP 或 SOCKS5
    private String host = "127.0.0.1";
    private int port = 7890;
    private String username = ""; // 可选,留空表示不带认证
    private String password = ""; // 可选,留空表示不带认证
}
