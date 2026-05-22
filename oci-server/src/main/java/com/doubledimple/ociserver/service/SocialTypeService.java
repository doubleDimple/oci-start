package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.TenantSocial;
import com.doubledimple.ocicommon.param.ApiResponse;

import java.util.List;

public interface SocialTypeService {



    ApiResponse getAllSocialType(TenantSocial tenantSocial);

    ApiResponse updateSocial(TenantSocial tenantSocial);

    ApiResponse addSocial(TenantSocial tenantSocial);

    ApiResponse disable(TenantSocial tenantSocial);

    //删除
    ApiResponse delete(TenantSocial tenantSocial);
}
