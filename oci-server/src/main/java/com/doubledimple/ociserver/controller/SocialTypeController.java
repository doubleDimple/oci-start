package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.TenantSocial;
import com.doubledimple.ocicommon.enums.oci.OciSocialType;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.SocialTypeService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;

/**
 * @version 1.0.0
 * @ClassName SocialTypeController
 * @Description TODO
 * @Author dobleDimple
 * @Date 2026-01-21 16:50
 */
@RestController
@RequestMapping("/social")
@Slf4j
public class SocialTypeController extends BaseController{

    @Resource
    private SocialTypeService socialTypeService;


    //查询当前租户下绑定的社交账号
    @RequestMapping("/list")
    public ApiResponse list(@RequestBody TenantSocial tenantSocial){
        return socialTypeService.getAllSocialType(tenantSocial);
    }

    //修改社交账号
    @RequestMapping("/update")
    public ApiResponse update(@RequestBody TenantSocial tenantSocial){
        return socialTypeService.updateSocial(tenantSocial);
    }

    //新增
    @RequestMapping("/add")
    public ApiResponse add(@RequestBody TenantSocial tenantSocial){
        return socialTypeService.addSocial(tenantSocial);
    }

    //查询支持社交登录的集合
    @RequestMapping("/availableLoginTypes")
    public ApiResponse availableLoginTypes(){
        return ApiResponse.success(OciSocialType.availableLoginTypes());
    }


    //禁用三方社媒登录
    @RequestMapping("/disable")
    public ApiResponse disable(@RequestBody TenantSocial tenantSocial){
        return socialTypeService.disable(tenantSocial);
    }

    //启用
    @RequestMapping("/enable")
    public ApiResponse enable(@RequestBody TenantSocial tenantSocial){
        return socialTypeService.updateSocial(tenantSocial);
    }
}
