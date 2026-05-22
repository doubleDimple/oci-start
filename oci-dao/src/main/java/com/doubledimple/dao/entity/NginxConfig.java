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
 * @version 1.0.0
 * @ClassName NginxConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-23 14:18
 */
@Data
@Entity
@Table(name = "nginx_config")
public class NginxConfig {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "config_name")
    private String configName;

    @Column(name = "config_content", columnDefinition = "TEXT")
    private String configContent;

    @Column(name = "is_current")
    private Boolean isCurrent = false;

    @Column(name = "config_version")
    private Integer configVersion = 1;

    @Column(name = "config_status")
    @Enumerated(EnumType.STRING)
    private ConfigStatus configStatus = ConfigStatus.DRAFT;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    @PrePersist
    protected void onCreate() {
        createTime = LocalDateTime.now();
        updateTime = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updateTime = LocalDateTime.now();
    }

    public enum ConfigStatus {
        DRAFT, TESTING, APPLIED, ERROR
    }
}
