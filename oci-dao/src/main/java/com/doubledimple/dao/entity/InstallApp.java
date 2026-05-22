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
 * @ClassName InstallApp
 * @Description 应用安装记录实体类
 * @Author doubleDimple
 * @Date 2025-08-23
 */
@Data
@Entity
@Table(name = "install_app")
@Slf4j
public class InstallApp {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "unique_id", nullable = false, unique = true)
    private String uniqueId;

    @Column(name = "ip_address", nullable = false)
    private String ipAddress;

    @Column(name = "install_time", nullable = false)
    private LocalDateTime installTime;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    @Column(name = "update_time")
    private LocalDateTime updateTime;
}
