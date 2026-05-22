package com.doubledimple.dao.entity;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIdentityInfo;
import com.fasterxml.jackson.annotation.ObjectIdGenerators;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;
import javax.persistence.Transient;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * @author doubleDimple
 * @date 2024:10:07日 13:50
 */
@JsonIdentityInfo(
        generator = ObjectIdGenerators.PropertyGenerator.class,
        property = "id")
@Entity
@Table(name = "tenant")
@Slf4j
public class Tenant {

    @Id
    //@GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String tenantId;
    private String userName;
    private String fingerprint;
    private String tenancy;
    private String region;
    private String keyFile;
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;

    private Boolean apiSynced;

    /**
    * 是否开启icmp协议 true表示开启,false表示未开启
    */
    private Boolean enableIcmp = false;

    private Boolean enableAllProtocol = false;

    /**
    * 是否主区域 true表示是,false表示不是
    */
    private Boolean isHomeRegion = true;

    /**
    * 父级id
    */
    private Long parenId;

    /**
    * 租户名
    */
    @Column(columnDefinition = "")
    private String tenancyName;

    /**
     * 租户描述
     */
    @Column(columnDefinition = "")
    private String tenancyDes;

    // 非持久化字段,用于前端显示
    @Transient
    private Boolean hasChildren;

    private String accountType;

    @Transient
    private String accountTypeName;

    // 0:不支持,1:支持
    @Transient
    private Integer supportAI = 0;

    @Transient
    private List<Tenant> children;  // 新增字段存储子记录

    //临时绝对路径
    @Transient
    private String tmpKeyFile;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    /**
    * region英文
    */
    private String regionEn;

    private String idStr;

    private String emailAddress;

    //oci邮箱启用 0: 未启用,1:启用
    private int emailEnable = 0;

    /**
     * 转移状态 0:未转移, 1:已转移
     */
    @Column(name = "transfer_status", columnDefinition = "INTEGER DEFAULT 0")
    private int transferStatus = 0;

    /**
     * 转移金额
     */
    private String transferAmount;

    /**
     * 账号是否有效: true表示有效, false表示失效
     */
    @Column(name = "is_active", columnDefinition = "BOOLEAN DEFAULT TRUE")
    private Boolean isActive = true;

    /**
     * 1:有抢机任务,2无抢机任务
     */
    @Transient
    private String openInsFlag = "2";

    @Transient
    private RegisterDetail registerDetail;

    @Transient
    private String defName;

    @Transient
    private String accountCost;

    @Transient
    private Boolean openBootFlag =  Boolean.FALSE;

    @Transient
    private String activeDays;

    public Tenant() {
        this.createdAt = LocalDateTime.now();
    }


    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public String getUserName() {
        return userName;
    }

    public void setUserName(String userName) {
        this.userName = userName;
    }

    public String getFingerprint() {
        return fingerprint;
    }

    public void setFingerprint(String fingerprint) {
        this.fingerprint = fingerprint;
    }

    public String getTenancy() {
        return tenancy;
    }

    public void setTenancy(String tenancy) {
        this.tenancy = tenancy;
    }

    public String getRegion() {
        return region;
    }

    public void setRegion(String region) {
        /*String codeByName = RegionEnum.getCodeByName(region);*/
        this.region = region;
    }

    public String getKeyFile() {
        return keyFile;
    }

