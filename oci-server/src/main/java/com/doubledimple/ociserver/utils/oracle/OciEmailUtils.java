package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.EmailReceive;
import com.doubledimple.dao.entity.EmailSendRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TenantEmailConfig;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.email.EmailClient;
import com.oracle.bmc.email.model.*;
import com.oracle.bmc.email.requests.*;
import com.oracle.bmc.email.responses.*;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.CreateSmtpCredentialDetails;
import com.oracle.bmc.identity.model.SmtpCredential;
import com.oracle.bmc.identity.requests.CreateSmtpCredentialRequest;
import com.oracle.bmc.identity.requests.DeleteSmtpCredentialRequest;
import com.oracle.bmc.identity.responses.CreateSmtpCredentialResponse;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import javax.mail.Authenticator;
import javax.mail.Message;
import javax.mail.PasswordAuthentication;
import javax.mail.Session;
import javax.mail.Transport;
import javax.mail.internet.InternetAddress;
import javax.mail.internet.MimeMessage;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * Oracle Cloud Email Service 工具类
 *
 * @author doubleDimple
 * @date 2025:09:27
 */
@Slf4j
@Component
public class OciEmailUtils {

    @Resource
    @Qualifier("taskExecutor")
    private ThreadPoolExecutor taskExecutor;

    /**
     * 步骤1: 创建电子邮件域
     * 对应OCI控制台: Developer Services → Email Delivery → Email Domains → Create Email Domain
     */
    public ApiResponse createEmailDomain(Tenant tenant, String domainName) {
        EmailDomainResult emailDomainResult = new EmailDomainResult();
        //先查询是否存在
        EmailDomain emailDomainByName = findEmailDomainByName(tenant, domainName);
        if (emailDomainByName != null){
            emailDomainResult.setDomainId(emailDomainByName.getId());
            emailDomainResult.setDomainId(emailDomainByName.getId());
            emailDomainResult.setDomainName(emailDomainByName.getName());
            emailDomainResult.setStatus(emailDomainByName.getLifecycleState().getValue());
            return ApiResponse.success(emailDomainResult);
        }
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try(EmailClient emailClient = EmailClient.builder().build(provider);) {

            CreateEmailDomainDetails domainDetails = CreateEmailDomainDetails.builder()
                    .compartmentId(compartmentId)
                    .name(domainName)
                    .build();

            CreateEmailDomainRequest request = CreateEmailDomainRequest.builder()
                    .createEmailDomainDetails(domainDetails)
                    .build();

            CreateEmailDomainResponse response = emailClient.createEmailDomain(request);
            EmailDomain domain = response.getEmailDomain();
            emailDomainResult.setDomainId(domain.getId());
            emailDomainResult.setDomainName(domain.getName());
            emailDomainResult.setStatus(domain.getLifecycleState().getValue());
            emailDomainResult.setMessage("域名创建成功，请按照验证要求在DNS中添加验证记录");
            return ApiResponse.success(emailDomainResult);

        } catch (Exception e) {
            log.error("创建电子邮件域失败: {}", domainName, e);
            return ApiResponse.error("创建电子邮件域失败: " + e.getMessage());
        }
    }

    /**
     * 创建发件人
     *
     * @param emailAddress 邮箱地址
     * @return 创建结果
     */
    public ApiResponse createSender(Tenant tenant, String emailAddress) {
        SenderCreationResult result = new SenderCreationResult();
        //先查询发件人是否存在,存在则返回
        Sender senderByEmail = findSenderByEmail(tenant, emailAddress);
        if (senderByEmail != null){
            result.setSenderId(senderByEmail.getId());
            result.setSenderAddress(senderByEmail.getEmailAddress());
            result.setState(senderByEmail.getLifecycleState().getValue());
            return ApiResponse.success(result);
        }
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (EmailClient emailClient = EmailClient.builder().build(provider)) {
            CreateSenderDetails createSenderDetails = CreateSenderDetails.builder()
                    .compartmentId(compartmentId)
                    .emailAddress(emailAddress)
                    .build();
            CreateSenderRequest createSenderRequest = CreateSenderRequest.builder()
                    .createSenderDetails(createSenderDetails)
                    .build();

            CreateSenderResponse response = emailClient.createSender(createSenderRequest);
            Sender sender = response.getSender();

            result.setSenderId(sender.getId());
            result.setSenderAddress(sender.getEmailAddress());
            result.setState(sender.getLifecycleState().getValue());
            log.info("发件人创建成功，ID: {}, 地址: {}", result.getSenderId(), result.getSenderAddress());
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("创建发件人时发生异常: {}", e.getMessage(), e);
            return ApiResponse.error("创建发件人失败: " + e.getMessage());
        }
    }

