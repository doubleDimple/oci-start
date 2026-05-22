package com.doubledimple.ociserver.service.impl;

import cn.hutool.core.util.IdUtil;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.EmailBody;
import com.doubledimple.dao.entity.EmailReceive;
import com.doubledimple.dao.entity.EmailSendRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TenantEmailConfig;
import com.doubledimple.dao.repository.EmailBodyRepository;
import com.doubledimple.dao.repository.EmailReceiveRepository;
import com.doubledimple.dao.repository.EmailSendRecordRepository;
import com.doubledimple.dao.repository.TenantEmailConfigRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.pojo.request.CloudflareConfig;
import com.doubledimple.ociserver.pojo.request.EmailBodyRequest;
import com.doubledimple.ociserver.pojo.request.EmailReceiveAddRequest;
import com.doubledimple.ociserver.pojo.request.EmailReceiveRequest;
import com.doubledimple.ociserver.pojo.request.EmailSendRecordRequest;
import com.doubledimple.ociserver.pojo.request.EmailSendRequest;
import com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.EmailService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.third.dns.CloudflareService;
import com.doubledimple.ociserver.utils.PageUtils;
import com.doubledimple.ociserver.utils.oracle.OciEmailUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.util.StringUtils;

import javax.annotation.Resource;
import javax.persistence.criteria.Predicate;
import java.sql.Array;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName EmailServiceImpl
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-27 09:45
 */
@Service
@Slf4j
public class EmailServiceImpl implements EmailService {

    private static final String SEND_EMAIL_PREFIX = "noreply@";

    @Resource
    EmailReceiveRepository emailReceiveRepository;

    @Resource
    TenantEmailConfigRepository tenantEmailConfigRepository;

    @Resource
    OciEmailUtils ociEmailUtils;

    @Resource
    SystemConfigService systemConfigService;

    @Resource
    CloudflareService cloudflareService;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    EmailSendRecordRepository emailSendRecordRepository;

    @Resource
    EmailBodyRepository emailBodyRepository;

    @Override
    public Page<EmailReceive> listPage(EmailReceiveRequest request) {
        Specification<EmailReceive> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            if (StringUtils.hasText(request.getEmail())) {
                predicates.add(criteriaBuilder.like(root.get("email"), "%" + request.getEmail() + "%"));
            }
            if (StringUtils.hasText(request.getName())) {
                predicates.add(criteriaBuilder.like(root.get("name"), "%" + request.getName() + "%"));
            }
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        return PageUtils.findWithSpec(emailReceiveRepository, request, spec);
    }

    @Override
    public Page<TenantEmailConfig> listTenantEmailConfig(TenantEmailConfigRequest request) {
        Specification<TenantEmailConfig> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            // 查询条件可以在这里添加
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        Page<TenantEmailConfig> page = PageUtils.findWithSpec(tenantEmailConfigRepository, request, spec);
        page.getContent().forEach(config -> {
            if (config.getTenantId() != null) {
                tenantRepository.findById(config.getTenantId()).ifPresent(tenant -> {
                    String name = tenant.getDefName();
                    if (name == null || name.isEmpty()) name = tenant.getTenancyName();
                    if (name == null || name.isEmpty()) name = String.valueOf(tenant.getId());
                    config.setTenantName(name);
                });
            }
        });
        return page;
    }

    @Override
    public Page<EmailBody> emailBodyList(EmailBodyRequest request) {
        Specification<EmailBody> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            // 查询条件可以在这里添加
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        return PageUtils.findWithSpec(emailBodyRepository, request, spec);
    }

