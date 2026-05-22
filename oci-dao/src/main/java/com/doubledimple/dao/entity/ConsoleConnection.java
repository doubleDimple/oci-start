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
 * 控制台连接信息实体
 *
 * @author doubleДимple
 * @date 2025-01-01
 */
@Data
@Entity
@Table(name = "console_connections")
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ConsoleConnection {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 实例OCID
     */
    @Column(name = "instance_id", nullable = false, length = 255)
    private String instanceId;

    /**
     * 租户ID
     */
    @Column(name = "tenant_id", nullable = false)
    private Long tenantId;

    /**
     * OCI控制台连接ID
     */
    @Column(name = "connection_id", nullable = false, length = 255)
    private String connectionId;

    /**
     * 私钥文件路径
     */
    @Column(name = "private_key_path", length = 500)
    private String privateKeyPath;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;
}