    /**
     * 步骤3: 配置DKIM（可选）
     * 对应OCI控制台: Email Domains → 选择域名 → DKIM → Generate DKIM
     */
    public ApiResponse createDkim(Tenant tenant, String emailDomainId) {
        DkimResult dkimResult = new DkimResult();

        // 先查询DKIM是否已存在
        Dkim existingDkim = findDkimByDomainId(tenant, emailDomainId);
        if (existingDkim != null) {
            dkimResult.setDkimId(existingDkim.getId());
            dkimResult.setCnameRecordValue(existingDkim.getCnameRecordValue());
            dkimResult.setStatus(existingDkim.getLifecycleState().getValue());
            dkimResult.setMessage("DKIM已存在，状态: " + existingDkim.getLifecycleState().getValue());
            return ApiResponse.success(dkimResult);
        }

        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try(EmailClient emailClient = EmailClient.builder().build(provider);) {

            CreateDkimDetails dkimDetails = CreateDkimDetails.builder()
                    .emailDomainId(emailDomainId)
                    .build();

            CreateDkimRequest request = CreateDkimRequest.builder()
                    .createDkimDetails(dkimDetails)
                    .build();

            CreateDkimResponse response = emailClient.createDkim(request);
            Dkim dkim = response.getDkim();

            dkimResult.setDkimId(dkim.getId());
            dkimResult.setCnameRecordValue(dkim.getCnameRecordValue());
            dkimResult.setStatus(dkim.getLifecycleState().getValue());
            dkimResult.setMessage("DKIM创建成功，请在DNS中添加CNAME记录");

            log.info("DKIM创建成功，ID: {}, CNAME记录: {}", dkim.getId(), dkim.getCnameRecordValue());
            return ApiResponse.success(dkimResult);

        } catch (Exception e) {
            log.error("创建DKIM失败: {}", emailDomainId, e);
            return ApiResponse.error("创建DKIM失败: " + e.getMessage());
        }
    }

    /**
     * 根据域名ID查询DKIM是否存在
     */
    public static Dkim findDkimByDomainId(Tenant tenant, String emailDomainId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try(EmailClient emailClient = EmailClient.builder().build(provider);) {

            ListDkimsRequest listRequest = ListDkimsRequest.builder()
                    .emailDomainId(emailDomainId)
                    .build();

            ListDkimsResponse listResponse = emailClient.listDkims(listRequest);
            List<DkimSummary> dkims = listResponse.getDkimCollection().getItems();

            if (dkims != null && !dkims.isEmpty()) {
                // 找到匹配的DKIM，获取详细信息
                String dkimId = dkims.get(0).getId();
                GetDkimRequest getRequest = GetDkimRequest.builder()
                        .dkimId(dkimId)
                        .build();

                GetDkimResponse getResponse = emailClient.getDkim(getRequest);
                return getResponse.getDkim();
            }

            return null;

        } catch (Exception e) {
            log.warn("查询DKIM失败: {}", emailDomainId, e);
            return null;
        }
    }

    /**
     * 查询域名下的所有DKIM记录
     */
    public ApiResponse listDkims(Tenant tenant, String emailDomainId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try(EmailClient emailClient = EmailClient.builder().build(provider);) {
            ListDkimsRequest listRequest = ListDkimsRequest.builder()
                    .emailDomainId(emailDomainId)
                    .build();

            ListDkimsResponse listResponse = emailClient.listDkims(listRequest);
            List<DkimSummary> dkims = listResponse.getDkimCollection().getItems();

            log.info("查询到 {} 个DKIM记录", dkims.size());
            return ApiResponse.success(dkims);

        } catch (Exception e) {
            log.error("查询DKIM列表失败: {}", emailDomainId, e);
            return ApiResponse.error("查询DKIM列表失败: " + e.getMessage());
        }
    }


    /**
     * 为当前用户生成SMTP凭据
     *
     * @param tenant 认证提供者
     * @param description SMTP凭据描述
     * @return SMTP凭据信息
     */
    public ApiResponse generateSmtpCredentialsForCurrentUser(Tenant tenant, String description) {
        return generateSmtpCredentials(tenant, description);
    }

