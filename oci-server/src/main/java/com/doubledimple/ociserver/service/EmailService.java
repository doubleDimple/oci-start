package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.EmailBody;
import com.doubledimple.dao.entity.EmailReceive;
import com.doubledimple.dao.entity.EmailSendRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TenantEmailConfig;
import com.doubledimple.ociserver.pojo.request.EmailBodyRequest;
import com.doubledimple.ociserver.pojo.request.EmailReceiveAddRequest;
import com.doubledimple.ociserver.pojo.request.EmailReceiveRequest;
import com.doubledimple.ociserver.pojo.request.EmailSendRecordRequest;
import com.doubledimple.ociserver.pojo.request.EmailSendRequest;
import com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import org.springframework.data.domain.Page;

import java.util.List;

public interface EmailService {


    /**
     * 分页查询收件人列表
     */
    Page<EmailReceive> listPage(EmailReceiveRequest request);

    /**
     * 添加收件人
     */
    EmailReceive addReceive(EmailReceiveAddRequest request);

    /**
     * 删除收件人
     */
    void deleteReceive(Long id);

    /**
     * 根据ID查询收件人
     */
    EmailReceive getById(Long id);


    //启用邮箱的租户列表
    Page<TenantEmailConfig> listTenantEmailConfig(TenantEmailConfigRequest request);

    /**
    * @Description: 一键启用邮箱服务(需要先配置cf)
    * @Param: [com.doubledimple.dao.entity.Tenant, java.lang.String, long]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 9/27/25 6:33 PM
    */
    ApiResponse enableEmailForTenant(Tenant tenant, String emailDomainName, long tenantId);

    /**
    * @Description: 邮件发送
    * @Param: [com.doubledimple.ociserver.pojo.request.EmailSendRequest]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/28/25 10:30 AM
    */
    void send(EmailSendRequest request);

    /**
    * @Description: emailBodyList
    * @Param: [com.doubledimple.ociserver.pojo.request.EmailBodyRequest]
    * @return: org.springframework.data.domain.Page<com.doubledimple.dao.entity.EmailBody>
    * @Author: doubleDimple
    * @Date: 9/28/25 12:40 PM
    */
    Page<EmailBody> emailBodyList(EmailBodyRequest request);

    /**
    * @Description: emailSendList
    * @Param: [com.doubledimple.ociserver.pojo.request.EmailSendRecordRequest]
    * @return: org.springframework.data.domain.Page<com.doubledimple.dao.entity.EmailSendRecord>
    * @Author: doubleDimple
    * @Date: 9/28/25 12:40 PM
    */
    Page<EmailSendRecord> emailSendList(EmailSendRecordRequest request);

    void deleteEmailBody();
    void deleteEmailBody(EmailBodyRequest request);

    /**
    * @Description: 禁用邮件服务
    * @Param: [com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/28/25 4:42 PM
    */
    void disableEmailForTenant(TenantEmailConfigRequest request);

    void deleteEmailConfig(Long tenantId);

    List<TenantEmailConfig> getTenantEmailConfig(String tenantId);

    //根据名称查询
    TenantEmailConfig getTenantEmailConfigByName(String domainName);

    void update(Tenant tenant, TenantEmailConfig tenantEmailConfig);

}
