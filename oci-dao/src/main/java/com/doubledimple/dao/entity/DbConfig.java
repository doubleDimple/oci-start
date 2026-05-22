package com.doubledimple.dao.entity;

import lombok.Builder;
import lombok.Data;
import org.springframework.util.StringUtils;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName DbConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-31 22:50
 */
@Data
@Entity
@Table(name = "db_configs")
public class DbConfig {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private Long tenantId;

    @Column(name = "db_name")
    private String dbName = "";
    @Column(name = "db_private_url")
    private String dbPrivateUrl;
    @Column(name = "db_public_url")
    private String dbPublicUrl = "";
    @Column(name = "db_port")
    private Integer dbPort;
    @Column(name = "db_password")
    private String dbPassword = "";
    @Column(name = "db_id", length = 128)
    private String dbId;

    @Column(name = "db_version")
    private String dbVersion;

    @Column(name = "db_storage_size")
    private Integer dataStorageSizeInGBs;

    //1: 读写模式2: 只读模式
    @Column(name = "db_data_base_mode")
    private String databaseMode;

    //备注名称
    @Column(name = "db_display_name", length = 256)
    private String displayName;

    @Column(name = "db_shape_name", length = 64)
    private String shapeName;

    @Column(name = "db_availability_domain", length = 64)
    private String availabilityDomain;

    //高可用 1:高可用,0:非高可用
    @Column(name = "db_high_available")
    private Integer highlyAvailable;

    @Column(name = "db_subnet_id", length = 128)
    private String subnetId;
    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private Integer cloudType = 1;

    //数据类型,1:mysql 2: oracle
    @Column(name = "db_type", columnDefinition = "INTEGER DEFAULT 1")
    private Integer dbType = 1;

    @Column(name = "db_status")
    private String dbStatus = "";

    private LocalDateTime createAt;
    private LocalDateTime updatedAt;
}
