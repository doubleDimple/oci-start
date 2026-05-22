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
 * @ClassName EmailReceive
 * @Description 邮件收件人实体类
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "email_receive")
@Slf4j
public class EmailReceive {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 收件人邮箱
     */
    @Column(name = "email", nullable = false)
    private String email;

    /**
     * 收件人名称
     */
    @Column(name = "name", nullable = false)
    private String name;

    /**
     * 创建时间
     */
    @Column(name = "create_time")
    private LocalDateTime createTime;

    /**
     * 更新时间
     */
    @Column(name = "update_time")
    private LocalDateTime updateTime;
}
