package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.PrePersist;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * 访问与操作审计日志实体
 *
 * @author doubleDimple
 */
@Data
@Entity
@Table(name = "audit_logs", indexes = {
        @Index(name = "idx_audit_create_time", columnList = "createTime"),
        @Index(name = "idx_audit_username", columnList = "username"),
        @Index(name = "idx_audit_status", columnList = "status"),
        @Index(name = "idx_audit_method", columnList = "method")
})
public class AuditLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 操作人用户名
     */
    @Column(length = 64)
    private String username;

    /**
     * 模块或操作说明
     */
    @Column(length = 128)
    private String title;

    /**
     * HTTP 请求方式 (GET, POST, PUT, DELETE 等)
     */
    @Column(length = 16)
    private String method;

    /**
     * 请求 URI
     */
    @Column(length = 255)
    private String requestUri;

    /**
     * Controller 类及方法名
     */
    @Column(length = 128)
    private String actionMethod;

    /**
     * 客户端真实 IP
     */
    @Column(length = 64)
    private String ip;

    /**
     * IP 归属地 / 地理位置
     */
    @Column(length = 128)
    private String location;

    /**
     * 请求参数 (脱敏后 JSON 或 query 参数)
     */
    @Column(columnDefinition = "TEXT")
    private String params;

    /**
     * HTTP 响应状态码 (200, 400, 401, 500 等)
     */
    private Integer responseStatus;

    /**
     * 操作状态 (1: 成功, 0: 失败)
     */
    private Integer status;

    /**
     * 错误信息 (若执行异常)
     */
    @Column(columnDefinition = "TEXT")
    private String errorMsg;

    /**
     * 执行耗时 (毫秒)
     */
    private Long costTime;

    /**
     * 浏览器 User-Agent
     */
    @Column(length = 500)
    private String userAgent;

    /**
     * 记录创建时间
     */
    private LocalDateTime createTime;

    @PrePersist
    protected void onCreate() {
        if (createTime == null) {
            createTime = LocalDateTime.now();
        }
    }
}
