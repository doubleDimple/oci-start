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
import javax.persistence.Lob;
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
@Table(name = "APP_MESSAGE")
@Slf4j
public class Message {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    //业务id
    @Column(name = "business_id")
    private String businessId;

    //消息类型
    @Column(name = "message_type")
    @Enumerated(EnumType.STRING)
    private MessageType messageType;

    //消息读取状态,1:已读,0:未读
    @Column(name = "read_status")
    private Integer readStatus;

    //消息主题
    @Column(name = "subject")
    private String subject;

    //消息内容
    @Column(name = "content_text",columnDefinition = "CLOB")
    private String content;

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    public enum MessageType {
        INNER,//站内消息
        SYSTEM//系统消息
    }
}
