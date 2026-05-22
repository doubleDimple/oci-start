package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;

/**
 * @author doubleDimple
 * @date 2024:11:03日 15:31
 */
@Data
@Entity
@Table(name = "instance_backup_detail")
public class InstanceBackUpDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private long tenantId;
    private String instanceId;
    private String displayName;
    private String shape;
    private String state;
    /**
    * CPU核心数
    */
    private Integer ocpus;
    /**
    * 内存大小(GB)
    */
    private Integer memoryInGBs;
    /**
    * 引导卷大小(GB)
    */
    private Long bootVolumeSizeInGBs;
    /**
    * 附加的数据卷
    */
    //private BlockVolume blockVolumes;
    // 网络信息
    private String publicIps;
    private String privateIps;
    // 其他信息
    private String availabilityDomain;
    private String compartmentId;
    private String bootVolumeId;
    //private Map<String, String> freeformTags;

    private String remark;

    private String bootVolumeName;

    @Column(length = 1000)  // 设置更长的长度
    private String ipv6Addresses;

    /**
    * ssh连接的用户名
    */
    @Column(name = "username")
    private String username = "";

    /**
     * ssh连接的端口
     */
    @Column(name = "port")
    private Integer port = 22;

    @Column(name = "password")
    private String password = "";

    /**
     * 架构类型全称
     */
    @Column(name = "processorDescription")
    private String processorDescription = "NONE";

    /**
     * 架构类型简称
     */
    private String architecture = "NONE";

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;


    /**
     * 系统是否备份
     * 0:未备份  1:已备份
     */
    @Column(name = "sys_image_backup", columnDefinition = "INTEGER DEFAULT 0")
    private int sysImageBackup = 0;


}
