package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.1.0
 * @ClassName SslCertificate
 * @Description SSL Certificate entity supporting Let's Encrypt (acme4j) and Cloudflare Origin CA
 * @Author doubleDimple
 * @Date 2025-09-23 14:16
 */
@Data
@Entity
@Table(name = "ssl_certificate")
public class SslCertificate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 绑定的域名
     */
    @Column(name = "domain", nullable = false)
    private String domain;

    /**
     * 证书类型（LETS_ENCRYPT / CLOUDFLARE）
     */
    @Column(name = "certificate_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private CertificateType certificateType = CertificateType.CLOUDFLARE;

    /**
     * 申请人邮箱（LETS_ENCRYPT 必须，CLOUDFLARE 可选）
     */
    @Column(name = "email")
    private String email;

    /**
     * 验证方式（DNS / HTTP）
     */
    @Column(name = "validation_method")
    @Enumerated(EnumType.STRING)
    private ValidationMethod validationMethod = ValidationMethod.DNS;

    /**
     * 是否自动续期
     */
    @Column(name = "auto_renew")
    private Boolean autoRenew = true;

    /**
     * 当前证书状态
     */
    @Column(name = "certificate_status")
    @Enumerated(EnumType.STRING)
    private CertificateStatus status = CertificateStatus.PENDING;

    /**
     * 签发日期
     */
    @Column(name = "issue_date")
    private LocalDateTime issueDate;

    /**
     * 过期日期
     */
    @Column(name = "expire_date")
    private LocalDateTime expireDate;

    /**
     * 证书文件路径（PEM/PKCS12）
     */
    @Column(name = "certificate_path")
    private String certificatePath;

    /**
     * 私钥文件路径
     */
    @Column(name = "private_key_path")
    private String privateKeyPath;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    /**
     * DNS服务商（用于域名验证）
     */
    @Column(name = "dns_provider")
    @Enumerated(EnumType.STRING)
    private DnsProvider dnsProvider;

    @PrePersist
    protected void onCreate() {
        createTime = LocalDateTime.now();
        updateTime = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updateTime = LocalDateTime.now();
    }

    public enum CertificateType {
        LETS_ENCRYPT, // 通过 acme4j 获取，90 天
        CLOUDFLARE   // 通过 Cloudflare Origin CA API 获取，最长 10-15 年
        ;

        public static CertificateType fromString(String value) {
            for (CertificateType type : values()) {
                if (type.name().equalsIgnoreCase(value)) {
                    return type;
                }
            }
            return null;
        }
    }

    public enum ValidationMethod {
        DNS,   // 通过 DNS-01 验证（LETS_ENCRYPT 支持，CLOUDFLARE 生成时无需）
        HTTP   // 通过 HTTP-01 验证（LETS_ENCRYPT）
    }

    public enum CertificateStatus {
        PENDING,        // 等待申请
        VALID,          // 已生效
        EXPIRING_SOON,  // 即将过期
        EXPIRED,        // 已过期
        ERROR           // 申请失败
    }

    public enum DnsProvider {
        CLOUDFLARE,     // Cloudflare DNS
        ALIYUN,         // 阿里云DNS
        TENCENT,        // 腾讯云DNS
        DNSPOD,         // DNSPod
        AWS_ROUTE53,    // AWS Route53
        GODADDY,        // GoDaddy
        MANUAL          // 手动管理（需要用户手动添加TXT记录）
        ;
        public static DnsProvider fromString(String value) {
            for (DnsProvider provider : values()) {
                if (provider.name().equalsIgnoreCase(value)) {
                    return provider;
                }
            }
            return null;
        }
    }
}
