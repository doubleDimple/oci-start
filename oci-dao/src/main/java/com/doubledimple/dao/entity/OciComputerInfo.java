package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;

/**
 * @version 1.0.0
 * @ClassName OciComputerCreate
 * @Description TODO
 * @Author renyx
 * @Date 2025-10-29 13:44
 */
@Data
@Entity
@Table(name = "oci_computer_info")
@Slf4j
public class OciComputerInfo {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String bootIdStr; //对应bootInstance里面的bootId

    //实例创建json集合串
    @Column(columnDefinition = "text")
    private String computerCreateJson;

    //租户id
    @Column(name = "tenant_id")
    private Long tenantId;

    //架构
    @Column(name = "architecture")
    private String architecture;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    //区域
    @Column(name = "computer_region")
    private String region = "NONE";
}
