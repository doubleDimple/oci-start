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
 * @ClassName CloudTenancy
 * @Description 云租户配置实体类
 * @Author doubleDimple
 * @Date 2025-07-26 10:51
 */
@Data
@Entity
@Table(name = "cloud_tenancy")
@Slf4j
public class CloudTenancy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
    * 云厂商的租户名
    */
    @Column(name = "tenancy_name", nullable = false, length = 256)
    private String tenancyName;

    @Column(name = "cloud_type", nullable = false)
    private Integer cloudType;

    /**
    * 自定义类型
     * 1: 租户名自定义
     * 2: 实例自定义
    */
    @Column(name = "type", nullable = false, columnDefinition = "INT DEFAULT 1")
    private Integer type;

    /**
    * 自定义名称
    */
    @Column(name = "def_name", length = 200)
    private String defName;

    @Column(name = "account_cost", length = 200)
    private String accountCost;

    @Column(name = "create_time")
    private LocalDateTime createTime;

    @Column(name = "update_time")
    private LocalDateTime updateTime;
}
