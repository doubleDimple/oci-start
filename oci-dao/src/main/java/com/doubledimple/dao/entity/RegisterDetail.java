package com.doubledimple.dao.entity;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import com.oracle.bmc.ospgateway.model.Subscription;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;
import java.util.Date;

/**
 * @version 1.0.0
 * @ClassName AppVersion
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 10:51
 */
@Data
@Entity
@Table(name = "register_detail")
@Slf4j
public class RegisterDetail {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    //tenant表的业务主键 id
    @Column(name = "tenant_prv_id")
    private Long tenantPrvId;


    @Column(name = "tenant_id")
    private String tenantId;

    // 从Subscription中添加的字段

    /**
     * 账号类型 - 对应AccountType枚举
     */
    @Column(name = "account_type")
    private Subscription.AccountType accountType;

    /**
     * 计划类型 - 对应PlanType枚举
     */
    @Column(name = "plan_type")
    private Subscription.PlanType planType;

    /**
     * 注册时间 - 对应timeStart
     */
    @Column(name = "register_time")
    private Date registerTime;

    /**
     * 注册地址 - 对应billingAddress的完整地址信息
     */
    @Column(name = "city")
    private String city;

    @Column(name = "country")
    private String country;

    /**
     *
     */
    @Column(name = "email_address", length = 1000)
    private String emailAddress;

    /**
     *
     */
    @Column(name = "first_name", length = 1000)
    private String firstName;

    /**
     *
     */
    @Column(name = "last_name", length = 1000)
    private String lastName;

    /**
     *
     */
    @Column(name = "line1", length = 1000)
    private String line1;

    /**
     * 邮编
     */
    @Column(name = "postalCode")
    private String postalCode;

    /**
     * 订阅编号
     */
    @Column(name = "subscriptionPlanNumber")
    private String subscriptionPlanNumber;

    /**
     * upgradeState
     */
    @Column(name = "upgrade_state")
    private String upgradeState;

    /**
     * 创建时间
     */
    @Column(name = "created_time")
    private LocalDateTime createdTime;

    /**
     * 更新时间
     */
    @Column(name = "updated_time")
    private LocalDateTime updatedTime;

    /**
     * 云厂商类型
     * @see com.doubledimple.ocicommon.enums.CloudTypeEnum
     */
    @Column(name = "cloud_type", columnDefinition = "INTEGER DEFAULT 1")
    private int cloudType = 1;
}
