package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TenantSocial;
import com.doubledimple.dao.repository.TenantSocialRepository;
import com.doubledimple.ocicommon.enums.oci.OciSocialType;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.SocialTypeService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.utils.oracle.SignOnPolicyUtils;
import com.oracle.bmc.identity.model.User;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName SocialTypeServiceImpl
 * @Description 三方登录 服务
 * @Author doubleDimple
 * @Date 2026-01-21 16:52
 */
@Service
@Slf4j
public class SocialTypeServiceImpl implements SocialTypeService {

    @Resource
    private TenantSocialRepository tenantSocialRepository;

    @Resource
    private TenantService tenantService;


    @Override
    public ApiResponse getAllSocialType(TenantSocial tenantSocial) {
        List<TenantSocial> all = tenantSocialRepository.findByTenantId(tenantSocial.getTenantId());
        return ApiResponse.success(all);
    }

    @Override
    @Transactional
    public ApiResponse updateSocial(TenantSocial tenantSocial) {
        try {
            Optional<TenantSocial> byId = tenantSocialRepository.findById(tenantSocial.getId());
            if (!byId.isPresent()) return ApiResponse.error("未找到该社交账号");
            TenantSocial tenantSocialUpdate = byId.get();
            Tenant tenant = tenantService.getById(tenantSocialUpdate.getTenantId());
            if (null == tenant)return ApiResponse.error("未找到该租户");
            String redirectUrl = SignOnPolicyUtils.enableSocialLogin(tenant, OciSocialType.getByName(tenantSocialUpdate.getSocialTypeStr()), tenantSocialUpdate.getClientId(), tenantSocialUpdate.getClientSecret());
            tenantSocialUpdate.setRedirectUrl(redirectUrl);
            tenantSocialUpdate.setSocialStatus("active");
            tenantSocialRepository.save(tenantSocialUpdate);
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("更新社交账号失败:{}", e.getMessage());
            return ApiResponse.error("更新社交账号失败");
        }
    }

    @Override
    @Transactional
    public ApiResponse addSocial(TenantSocial tenantSocial) {
        try {
            Tenant tenant = tenantService.getById(tenantSocial.getTenantId());
            if (null == tenant)return ApiResponse.error("未找到该租户");
            String redirectUrl = SignOnPolicyUtils.enableSocialLogin(tenant, OciSocialType.getByName(tenantSocial.getSocialTypeStr()), tenantSocial.getClientId(), tenantSocial.getClientSecret());
            tenantSocial.setRedirectUrl(redirectUrl);
            tenantSocial.setTenancy(tenant.getTenancy());
            tenantSocialRepository.save(tenantSocial);
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("更新社交账号失败:{}", e.getMessage());
            return ApiResponse.error("更新社交账号失败");
        }
    }

    @Override
    @Transactional
    public ApiResponse disable(TenantSocial tenantSocial) {
        try {
            Optional<TenantSocial> byId = tenantSocialRepository.findById(tenantSocial.getId());
            if (!byId.isPresent()) return ApiResponse.error("未找到该社交账号");
            TenantSocial tenantSocialUpdate = byId.get();
            Tenant tenant = tenantService.getById(tenantSocialUpdate.getTenantId());
            if (null == tenant)return ApiResponse.error("未找到该租户");
            SignOnPolicyUtils.doRemoveSocialFromRule(tenant, OciSocialType.getByName(tenantSocial.getSocialTypeStr()));
            tenantSocialUpdate.setSocialStatus("disabled");
            tenantSocialRepository.save(tenantSocialUpdate);
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("更新社交账号失败:{}", e.getMessage());
            return ApiResponse.error("更新社交账号失败");
        }
    }

    @Override
    @Transactional
    public ApiResponse delete(TenantSocial tenantSocial) {
         tenantSocialRepository.deleteById(tenantSocial.getId());
         return ApiResponse.success();
    }

    //校验邮箱账号是否存在
    private boolean checkEmailExist(TenantSocial tenantSocial) {
        String thirdLoginAddress = tenantSocial.getThirdLoginAddress();
        List<User> users = tenantService.listUsers(String.valueOf(tenantSocial.getTenantId()));
        boolean exists = false;
        if (thirdLoginAddress != null && users != null) {
            exists = users.stream()
                    .map(User::getEmail)
                    .filter(Objects::nonNull)
                    .anyMatch(email -> email.equalsIgnoreCase(thirdLoginAddress));
        }
        return exists;
    }
}
