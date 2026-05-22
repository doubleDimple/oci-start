package com.doubledimple.ociserver.pojo.request;

/**
 * @version 1.0.0
 * @ClassName ConnectionInfo
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-01 15:53
 */

import lombok.Data;

/**
 * 连接信息缓存类
 */
@Data
public class ConnectionInfo {
    private final String connectionId;
    private final String keyFilePath;
    private final String publicKey;
    private final String connectionString;
    private final long createTime;

    public ConnectionInfo(String connectionId, String keyFilePath, String publicKey, String connectionString) {
        this.connectionId = connectionId;
        this.keyFilePath = keyFilePath;
        this.publicKey = publicKey;
        this.connectionString = connectionString;
        this.createTime = System.currentTimeMillis();
    }

    // 检查是否过期（超过24小时）
    public boolean isExpired() {
        return System.currentTimeMillis() - createTime > 24 * 60 * 60 * 1000;
    }
}
