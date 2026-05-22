package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName AppVersion
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "tenant_social")
@Slf4j
public class TenantSocial {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    //tenant表的主键id
    private Long tenantId;

    @Column(name = "tenancy")
    private String tenancy;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;

    private String clientId;

    private String clientSecret;

    // OciSocialType枚举的值
    private String socialTypeStr;

    //登录的三方账户地址(一般是邮箱)
    private String thirdLoginAddress;

    //回调地址
    private String redirectUrl;

    //状态,active 激活,inactive 未激活 disabled 禁用
    @Column(name = "social_status")
    private String socialStatus = "active";

}
