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
        return compareVersion(currentVersion, latestVersion) < 0;
    }

    private int compareVersion(String left, String right) {
        String[] leftParts = normalizeVersion(left).split("\\.");
        String[] rightParts = normalizeVersion(right).split("\\.");
        int length = Math.max(leftParts.length, rightParts.length);
        for (int i = 0; i < length; i++) {
            int leftValue = i < leftParts.length ? parseVersionPart(leftParts[i]) : 0;
            int rightValue = i < rightParts.length ? parseVersionPart(rightParts[i]) : 0;
            if (leftValue != rightValue) {
                return Integer.compare(leftValue, rightValue);
            }
        }
        return 0;
    }

    private String normalizeVersion(String version) {
        if (version == null || version.trim().isEmpty()) {
            return "0";
        }
        return version.trim().replaceFirst("^[vV][-_]?", "");
    }

    private int parseVersionPart(String part) {
        if (part == null) {
            return 0;
        }
        String digits = part.replaceAll("[^0-9].*$", "");
        if (digits.isEmpty()) {
            return 0;
        }
        return Integer.parseInt(digits);
    }
}
