package com.doubledimple.ociserver.service.cloud.credential;

import com.doubledimple.ocicommon.enums.CloudTypeEnum;

/**
 * 中立凭证视图，避免业务代码直接猜 Tenant 字段含义。
 */
public final class CloudCredential {

    private final CloudTypeEnum cloudType;
    /** OCI tenancy OCID / GCP projectId */
    private final String projectOrTenancyId;
    /** 密钥/服务账号 JSON 路径 */
    private final String credentialsPath;
    /** OCI user OCID / GCP SA email */
    private final String principalId;
    private final String region;
    private final String fingerprint;

    public CloudCredential(CloudTypeEnum cloudType,
                           String projectOrTenancyId,
                           String credentialsPath,
                           String principalId,
                           String region,
                           String fingerprint) {
        this.cloudType = cloudType;
        this.projectOrTenancyId = projectOrTenancyId;
        this.credentialsPath = credentialsPath;
        this.principalId = principalId;
        this.region = region;
        this.fingerprint = fingerprint;
    }

    public CloudTypeEnum getCloudType() {
        return cloudType;
    }

    public String getProjectOrTenancyId() {
        return projectOrTenancyId;
    }

    public String getCredentialsPath() {
        return credentialsPath;
    }

    public String getPrincipalId() {
        return principalId;
    }

    public String getRegion() {
        return region;
    }

    public String getFingerprint() {
        return fingerprint;
    }
}
