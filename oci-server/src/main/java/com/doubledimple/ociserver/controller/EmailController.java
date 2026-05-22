package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.EmailBody;
import com.doubledimple.dao.entity.EmailReceive;
import com.doubledimple.dao.entity.EmailSendRecord;
import com.doubledimple.dao.entity.TenantEmailConfig;
import com.doubledimple.ociserver.pojo.request.EmailBodyRequest;
import com.doubledimple.ociserver.pojo.request.EmailReceiveAddRequest;
import com.doubledimple.ociserver.pojo.request.EmailReceiveRequest;
import com.doubledimple.ociserver.pojo.request.EmailSendRecordRequest;
import com.doubledimple.ociserver.pojo.request.EmailSendRequest;
import com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.EmailService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.validation.Valid;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName EmailController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-27 06:21
 */
@Controller
@RequestMapping("/email")
@Slf4j
public class EmailController extends BaseController{

    @Resource
    private EmailService emailService;

    /**
     * 邮箱管理页面
     */
    @GetMapping("/management")
    public String listUsers(HttpServletRequest request, Model model) {
        model.addAttribute("activePage", "oci-email-management");
        return "email";
    }

    /**
     * 收件人列表(支持分页)
     */
    @PostMapping("/receive/list")
    @ResponseBody
    public ApiResponse listReceive(@RequestBody EmailReceiveRequest emailReceiveRequest) {
        try {
            Page<EmailReceive> page = emailService.listPage(emailReceiveRequest);
            return ApiResponse.success(page);
        } catch (Exception e) {
            log.error("查询收件人列表失败", e);
            return ApiResponse.error("查询收件人列表失败: " + e.getMessage());
        }
    }

    /**
    * @Description: 开启邮件服务的租户列表
    * @Param: [com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 9/27/25 10:53 AM
    */
    @PostMapping("/tenant/list")
    @ResponseBody
    public ApiResponse listTenant(@RequestBody TenantEmailConfigRequest request) {
        try {
            Page<TenantEmailConfig> page = emailService.listTenantEmailConfig(request);
            return ApiResponse.success(page);
        } catch (Exception e) {
            log.warn("查询开启邮件服务的租户列表失败,原因为:{}", e.getMessage(),e);
            return ApiResponse.error("查询开启邮件服务的租户列表失败: " + e.getMessage());
        }
    }

    //根据租户id查询邮件服务
    @PostMapping("/tenant/get")
    @ResponseBody
    public ApiResponse getTenantEmailConfig(@RequestBody TenantEmailConfigRequest request) {
        try {
            List<TenantEmailConfig> tenantEmailConfigs = emailService.getTenantEmailConfig(request.getTenantId());
            return ApiResponse.success(tenantEmailConfigs);
        } catch (Exception e) {
            log.warn("查询开启邮件服务的租户列表失败,原因为:{}", e.getMessage(),e);
            return ApiResponse.error("查询开启邮件服务的租户列表失败: " + e.getMessage());
        }
    }

    /**
    * @Description: 邮件主体记录
    * @Param: [com.doubledimple.ociserver.pojo.request.EmailBodyRequest]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubledimple
    * @Date: 9/28/25 12:37 PM
    */
    @PostMapping("/body/list")
    @ResponseBody
    public ApiResponse emailBodyList(@RequestBody EmailBodyRequest request) {
        try {
            Page<EmailBody> page = emailService.emailBodyList(request);
            return ApiResponse.success(page);
        } catch (Exception e) {
            log.warn("查询开启邮件服务的租户列表失败,原因为:{}", e.getMessage(),e);
            return ApiResponse.error("查询开启邮件服务的租户列表失败: " + e.getMessage());
        }
    }

