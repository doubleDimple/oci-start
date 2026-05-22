package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import javax.persistence.Transient;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
* @Description:
* @Param:
* @return:
* @Author: doubleDimple
* @Date: 9/26/25 10:31 PM
*/
@Entity
@Table(name = "tenant_email_config")
@Data
public class TenantEmailConfig {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "tenant_id")
    private Long tenantId;

    @Column(name = "domain_id")
    private String domainId;

    @Column(name = "domain_name")
    private String domainName;

    @Column(name = "sender_id")
    private String senderId;

    //凭据id
    @Column(name = "credential_id")
    private String credentialId;

    @Column(name = "smtp_username")
    private String smtpUsername;

    @Column(name = "smtp_password")
    private String smtpPassword;

    @Column(name = "smtp_host")
    private String smtpHost;

    @Column(name = "smtp_port")
    private String smtpPort;

    @Column(name = "sender_email")
    private String senderEmail;

    @Column(name = "dkim_id")
    private String dkimId;

    @Column(name = "cname_record_value")
    private String cnameRecordValue;

    @Column(name = "active")
    private Boolean active;

    @Column(name = "created_time")
    private LocalDateTime createdTime;

    @Column(name = "daily_email_limit")
    private Long dailyEmailLimit = 200L;

    @Column(name = "today_sent_count")
    private Long todaySentCount = 0L;

    @Column(name = "last_reset_date")
    private LocalDate lastResetDate;

    /**
    * 英文逗号分割的DBS记录ID
    */
    @Column(name = "dbs_record_ids_str")
    private String dbsRecordIdsStr;

    @Transient
    private String tenantName;
}
