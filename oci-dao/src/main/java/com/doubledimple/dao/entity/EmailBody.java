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
@Table(name = "email_body")
@Slf4j
public class EmailBody {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "email_body_id", unique = true, nullable = false)
    private String emailBodyId;

    /**
    * 租户id
    */
    @Column(name = "current_version")
    private Long tenantId;

    /**
     * 租户名称
     */
    @Column(name = "tenant_name")
    private String tenantName;

    /**
    * 邮箱配置主键id
    */
    @Column(name = "tenant_email_config_id")
    private Long tenantEmailConfigId;

    /**
     * 邮箱配置表的发件人
     */
    @Column(name = "sender_email")
    private String senderEmail;

    /**
     * 邮箱标题
     */
    @Column(name = "title")
    private String title;

    /**
     * 邮箱内容
     */
    @Column(name = "content")
    private String content;

    /**
     * 收件人数量
     */
    @Column(name = "receive_total")
    private Long receiveTotal;

    /**
     * 发送成功数量
     */
    @Column(name = "receive_success_total")
    private Long receiveSuccessTotal;

    /**
     * 发送失败数量
     */
    @Column(name = "receive_fail_total")
    private Long receiveFailTotal;

    /**
    * 时间
    */
    @Column(name = "create_time")
    private LocalDateTime createTime;
}
