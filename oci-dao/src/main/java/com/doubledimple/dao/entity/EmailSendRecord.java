package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName 邮件发送记录
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "Email_send_record")
@Slf4j
public class EmailSendRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 邮件发送的业务id
     */
    @Column(name = "email_send_record_id")
    private String emailSendRecordId;

    /**
     * 邮箱主体的业务id
     */
    @Column(name = "email_body_id")
    private String emailBodyId;

    /**
     * 邮箱发送的邮箱
     */
    @Column(name = "email_send_address")
    private String emailSendAddress;

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
     * 收件人id,对应EmailReceive
     */
    @Column(name = "email_receive_id")
    private Long emailReceiveId;

    /**
     * 收件人邮箱,对应EmailReceive
     */
    @Column(name = "receive_email_address")
    private String receiveEmailAddress;

    /**
     * 邮件发送状态 0:发送失败 1:发送成功
     */
    @Column(name = "send_state")
    private Integer sendState = 1;


    /**
    * 时间
    */
    @Column(name = "create_time")
    private LocalDateTime createTime;



}