    /**
     * 为指定用户生成SMTP凭据
     *
     * @param description SMTP凭据描述
     * @return SMTP凭据信息
     */
    public ApiResponse generateSmtpCredentials(Tenant tenant, String description) {
        SmtpCredentialsResult result = new SmtpCredentialsResult();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String userId = provider.getUserId();
        // 使用 IdentityClient 创建SMTP凭据
        try (IdentityClient identityClient = IdentityClient.builder().build(provider)) {
            CreateSmtpCredentialDetails createDetails = CreateSmtpCredentialDetails.builder()
                    .description(description)
                    .build();

            CreateSmtpCredentialRequest request = CreateSmtpCredentialRequest.builder()
                    .userId(userId)
                    .createSmtpCredentialDetails(createDetails)
                    .build();

            CreateSmtpCredentialResponse response =
                    identityClient.createSmtpCredential(request);

            SmtpCredential credential = response.getSmtpCredential();

            result.setSmtpUsername(credential.getUsername());
            result.setSmtpPassword(credential.getPassword());
            result.setCredentialId(credential.getId());
            log.info("SMTP凭据创建成功，用户名: {}, ID: {}",
                    credential.getUsername(), credential.getId());
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("生成SMTP凭据时发生异常: {}", e.getMessage(), e);
            return ApiResponse.error("生成SMTP凭据失败: " + e.getMessage());
        }
    }

    /**
     * 步骤5: 发送邮件
     */
    public ApiResponse sendEmail(String smtpHost, int smtpPort,
                                 String smtpUsername, String smtpPassword,
                                 String senderEmail, String senderName,
                                 List<String> recipients, String subject, String content) {
        try {
            Properties props = new Properties();
            props.put("mail.smtp.host", smtpHost);
            props.put("mail.smtp.port", smtpPort);
            props.put("mail.smtp.auth", "true");
            props.put("mail.smtp.starttls.enable", "true");

            Session session = Session.getInstance(props, new Authenticator() {
                protected PasswordAuthentication getPasswordAuthentication() {
                    return new PasswordAuthentication(smtpUsername, smtpPassword);
                }
            });

            MimeMessage message = new MimeMessage(session);
            message.setFrom(new InternetAddress(senderEmail, senderName));

            // 添加收件人
            for (String recipient : recipients) {
                message.addRecipient(Message.RecipientType.TO, new InternetAddress(recipient));
            }

            message.setSubject(subject, "UTF-8");
            message.setText(content, "UTF-8");

            Transport.send(message);

            return ApiResponse.success("邮件发送成功");

        } catch (Exception e) {
            log.error("发送邮件失败", e);
            return ApiResponse.error("发送邮件失败: " + e.getMessage());
        }
    }

    /**
     * 并行发送邮件，返回每个邮件的发送结果
     */
    public ApiResponse sendEmailsParallel(String smtpHost, int smtpPort,
                                          String smtpUsername, String smtpPassword,
                                          String senderEmail, String senderName,
                                          List<EmailSendRecord> recordAddList, String subject, String content) {

        if (recordAddList == null || recordAddList.isEmpty()) {
            return ApiResponse.error("收件人列表不能为空");
        }

        try {
            Properties props = new Properties();
            props.put("mail.smtp.host", smtpHost);
            props.put("mail.smtp.port", smtpPort);
            props.put("mail.smtp.auth", "true");
            props.put("mail.smtp.starttls.enable", "true");

            List<CompletableFuture<EmailResult>> futures = new ArrayList<>();

            // 为每个收件人创建异步任务
            for (EmailSendRecord recipient : recordAddList) {
                CompletableFuture<EmailResult> future = CompletableFuture.supplyAsync(() -> {
                    try {
                        Session session = Session.getInstance(props, new Authenticator() {
                            protected PasswordAuthentication getPasswordAuthentication() {
                                return new PasswordAuthentication(smtpUsername, smtpPassword);
                            }
                        });

                        MimeMessage message = new MimeMessage(session);
                        message.setFrom(new InternetAddress(senderEmail, senderName));
                        message.addRecipient(Message.RecipientType.TO, new InternetAddress(recipient.getReceiveEmailAddress()));
                        message.setSubject(subject, "UTF-8");
                        message.setText(content, "UTF-8");

                        Transport.send(message);

                        return new EmailResult(recipient.getEmailSendRecordId(),recipient.getReceiveEmailAddress(), true, "发送成功");

                    } catch (Exception e) {
                        log.error("发送邮件失败: {}", recipient, e);
                        return new EmailResult(recipient.getEmailSendRecordId(),recipient.getReceiveEmailAddress(), false, e.getMessage());
                    }
                }, taskExecutor);

                futures.add(future);
            }

            // 等待所有邮件发送完成
            List<EmailResult> results = futures.stream()
                    .map(CompletableFuture::join)
                    .collect(Collectors.toList());

            return ApiResponse.success(results);

        } catch (Exception e) {
            log.error("并行发送邮件失败", e);
            return ApiResponse.error("并行发送邮件失败: " + e.getMessage());
        }
    }

