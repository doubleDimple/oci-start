package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName SystemConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 12:56
 */
@Entity
@Table(name = "system_config")
@Data
public class SystemConfig {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "config_key", unique = true)
    private String key;

    @Column(name = "config_value", length = 1000)
    private String value;

    @Column(name = "config_enabled")
    private boolean enabled = false;

    @Column(name = "last_modified")
    private LocalDateTime lastModified;

    @PreUpdate
    @PrePersist
    public void updateLastModified() {
        lastModified = LocalDateTime.now();
    }

}
