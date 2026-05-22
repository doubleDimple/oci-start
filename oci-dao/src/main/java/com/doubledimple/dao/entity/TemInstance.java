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
 * @ClassName AppVersion
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "tem_instance")
@Slf4j
public class TemInstance {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
    * 租户
    */
    @Column(name = "tenancy", length = 255)
    private String tenancy;

    /**
     * 租户
     */
    @Column(name = "instanceId", length = 255)
    private String instanceId;

    /**
    * 公共ip
    */
    @Column(name = "publicIp")
    private String publicIp;

    /**
     * 区域
     */
    @Column(name = "region")
    private String region;

    /**
    *架构类型
    */
    @Column(name = "architecture")
    private String architecture;

    /**
    *实例密码
    */
    @Column(name = "rootPassword")
    private String rootPasswd;


    /**
     *实例密码
     */
    @Column(name = "cloneBootVolumeId",length = 256)
    private String cloneBootVolumeId;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;


}