    // ========================================
    // 查询操作方法
    // ========================================
    public static EmailDomain findEmailDomainByName(Tenant tenant, String domainName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try(EmailClient emailClient = EmailClient.builder().build(provider);) {
            ListEmailDomainsRequest listRequest = ListEmailDomainsRequest.builder()
                    .compartmentId(compartmentId)
                    .name(domainName)
                    .build();

            ListEmailDomainsResponse listResponse = emailClient.listEmailDomains(listRequest);

            List<EmailDomainSummary> domains = listResponse.getEmailDomainCollection().getItems();
            if (domains != null && !domains.isEmpty()) {
                // 找到匹配的域名，获取详细信息
                String domainId = domains.get(0).getId();
                GetEmailDomainRequest getRequest = GetEmailDomainRequest.builder()
                        .emailDomainId(domainId)
                        .build();

                GetEmailDomainResponse getResponse = emailClient.getEmailDomain(getRequest);
                return getResponse.getEmailDomain();
            }
            return null;
        } catch (Exception e) {
            log.warn("查询域名失败: {}", domainName, e);
            return null;
        }

    }

    /**
     * 根据邮箱地址查询发件人是否存在
     */
    public static Sender findSenderByEmail(Tenant tenant,String senderEmail) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try(EmailClient emailClient = EmailClient.builder().build(provider);) {
            ListSendersRequest listRequest = ListSendersRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .emailAddress(senderEmail)
                    .build();

            ListSendersResponse listResponse = emailClient.listSenders(listRequest);
            List<SenderSummary> senders = listResponse.getItems();
            if (senders != null && !senders.isEmpty()) {
                // 找到匹配的发件人，获取详细信息
                String senderId = senders.get(0).getId();
                GetSenderRequest getRequest = GetSenderRequest.builder()
                        .senderId(senderId)
                        .build();
                GetSenderResponse getResponse = emailClient.getSender(getRequest);
                return getResponse.getSender();
            }
            return null;
        } catch (Exception e) {
            log.warn("查询发件人失败: {}", senderEmail, e);
            return null;
        }
    }


    // ========================================
    // 删除操作方法
    // ========================================

    /**
    * @Description: 删除oci的邮箱服务
    * @Param: [com.doubledimple.dao.entity.Tenant, com.doubledimple.dao.entity.TenantEmailConfig]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/28/25 9:24 PM
    */
    public void deleteOciEmail(Tenant tenant, TenantEmailConfig tenantEmailConfig){
        //删除dkim
        deleteDkim(tenant, tenantEmailConfig.getDkimId());
        //删除smtp凭据
        deleteSmtpCredentials(tenant, tenantEmailConfig.getCredentialId());
        //删除认证发件人
        deleteApprovedSender(tenant, tenantEmailConfig.getSenderId());
        //删除邮件域名
        deleteEmailDomain(tenant, tenantEmailConfig.getDomainId());
    }

    /**
     * 删除电子邮件域
     */
    public boolean deleteEmailDomain(Tenant tenant,String emailDomainId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try(EmailClient emailClient = EmailClient.builder().build(provider);) {
            DeleteEmailDomainRequest deleteRequest = DeleteEmailDomainRequest.builder()
                    .emailDomainId(emailDomainId)
                    .build();

            emailClient.deleteEmailDomain(deleteRequest);
            log.info("删除电子邮件域成功: {}", emailDomainId);
            return true;

        } catch (Exception e) {
            log.error("删除电子邮件域失败: {}", emailDomainId, e);
            return false;
        }
    }

    /**
     * 删除已批准的发件人
     */
    public boolean deleteApprovedSender(Tenant tenant,String senderId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try(EmailClient emailClient = EmailClient.builder().build(provider);) {

            DeleteSenderRequest deleteRequest = DeleteSenderRequest.builder()
                    .senderId(senderId)
                    .build();

            emailClient.deleteSender(deleteRequest);
            log.info("删除发件人成功: {}", senderId);
            return true;

        } catch (Exception e) {
            log.error("删除发件人失败: {}", senderId, e);
            return false;
        }
    }

    /**
     * 删除DKIM
     */
    public boolean deleteDkim(Tenant tenant,String dkimId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try(EmailClient emailClient = EmailClient.builder().build(provider);) {

            DeleteDkimRequest deleteRequest = DeleteDkimRequest.builder()
                    .dkimId(dkimId)
                    .build();

            emailClient.deleteDkim(deleteRequest);
            log.info("删除DKIM成功: {}", dkimId);
            return true;

        } catch (Exception e) {
            log.error("删除DKIM失败: {}", dkimId, e);
            return false;
        }
    }

    /**
     * 删除SMTP凭据
     */
    public boolean deleteSmtpCredentials(Tenant tenant,String smtpCredentialId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String userId = provider.getUserId();
        try(IdentityClient identityClient = IdentityClient.builder().build(provider);) {

            DeleteSmtpCredentialRequest deleteRequest = DeleteSmtpCredentialRequest.builder()
                    .userId(userId)
                    .smtpCredentialId(smtpCredentialId)
                    .build();

            identityClient.deleteSmtpCredential(deleteRequest);
            log.info("删除SMTP凭据成功: {}", smtpCredentialId);
            return true;

        } catch (Exception e) {
            log.error("删除SMTP凭据失败: {}", smtpCredentialId, e);
            return false;
        }
    }



    @Data
    public static class SenderCreationResult {
        private String senderId;
        private String senderAddress;
        private String state;

    }

    public static class SenderInfo {
        private String senderId;
        private String senderAddress;
        private String state;
        private Boolean isSpfEnabled;
        private Date timeCreated;

        // Getters and Setters
        public String getSenderId() { return senderId; }
        public void setSenderId(String senderId) { this.senderId = senderId; }

        public String getSenderAddress() { return senderAddress; }
        public void setSenderAddress(String senderAddress) { this.senderAddress = senderAddress; }

        public String getState() { return state; }
        public void setState(String state) { this.state = state; }

        public Boolean getIsSpfEnabled() { return isSpfEnabled; }
        public void setIsSpfEnabled(Boolean isSpfEnabled) { this.isSpfEnabled = isSpfEnabled; }

        public Date getTimeCreated() { return timeCreated; }
        public void setTimeCreated(Date timeCreated) { this.timeCreated = timeCreated; }
    }

    public static class EmailConfigurationInfo {
        private String httpSubmitEndpoint;
        private String smtpSubmitEndpoint;
        private String compartmentId;
        private String error;

        // Getters and Setters
        public String getHttpSubmitEndpoint() { return httpSubmitEndpoint; }
        public void setHttpSubmitEndpoint(String httpSubmitEndpoint) { this.httpSubmitEndpoint = httpSubmitEndpoint; }

        public String getSmtpSubmitEndpoint() { return smtpSubmitEndpoint; }
        public void setSmtpSubmitEndpoint(String smtpSubmitEndpoint) { this.smtpSubmitEndpoint = smtpSubmitEndpoint; }

        public String getCompartmentId() { return compartmentId; }
        public void setCompartmentId(String compartmentId) { this.compartmentId = compartmentId; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }
    }

    @Data
    public static class SmtpCredentialsResult {
        private String smtpUsername;
        private String smtpPassword;
        private String credentialId;

    }

    @Data
    public static class SmtpCredentialInfo {
        private String credentialId;
        private String username;
        private String description;
        private String state;
        private Date timeCreated;

    }

    /**
     * 电子邮件域创建结果
     */
    @Data
    public static class EmailDomainResult {
        private boolean success;
        private String message;
        private String domainId;
        private String domainName;
        private String status;
    }

    @Data
    public static class EmailResult {
        private String email;
        private boolean success;
        private String message;
        private String getEmailSendRecordId;

        public EmailResult(String getEmailSendRecordId,String email, boolean success, String message) {
            this.getEmailSendRecordId = getEmailSendRecordId;
            this.email = email;
            this.success = success;
            this.message = message;
        }
    }

    @Data
    public static class DkimResult {
        private String dkimId;
        private String cnameRecordValue;
        private String status;
        private String message;
    }
}