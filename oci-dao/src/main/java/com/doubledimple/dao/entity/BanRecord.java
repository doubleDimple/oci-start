package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName AppVersion
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "ban_record",indexes = {
        @Index(name = "idx_ip", columnList = "ip_address"),
        @Index(name = "idx_status", columnList = "status"),
        @Index(name = "idx_ip_status", columnList = "ip_address,status")
})
@Slf4j
public class BanRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 被封禁的 IP 地址
     */
    @Column(name = "ip_address", nullable = false, length = 64)
    private String ipAddress;

    /**
     * 触发来源（例如 登录失败、恶意登录、手动封禁 等）
     */
    @Column(name = "source", length = 128)
    private String source;

    /**
     * 操作用户名（可选，来自 Telegram 昵称）
     */
    @Column(name = "operator_name", length = 64)
    private String operatorName;

    /**
     * 封禁原因描述
     */
    @Column(name = "reason", length = 255)
    private String reason;

    /**
     * 封禁状态：1=封禁中，0=已解除
     */
    @Column(name = "status", nullable = false)
    private Integer status = 1;

    /**
     * 创建时间
     */
    @Column(name = "create_time", nullable = false)
    private LocalDateTime createTime = LocalDateTime.now();

    /**
     * 解除时间（如果解封则记录）
     */
    @Column(name = "unban_time")
    private LocalDateTime unbanTime;

    /**
     * 备注信息
     */
    @Column(name = "remark", length = 255)
    private String remark;

}
