package com.doubledimple.ociserver.service.cloud.credential;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;

/**
 * 将 Tenant 字段解析为中立 CloudCredential。
 */
public interface CloudCredentialResolver {

    CloudTypeEnum getCloudType();

    CloudCredential resolve(Tenant tenant);
}
