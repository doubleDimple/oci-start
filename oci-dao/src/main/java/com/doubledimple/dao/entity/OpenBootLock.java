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
@Table(name = "open_boot_lock")
@Slf4j
public class OpenBootLock {

    @Id
    @Column(name = "task_id", length = 64, nullable = false)
    private String taskId;

    /**
     * 云厂商类型
     * 默认值为 1
     */
    @Column(name = "cloud_type", nullable = false, columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    /**
     * 任务状态
     * "PROCESSING": 抢锁成功，正在创建
     * "SUCCESS":    创建成功
     */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    /**
     * 云主机实例 ID
     * 成功后回填，用于防止重复请求时直接返回结果
     */
    @Column(name = "ins_id", length = 128)
    private String instanceId;

    /**
     * 创建时间
     * 用于排查僵尸锁
     */
    @Column(name = "create_time")
    private LocalDateTime createTime;

    /**
     * 【便捷构造器】用于 Service 层抢锁时快速创建对象
     * 自动设置 createTime 为当前时间
     *
     * @param taskId 任务ID
     * @param cloudType 云厂商类型
     * @param status 初始状态 (通常是 PROCESSING)
     */
    public OpenBootLock(String taskId, int cloudType, String status) {
        this.taskId = taskId;
        this.cloudType = cloudType;
        this.status = status;
        this.createTime = LocalDateTime.now();
    }

    public OpenBootLock() {

    }

    public enum Status {
        PROCESSING,
        SUCCESS
    }
}
