package com.doubledimple.dao.entity;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.ToString;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import javax.persistence.Transient;
import javax.persistence.Version;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * @author doubleDimple
 * @date 2024:10:08日 22:11
 */
@Entity
@Table(name = "OTHER_BOOT_INSTANCE")
@ToString
public class OtherBootInstance {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Version
    @Column(name = "version",columnDefinition = "BIGINT DEFAULT 0")
    private Long version;

    @Column(name = "boot_id")
    private String bootId;

    @Column(name = "tenant_id")
    private Long tenantId;
    private int ocpu;
    private int memory;
    private int disk;
    private int instanceCount;
    //0 : 未开机 1:开机中  2:已开机
    private int status;
    //架构类型
    private String architecture;
    private String rootPassword;
    private String publicIp = "0.0.0.0";

    private String remark;

    private String instanceName;

    private String zone;

    /**
     * 创建时间
     */
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Column(updatable = false)
    private LocalDateTime createdAt;

    /**
     * 修改时间 - 自动更新
     */
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime updatedAt;

    /**
    * 云厂商类型(不包含oracle)
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
    */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 2")
    private int cloudType = 2;

    @Transient
    private String defName;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getBootId() {
        return bootId;
    }

    public void setBootId(String bootId) {
        this.bootId = bootId;
    }

    public Long getTenantId() {
        return tenantId;
    }

    public void setTenantId(Long tenantId) {
        this.tenantId = tenantId;
    }

    public int getOcpu() {
        return ocpu;
    }

    public void setOcpu(int ocpu) {
        this.ocpu = ocpu;
    }

    public int getMemory() {
        return memory;
    }

    public void setMemory(int memory) {
        this.memory = memory;
    }

    public int getDisk() {
        return disk;
    }

    public void setDisk(int disk) {
        this.disk = disk;
    }

    public int getInstanceCount() {
        return instanceCount;
    }

    public void setInstanceCount(int instanceCount) {
        this.instanceCount = instanceCount;
    }

    public int getStatus() {
        return status;
    }

    public void setStatus(int status) {
        this.status = status;
    }

    public String getArchitecture() {
        return architecture;
    }

    public void setArchitecture(String architecture) {
        this.architecture = architecture;
    }

    public String getRootPassword() {
        return rootPassword;
    }

    public void setRootPassword(String rootPassword) {
        this.rootPassword = rootPassword;
    }

    public String getPublicIp() {
        return publicIp;
    }

    public void setPublicIp(String publicIp) {
        this.publicIp = publicIp;
    }

    // 修改这两个方法，使其返回 LocalDateTime 而不是 String
    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    // 为前端显示添加格式化方法
    @Transient // 告诉 JPA 这不是数据库字段
    public String getFormattedCreatedAt() {
        if (createdAt == null) return "";
        return createdAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    @Transient
    public String getFormattedUpdatedAt() {
        if (updatedAt == null) return "";
        return updatedAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    public String getRemark() {
        return remark;
    }
    public void setRemark(String remark) {
        this.remark = remark;
    }
    public int getCloudType() {
        return cloudType;
    }
    public void setCloudType(int cloudType) {
        this.cloudType = cloudType;
    }

    public Long getVersion() {
        return version;
    }

    public void setVersion(Long version) {
        this.version = version;
    }

    public String getInstanceName() {
        return instanceName;
    }

    public void setInstanceName(String instanceName) {
        this.instanceName = instanceName;
    }
    public String getZone() {
        return zone;
    }
    public void setZone(String zone) {
        this.zone = zone;
    }

    public String getDefName() {
        return defName;
    }
    public void setDefName(String defName) {
        this.defName = defName;
    }
}
