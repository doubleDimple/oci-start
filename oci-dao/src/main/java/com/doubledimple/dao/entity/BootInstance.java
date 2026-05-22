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
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * @author doubleDimple
 * @date 2024:10:08日 22:11
 */
@Entity
@Table(name = "BOOT_INSTANCE")
@ToString
public class BootInstance {

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
    private int loopTime;
    private int instanceCount;
    //0 : 未开机 1:开机中  2:已开机
    private int status;
    //架构类型
    private String architecture;
    private String rootPassword;
    private String publicIp = "0.0.0.0";
    /**
     * 下次执行时间
     */
    private Timestamp nextExecutionTime;

    /**
     * 当前实例执行创建实例总次数
     */
    @Column(columnDefinition = "BIGINT DEFAULT 0")
    private long addCount;

    /**
     * 当前实例抢机成功次数
     */
    @Column(columnDefinition = "INTEGER DEFAULT 0")
    private int successCount = 0;

    private String remark;

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
    * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
    */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    /** * 当前抢机次数（今天的） */
    @Column(name = "current_attempt_count", columnDefinition = "INTEGER DEFAULT 0")
    private int currentAttemptCount = 0;

    /** * 昨天抢机次数 */
    @Column(name = "yesterday_attempt_count", columnDefinition = "INTEGER DEFAULT 0")
    private int yesterdayAttemptCount = 0;

    /** * 是否已重置为新的一天（防止重复重置） */
    @Column(name = "reset_today_flag", columnDefinition = "BOOLEAN DEFAULT FALSE")
    private boolean resetTodayFlag = false;

    @Column(name = "last_reset_date")
    private LocalDate lastResetDate;

    //抢机失败次数
    @Column(name = "fail_count", columnDefinition = "INTEGER DEFAULT 0")
    private int failCount = 0;

    /*@Column(name = "operation_system")
    private String operationSystem = "Ubuntu";*/

    private Long totalCount;

    //镜像id
    private String imageId;
    //系统名称
    private String operatingSystem;
    // 系统版本，如 20.04
    private String operatingSystemVersion;

    //抢机间隔
    @Column(name = "data_gap")
    private String dayGap;

    //通知标识:已通知: YES 未通知: NO
    @Column(name = "notify_flag")
    private String notifyFlag = "NO";

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

    public int getLoopTime() {
        return loopTime;
    }

    public void setLoopTime(int loopTime) {
        this.loopTime = loopTime;
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

    public Timestamp getNextExecutionTime() {
        return nextExecutionTime;
    }

    public void setNextExecutionTime(Timestamp nextExecutionTime) {
        this.nextExecutionTime = nextExecutionTime;
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

    public long getAddCount() {
        return addCount;
    }

    public void setAddCount(long addCount) {
        this.addCount = addCount;
    }

    public int getSuccessCount() {
        return successCount;
    }

    public void setSuccessCount(int successCount) {
        this.successCount = successCount;
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

    public int getCurrentAttemptCount() {
        return currentAttemptCount;
    }

    public void setCurrentAttemptCount(int currentAttemptCount) {
        this.currentAttemptCount = currentAttemptCount;
    }

    public int getYesterdayAttemptCount() {
        return yesterdayAttemptCount;
    }

    public void setYesterdayAttemptCount(int yesterdayAttemptCount) {
        this.yesterdayAttemptCount = yesterdayAttemptCount;
    }

    public String getImageId() {
        return imageId;
    }

    public void setImageId(String imageId) {
        this.imageId = imageId;
    }

    public String getOperatingSystem() {
        return operatingSystem;
    }

    public void setOperatingSystem(String operatingSystem) {
        this.operatingSystem = operatingSystem;
    }

    public String getOperatingSystemVersion() {
        return operatingSystemVersion;
    }

    public void setOperatingSystemVersion(String operatingSystemVersion) {
        this.operatingSystemVersion = operatingSystemVersion;
    }

    public boolean isResetTodayFlag() {
        return resetTodayFlag;
    }

    public void setResetTodayFlag(boolean resetTodayFlag) {
        this.resetTodayFlag = resetTodayFlag;
    }

    public LocalDate getLastResetDate() {
        return lastResetDate;
    }

    public void setLastResetDate(LocalDate lastResetDate) {

        this.lastResetDate = lastResetDate;
    }

    public Long getTotalCount() {
        return totalCount;
    }

    public void setTotalCount(Long totalCount) {
        this.totalCount = totalCount;
    }

    public String getDayGap() {
        return dayGap;
    }

    public void setDayGap(String dayGap) {
        this.dayGap = dayGap;
    }

    public int getFailCount() {
        return failCount;
    }

    public void setFailCount(int failCount) {
        this.failCount = failCount;
    }

    public String getNotifyFlag() {
        return notifyFlag;
    }

    public void setNotifyFlag(String notifyFlag) {
        this.notifyFlag = notifyFlag;
    }

    public void incrementAttemptCount() {
        checkAndResetIfNewDay();
        currentAttemptCount++;
    }

    public void checkAndResetIfNewDay() {
        LocalDate today = LocalDate.now();
        // 如果上次重置日期为空，或者上次重置日期在今天之前
        if (lastResetDate == null || lastResetDate.isBefore(today)) {
            yesterdayAttemptCount = currentAttemptCount;
            currentAttemptCount = 0;
            lastResetDate = today;
        }
    }


}
