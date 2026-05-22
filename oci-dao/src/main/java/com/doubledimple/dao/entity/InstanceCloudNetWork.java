package com.doubledimple.dao.entity;


import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
* 抢机需要的网络相关实例映射
*/
@Entity
@Table(name = "instance_cloud_networks")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class InstanceCloudNetWork {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 需要存储oci的用户id 就是tenant表的tenantId
     * provider里面的tenantId实际上试tenant表tenancy
     */
    @Column(name = "tenant_id",  length = 100)
    private String tenantId;

    @Column(name = "vcn_id", length = 100)
    private String vcnId;

    @Column(name = "vcn_name", length = 255)
    private String vcnName;

    @Column(name = "subnet_id",  length = 100)
    private String subnetId;

    @Column(name = "subnet_name", length = 255)
    private String subnetName;

    @Column(name = "region",  length = 50)
    private String region;

    @Column(name = "cidr_block", length = 50)
    private String cidrBlock;

    @Column(name = "net_work_security_group_id", length = 128)
    private String networkSecurityGroupId;


    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;
}