    public void setKeyFile(String keyFile) {
        this.keyFile = keyFile;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public Boolean getApiSynced() {
        return apiSynced;
    }

    public void setApiSynced(Boolean apiSynced) {
        this.apiSynced = apiSynced;
    }

    public LocalDateTime getCreatedAt() {
        return this.createdAt;
    }

    public String getCreatedAtStr() {
        if (createdAt == null) return "";
        return createdAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"));
    }

    public Boolean getEnableIcmp() {
        return enableIcmp != null ? enableIcmp : false;
    }

    public void setEnableIcmp(Boolean enableIcmp) {
        this.enableIcmp = enableIcmp;
    }

    public Boolean getIsHomeRegion() {
        return isHomeRegion != null ? isHomeRegion : false;
    }

    public void setIsHomeRegion(Boolean isHomeRegion) {
        this.isHomeRegion = isHomeRegion;
    }

    public Long getParenId() {
        return parenId;
    }

    public void setParenId(Long parenId) {
        this.parenId = parenId;
    }

    public Boolean getHasChildren() {
        return hasChildren;
    }

    public void setHasChildren(Boolean hasChildren) {
        this.hasChildren = hasChildren;
    }

    public List<Tenant> getChildren() {
        return children;
    }

    public void setChildren(List<Tenant> children) {
        this.children = children;
    }

    public String getTenancyName() {
        return tenancyName;
    }

    public void setTenancyName(String tenancyName) {
        this.tenancyName = tenancyName;
    }

    public String getTenancyDes() {
        return tenancyDes;
    }

    public void setTenancyDes(String tenancyDes) {
        this.tenancyDes = tenancyDes;
    }

    public String getAccountType() {
        return accountType;
    }

    public void setAccountType(String accountType) {
        this.accountType = accountType;
    }

    public Boolean getEnableAllProtocol() {
        return enableAllProtocol;
    }

    public void setEnableAllProtocol(Boolean enableAllProtocol) {

        this.enableAllProtocol = enableAllProtocol;
    }

    public String getOpenInsFlag() {
        return openInsFlag;
    }

    public void setOpenInsFlag(String openInsFlag) {

        this.openInsFlag = openInsFlag;
    }

    public RegisterDetail getRegisterDetail() {
        return registerDetail;
    }
    public void setRegisterDetail(RegisterDetail registerDetail) {

        this.registerDetail = registerDetail;
    }

    public String getAccountTypeName() {
        return accountTypeName;
    }
    public void setAccountTypeName(String accountTypeName) {


        this.accountTypeName = accountTypeName;
    }

    public String getRegionEn() {
        return regionEn;
    }
    public void setRegionEn(String regionEn) {
        this.regionEn = regionEn;
    }
    public int getCloudType() {
        return cloudType;
    }
    public void setCloudType(int cloudType) {
        this.cloudType = cloudType;
    }

    public String getIdStr() {
        return idStr;
    }
    public void setIdStr(String idStr) {
        this.idStr = idStr;
    }

    public String getTmpKeyFile() {
        return tmpKeyFile;
    }

    public void setTmpKeyFile(String tmpKeyFile) {
        this.tmpKeyFile = tmpKeyFile;
    }

    public String getEmailAddress() {
        return emailAddress;
    }
    public void setEmailAddress(String emailAddress) {


        this.emailAddress = emailAddress;
    }

    public String getDefName() {
        return defName;
    }

    public void setDefName(String defName) {
        this.defName = defName;
    }

    public Integer getSupportAI() {
        return supportAI;
    }

    public void setSupportAI(Integer supportAI) {
        this.supportAI = supportAI;
    }

    public int getEmailEnable() {
        return emailEnable;
    }

    public void setEmailEnable(int emailEnable) {
        this.emailEnable = emailEnable;
    }

    public Boolean getOpenBootFlag() {
        return openBootFlag;
    }

    public void setOpenBootFlag(Boolean openBootFlag) {
        this.openBootFlag = openBootFlag;
    }

    public String getAccountCost() {
        return accountCost;
    }

    public void setAccountCost(String accountCost) {
        this.accountCost = accountCost;
    }

    public String getActiveDays() {
        return activeDays;
    }

    public void setActiveDays(String activeDays) {
        this.activeDays = activeDays;
    }

    public int getTransferStatus() {
        return transferStatus;
    }

    public void setTransferStatus(int transferStatus) {
        this.transferStatus = transferStatus;
    }

    public String getTransferAmount() {
        return transferAmount;
    }

    public void setTransferAmount(String transferAmount) {
        this.transferAmount = transferAmount;
    }

    public Boolean getActive() {
        return isActive;
    }

    public void setActive(Boolean active) {
        isActive = active;
    }
}