    @Override
    public Page<EmailSendRecord> emailSendList(EmailSendRecordRequest request) {
        Specification<EmailSendRecord> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            if (StringUtils.hasText(request.getEmailBodyId())) {
                predicates.add(criteriaBuilder.equal(root.get("emailBodyId"), request.getEmailBodyId()));
            }
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };
        return PageUtils.findWithSpec(emailSendRecordRepository, request, spec);
    }

    /**
    * @Description: 批量删除邮箱主体发送记录
    * @Param: []
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/28/25 2:54 PM
    */
    @Override
    @Transactional
    public void deleteEmailBody() {
        emailBodyRepository.deleteAll();
        emailSendRecordRepository.deleteAll();
    }

    @Override
    @Transactional
    public void deleteEmailBody(EmailBodyRequest request) {
        Optional<EmailBody> byId = emailBodyRepository.findById(request.getId());
        if (byId.isPresent()){
            EmailBody emailBody = byId.get();
            //删除主体邮件的发送记录
            emailSendRecordRepository.deleteByEmailBodyId(emailBody.getEmailBodyId());
            //删除主体
            emailBodyRepository.delete(emailBody);
        }
    }

    /**
    * @Description: 禁用邮件服务
    * @Param: [com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/28/25 4:42 PM
    */
    @Override
    @Transactional
    public void disableEmailForTenant(TenantEmailConfigRequest request) {
        long id = request.getId();
        Optional<TenantEmailConfig> byId = tenantEmailConfigRepository.findById(id);
        if (!byId.isPresent()){
            throw new IllegalArgumentException("租户邮件配置不存在");
        }
        TenantEmailConfig tenantEmailConfig = byId.get();
        Optional<Tenant> tenantOptional = tenantRepository.findById(tenantEmailConfig.getTenantId());
        if (!tenantOptional.isPresent()){
            throw new IllegalArgumentException("租户不存在");
        }
        Tenant tenant = tenantOptional.get();
        ociEmailUtils.deleteOciEmail(tenant,tenantEmailConfig);

        //删除cf下的dns记录
        CloudflareConfig cloudflareConfig = systemConfigService.getCloudflareConfig();
        if (cloudflareConfig != null && cloudflareConfig.isEnabled()){
            try {
                String dbsRecordIdsStr = tenantEmailConfig.getDbsRecordIdsStr();
                if (StringUtils.hasText(dbsRecordIdsStr)){
                    String[] dbsRecordIds = dbsRecordIdsStr.split(",");
                    for (String dbsRecordId : dbsRecordIds) {
                        cloudflareService.deleteDnsRecord(dbsRecordId);
                    }
                }
            } catch (Exception e) {
                log.warn("删除DNS记录失败: {}", e.getMessage());
            }
        }

        //修改租户的邮件服务状态
        tenant.setEmailEnable(0);
        tenantRepository.save(tenant);
        tenantEmailConfigRepository.delete(tenantEmailConfig);
        List<EmailBody> emailBodyList = emailBodyRepository.findByTenantEmailConfigId(tenantEmailConfig.getId());
        if (!CollectionUtils.isEmpty(emailBodyList)){
            emailBodyList.forEach(emailBody -> emailSendRecordRepository.deleteByEmailBodyId(emailBody.getEmailBodyId()));
            emailBodyRepository.deleteByTenantEmailConfigId(tenantEmailConfig.getId());
        }
    }

    @Override
    @Transactional
    public void deleteEmailConfig(Long tenantId) {
        try {
            List<TenantEmailConfig> byTenantId = tenantEmailConfigRepository.findByTenantId(tenantId);
            if (!CollectionUtils.isEmpty(byTenantId)){
                tenantEmailConfigRepository.deleteAll(byTenantId);
            }
        } catch (Exception e) {
            log.warn("删除邮件配置失败: {}", e.getMessage());
        }
    }

    @Override
    public List<TenantEmailConfig> getTenantEmailConfig(String tenantId) {
        List<TenantEmailConfig> list = tenantEmailConfigRepository.findByTenantId(Long.valueOf(tenantId));
        return list;
    }

    @Override
    public TenantEmailConfig getTenantEmailConfigByName(String domainName) {
        return tenantEmailConfigRepository.findByDomainName(domainName).orElse( null);
    }

    @Override
    @Transactional
    public void update(Tenant tenant, TenantEmailConfig tenantEmailConfig) {
        tenantEmailConfig.setTenantId(tenant.getId());
        tenantEmailConfigRepository.save(tenantEmailConfig);
    }


    @Override
    @Transactional
    public ApiResponse enableEmailForTenant(Tenant tenant, String emailDomainName,long tenantId) {
        //检查是否配置了cf
        CloudflareConfig cloudflareConfig = systemConfigService.getCloudflareConfig();
        if (cloudflareConfig == null){
            log.error("请先配置Cloudflare");
            return ApiResponse.error("请先配置Cloudflare");
        }
        if (!cloudflareConfig.isEnabled()){
            log.error("Cloudflare已被禁用,请先使用");
            return ApiResponse.error("Cloudflare已被禁用,请先使用");
        }

        Optional<TenantEmailConfig> byDomainName = tenantEmailConfigRepository.findByDomainName(emailDomainName);
        if (byDomainName.isPresent()){
            //删除
            tenantEmailConfigRepository.delete(byDomainName.get());
        }

        //第一步:创建域名邮件
        ApiResponse emailDomainRes = ociEmailUtils.createEmailDomain(tenant, emailDomainName);
        if (!emailDomainRes.isSuccess()) {
            return emailDomainRes;
        }
        OciEmailUtils.EmailDomainResult emailDomainResult = (OciEmailUtils.EmailDomainResult) emailDomainRes.getData();
        log.info("创建域名邮件成功: {}", JSON.toJSONString(emailDomainResult));

        //第二步:创建发送人
        String defaultSenderEmail = SEND_EMAIL_PREFIX + emailDomainName;
        ApiResponse senderRes = ociEmailUtils.createSender(tenant, defaultSenderEmail);
        if (!senderRes.isSuccess()) {
            return senderRes;
        }
        OciEmailUtils.SenderCreationResult senderCreationResult = (OciEmailUtils.SenderCreationResult) senderRes.getData();
        log.info("创建发送人成功: {}", JSON.toJSONString(senderCreationResult));

        //第三步:添加dkim记录
        ApiResponse dkim = ociEmailUtils.createDkim(tenant, emailDomainResult.getDomainId());
        if (!dkim.isSuccess()) {
            return dkim;
        }
        OciEmailUtils.DkimResult dkimResult = (OciEmailUtils.DkimResult) dkim.getData();
        log.info("添加DKIM记录成功: {}", JSON.toJSONString(dkimResult));

        //第四步:创建SMTP凭据
        ApiResponse smtpCredentialsRes = ociEmailUtils.generateSmtpCredentialsForCurrentUser(tenant, "Email credentials for tenant " + tenantId);
        if (!smtpCredentialsRes.isSuccess()) {
            return smtpCredentialsRes;
        }
        OciEmailUtils.SmtpCredentialsResult smtpResult = (OciEmailUtils.SmtpCredentialsResult) smtpCredentialsRes.getData();
        log.info("创建SMTP凭据成功: {}", JSON.toJSONString(smtpResult));

        // 第五步. 获取邮件配置
        String smtpHost = "smtp.email." + RegionEnum.getRegionCode(tenant.getRegion()) + ".oci.oraclecloud.com";


        // 第六步: 保存SMTP配置到数据库
        TenantEmailConfig config = new TenantEmailConfig();
        config.setTenantId(tenantId);
        config.setCredentialId(smtpResult.getCredentialId());
        config.setDomainId(emailDomainResult.getDomainId());
        config.setDomainName(emailDomainName);
        config.setSenderId(senderCreationResult.getSenderId());
        config.setSmtpUsername(smtpResult.getSmtpUsername());
        config.setDkimId(dkimResult.getDkimId());
        config.setCnameRecordValue(dkimResult.getCnameRecordValue());
        config.setSmtpPassword(smtpResult.getSmtpPassword());
        config.setSmtpHost(extractHostFromEndpoint(smtpHost));
        config.setSmtpPort("587");
        config.setSenderEmail(defaultSenderEmail);
        config.setCredentialId(smtpResult.getCredentialId());
        config.setActive(true);
        config.setCreatedTime(LocalDateTime.now());
        ApiResponse apiResponse = cloudflareService.addOracleEmailDnsRecords(emailDomainName, config);
        if (apiResponse.isSuccess()){
            Map<String, Object> data = (Map<String, Object>) apiResponse.getData();
            List<String> addedRecords = (List<String>) data.get("addedRecords");
            config.setDbsRecordIdsStr(String.join(",", addedRecords));
        }
        tenantEmailConfigRepository.save(config);
        return ApiResponse.success();
    }

    /**
    * @Description: send
    * @Param: [com.doubledimple.ociserver.pojo.request.EmailSendRequest]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/28/25 10:30 AM
    */
    @Override
    public void send(EmailSendRequest request) {
        Long tenantEmailConfigId = request.getTenantEmailConfigId();
        String title = request.getTitle();
        String content = request.getContent();
        List<Long> emailReceiveIds = request.getEmailReceiveIds();
        String emailBodyId = IdUtil.getSnowflakeNextIdStr();
        //查询租户是否存在
        //第一步:查询邮件配置
        Optional<TenantEmailConfig> byId = tenantEmailConfigRepository.findById(tenantEmailConfigId);
        if (!byId.isPresent()){
            throw new RuntimeException("邮件配置不存在");
        }
        TenantEmailConfig tenantEmailConfig = byId.get();
        Long tenantId = tenantEmailConfig.getTenantId();
        Optional<Tenant> tenantOptional = tenantRepository.findById(tenantId);
        if (!tenantOptional.isPresent()){
            throw new RuntimeException("租户不存在");
        }
        Tenant tenant = tenantOptional.get();
        //第二步:查询具体的收件人
        List<EmailReceive> emailReceiveList = emailReceiveRepository.findAllById(emailReceiveIds);
        if (CollectionUtils.isEmpty(emailReceiveList)){
            throw new RuntimeException("收件人不存在");
        }

        //保存邮件主体和邮件发送记录
        EmailBody emailBody = new EmailBody();
        emailBody.setSenderEmail(tenantEmailConfig.getSenderEmail());
        emailBody.setEmailBodyId(emailBodyId);
        emailBody.setTitle(title);
        emailBody.setContent(content);
        emailBody.setReceiveTotal((long) emailReceiveIds.size());
        emailBody.setReceiveSuccessTotal(0L);
        emailBody.setReceiveFailTotal(0L);
        emailBody.setTenantId(tenantId);
        emailBody.setTenantName(tenant.getUserName());
        emailBody.setCreateTime(LocalDateTime.now());
        emailBody.setTenantEmailConfigId(tenantEmailConfigId);
        emailBodyRepository.save(emailBody);

        //保存邮件发送记录
        List<EmailSendRecord> recordAddList = new ArrayList<>();
        for (EmailReceive emailReceive : emailReceiveList) {
            EmailSendRecord emailSendRecord = new EmailSendRecord();
            emailSendRecord.setEmailSendRecordId(IdUtil.getSnowflakeNextIdStr());
            emailSendRecord.setSendState(0);
            emailSendRecord.setEmailBodyId(emailBodyId);
            emailSendRecord.setTenantId(tenantId);
            emailSendRecord.setTenantName(tenant.getUserName());
            emailSendRecord.setEmailReceiveId(emailReceive.getId());
            emailSendRecord.setCreateTime(LocalDateTime.now());
            emailSendRecord.setEmailSendAddress(tenantEmailConfig.getSenderEmail());
            emailSendRecord.setReceiveEmailAddress(emailReceive.getEmail());
            recordAddList.add(emailSendRecord);
        }
        emailSendRecordRepository.saveAll(recordAddList);

        //发送邮件并更新邮件结果
        sendEmailAndRefresh(emailBodyId,tenant,tenantEmailConfig,recordAddList,title,content);

    }

    private void sendEmailAndRefresh(String emailBodyId,Tenant tenant,TenantEmailConfig tenantEmailConfig, List<EmailSendRecord> recordAddList, String title, String content) {
        Long sendSuccessTotal = 0L;
        Long sendFailTotal = 0L;
        Long todaySentCount = tenantEmailConfig.getTodaySentCount();
        //第二步:发送邮件(获取发送结果)
        ApiResponse apiResponse = ociEmailUtils.sendEmailsParallel(tenantEmailConfig.getSmtpHost(),
                Integer.parseInt(tenantEmailConfig.getSmtpPort()),
                tenantEmailConfig.getSmtpUsername(),
                tenantEmailConfig.getSmtpPassword(),
                tenantEmailConfig.getSenderEmail(),
                tenantEmailConfig.getSenderEmail(),
                recordAddList, title, content);
        if (!apiResponse.isSuccess()){
            throw new RuntimeException("邮件发送失败");
        }
        //第三步:保存邮件发送记录
        List<OciEmailUtils.EmailResult> emailSendResult = (List<OciEmailUtils.EmailResult>) apiResponse.getData();
        List<EmailSendRecord> emailSendRecordUpdate = new ArrayList<>();
        for (OciEmailUtils.EmailResult emailResult : emailSendResult) {
            //record的记录id
            String emailSendRecordId = emailResult.getGetEmailSendRecordId();
            EmailSendRecord emailSendRecord = emailSendRecordRepository.findByEmailSendRecordId(emailSendRecordId);
            if (emailSendRecord != null){
                boolean success = emailResult.isSuccess();
                if ( success){
                    sendSuccessTotal++;
                    emailSendRecord.setSendState(1);
                }else {
                    sendFailTotal++;
                }
                emailSendRecord.setEmailBodyId(emailBodyId);
                emailSendRecord.setTenantId(tenant.getId());
                emailSendRecord.setTenantName(tenant.getUserName());
                emailSendRecord.setEmailReceiveId(emailSendRecord.getEmailReceiveId());
                emailSendRecord.setCreateTime(LocalDateTime.now());
                emailSendRecord.setEmailSendAddress(tenantEmailConfig.getSenderEmail());
                emailSendRecord.setReceiveEmailAddress(emailResult.getEmail());
                emailSendRecordUpdate.add(emailSendRecord);
            }
        }
        emailSendRecordRepository.saveAll(emailSendRecordUpdate);

        //第五步:更新邮件配置
        LocalDate now = LocalDate.now();
        LocalDate lastResetDate = tenantEmailConfig.getLastResetDate();
        if (lastResetDate == null || now.isAfter(lastResetDate)) {
            tenantEmailConfig.setTodaySentCount(sendSuccessTotal);
        } else {
            tenantEmailConfig.setTodaySentCount(todaySentCount + sendSuccessTotal);
        }
        tenantEmailConfig.setLastResetDate(now);
        tenantEmailConfigRepository.save(tenantEmailConfig);

        //更新邮件主体
        EmailBody byEmailBodyId = emailBodyRepository.findByEmailBodyId(emailBodyId);
        if (byEmailBodyId != null){
            byEmailBodyId.setReceiveSuccessTotal(byEmailBodyId.getReceiveSuccessTotal() + sendSuccessTotal);
            byEmailBodyId.setReceiveFailTotal(byEmailBodyId.getReceiveFailTotal() + sendFailTotal);
            emailBodyRepository.save(byEmailBodyId);
        }
    }

    @Override
    @Transactional
    public EmailReceive addReceive(EmailReceiveAddRequest request) {
        // 检查邮箱是否已存在
        if (emailReceiveRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("邮箱地址已存在");
        }

        EmailReceive emailReceive = new EmailReceive();
        emailReceive.setEmail(request.getEmail());
        emailReceive.setName(request.getName());
        emailReceive.setCreateTime(LocalDateTime.now());
        emailReceive.setUpdateTime(LocalDateTime.now());

        return emailReceiveRepository.save(emailReceive);
    }

    @Override
    @Transactional
    public void deleteReceive(Long id) {
        if (!emailReceiveRepository.existsById(id)) {
            throw new RuntimeException("收件人不存在");
        }
        emailReceiveRepository.deleteById(id);
    }

    @Override
    public EmailReceive getById(Long id) {
        return emailReceiveRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("收件人不存在"));
    }

    private String extractHostFromEndpoint(String endpoint) {
        if (endpoint == null || endpoint.isEmpty()) {
            return "";
        }
        String host = endpoint.replaceFirst("^https?://", "");
        int colonIndex = host.indexOf(':');
        if (colonIndex > 0) {
            host = host.substring(0, colonIndex);
        }
        return host;
    }
}
