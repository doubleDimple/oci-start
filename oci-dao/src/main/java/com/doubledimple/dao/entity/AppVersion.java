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
@Table(name = "app_version")
@Slf4j
public class AppVersion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "current_version")
    private String currentVersion;

    @Column(name = "latest_version")
    private String latestVersion;

    @Column(name = "deploy_type")
    @Enumerated(EnumType.STRING)
    private DeployType deployType;

    @Column(name = "update_time")
    private LocalDateTime updateTime;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    public enum DeployType {
        SSH,
        DOCKER
    }

    public boolean needUpdate() {
        if (log.isDebugEnabled()){
            log.info("比较版本 - currentVersion: '{}'", currentVersion);
            log.info("比较版本 - latestVersion: '{}'", latestVersion);
        }
        return !currentVersion.equals(latestVersion);
    }
}