    /**
    * @Description: 发送邮件收件人列表
    * @Param: [com.doubledimple.ociserver.pojo.request.EmailSendRecordRequest]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubledimple
    * @Date: 9/28/25 12:40 PM
    */
    @PostMapping("/send/list")
    @ResponseBody
    public ApiResponse emailSendList(@RequestBody EmailSendRecordRequest request) {
        try {
            Page<EmailSendRecord> page = emailService.emailSendList(request);
            return ApiResponse.success(page);
        } catch (Exception e) {
            log.warn("查询开启邮件服务的租户列表失败,原因为:{}", e.getMessage(),e);
            return ApiResponse.error("查询开启邮件服务的租户列表失败: " + e.getMessage());
        }
    }

    /**
     * 添加收件人
     */
    @PostMapping("/receive/add")
    @ResponseBody
    public ApiResponse addReceive(@Validated @RequestBody EmailReceiveAddRequest request) {
        try {
            EmailReceive emailReceive = emailService.addReceive(request);
            return ApiResponse.success(emailReceive);
        } catch (Exception e) {
            log.error("添加收件人失败", e);
            return ApiResponse.error("添加收件人失败: " + e.getMessage());
        }
    }

    /**
     * 删除收件人
     */
    @PostMapping("/receive/delete")
    @ResponseBody
    public ApiResponse deleteReceive(@RequestParam Long id) {
        try {
            emailService.deleteReceive(id);
            return ApiResponse.success("删除成功");
        } catch (Exception e) {
            log.error("删除收件人失败", e);
            return ApiResponse.error("删除收件人失败: " + e.getMessage());
        }
    }

    /**
     * 根据ID查询收件人
     */
    @PostMapping("/receive/get")
    @ResponseBody
    public ApiResponse getReceive(@RequestParam Long id) {
        try {
            EmailReceive emailReceive = emailService.getById(id);
            return ApiResponse.success(emailReceive);
        } catch (Exception e) {
            log.error("查询收件人失败", e);
            return ApiResponse.error("查询收件人失败: " + e.getMessage());
        }
    }


    //发送邮件
    @PostMapping("/send")
    @ResponseBody
    public ApiResponse sendEmail(@RequestBody @Valid EmailSendRequest request) {
        try {
            emailService.send(request);
            return ApiResponse.success("发送成功");
        } catch (Exception e) {
            log.warn("发送邮件失败, 原因为:{}", e.getMessage(), e);
            return ApiResponse.error("发送邮件失败请稍后再试 ");
        }
    }


    /**
    * @Description: 批量删除邮箱发送记录
    * @Param: []
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: renyx
    * @Date: 9/28/25 2:54 PM
    */
    @PostMapping("/body/batchDelete")
    @ResponseBody
    public ApiResponse deleteEmailBody() {
        try {
            emailService.deleteEmailBody();
            return ApiResponse.success("删除成功");
        } catch (Exception e) {
            log.warn("批量删除邮箱主体失败, 原因为:{}", e.getMessage(), e);
            return ApiResponse.error("批量删除邮箱主体失败请稍后再试 ");
        }
    }

    /**
    * @Description: 删除某个邮件主体的发送记录
    * @Param: [java.lang.Long]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 9/28/25 3:08 PM
    */
    @PostMapping("/body/delete")
    @ResponseBody
    public ApiResponse deleteEmailBody(@RequestBody EmailBodyRequest request) {
        try {
            emailService.deleteEmailBody(request);
            return ApiResponse.success("删除成功");
        } catch (Exception e) {
            log.warn("删除邮箱主体失败, 原因为:{}", e.getMessage(), e);
            return ApiResponse.error("删除邮箱主体失败请稍后再试 ");
        }
    }

    /**
    * @Description: 禁用邮件服务
    * @Param: [com.doubledimple.ociserver.pojo.request.TenantEmailConfigRequest]
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 9/28/25 5:04 PM
    */
    @PostMapping("/disable")
    @ResponseBody
    public ApiResponse disableEmailService(@RequestBody TenantEmailConfigRequest request) {
        try {
            emailService.disableEmailForTenant(request);
            return ApiResponse.success("禁用成功");
        } catch (Exception e) {
            log.warn("禁用邮件服务失败, 原因为:{}", e.getMessage(), e);
            return ApiResponse.error("禁用邮件服务失败请稍后再试 ");
        }
    }
}
