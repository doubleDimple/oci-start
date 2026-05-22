package com.doubledimple.dao.entity;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;

/**
 * @version 1.0.0
 * @ClassName OciSshConn
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-22 16:09
 */
@Data
@Entity
@Table(name = "Oci_ssh_conn")
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class CloudSshConn {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String instanceId;


    /**
     * 用户名
     */
    @Column(name = "name", nullable = false)
    private String name;

    /**
     * 备注
     */
    @Column(name = "remark", nullable = false)
    private String remark;

    /**
     * ssh连接的用户名
     */
    @Column(name = "username", nullable = false)
    private String username;

    /**
     * host域名
     */
    @Column(name = "host")
    private String host;

    /**
     * ssh连接的端口
     */
    @Column(name = "port")
    private Integer port;

    @Column(name = "password")
    private String password;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    /** 文件夹ID */
    @Column(name = "folder_id")
    private Long folderId;
}
