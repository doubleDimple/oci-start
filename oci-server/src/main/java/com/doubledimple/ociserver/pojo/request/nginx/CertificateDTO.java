package com.doubledimple.ociserver.pojo.request.nginx;

import lombok.Data;

import java.time.LocalDateTime;

@Data
public class CertificateDTO {
    private Long id;
    private String name;           // 证书名称
    private String domain;         // 域名
    private String certPath;       // 证书文件路径
    private String keyPath;        // 私钥文件路径
    private LocalDateTime expiryDate;  // 过期时间
    private String issuer;         // 颁发机构
}
