package com.doubledimple.ociserver.service.cloud.oci;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.service.cloud.credential.CloudCredential;
import com.doubledimple.ociserver.service.cloud.credential.CloudCredentialResolver;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Component;

@Component
public class OciCredentialResolver implements CloudCredentialResolver {

    @Override
    public CloudTypeEnum getCloudType() {
        return CloudTypeEnum.ORACLE_CLOUD;
    }

    @Override
    public CloudCredential resolve(Tenant tenant) {
        if (tenant == null) {
            throw new IllegalArgumentException("租户不能为空");
        }
        if (StringUtils.isBlank(tenant.getTenancy()) || StringUtils.isBlank(tenant.getKeyFile())) {
            throw new IllegalArgumentException("OCI 凭证不完整: tenancy/keyFile 必填");
        }
        return new CloudCredential(
                CloudTypeEnum.ORACLE_CLOUD,
                tenant.getTenancy(),
                tenant.getKeyFile(),
                tenant.getTenantId(),
                tenant.getRegion(),
                tenant.getFingerprint()
        );
    }
}
