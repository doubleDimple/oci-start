package com.doubledimple.ocicommon.enums;

import java.util.Arrays;
import java.util.List;

/**
 * 域名服务商类型枚举
 */
public enum ProviderType {
    CLOUDFLARE("Cloudflare"),
    ALIYUN("阿里云"),
    TENCENT("腾讯云"),
    DNSPOD("DNSPod"),
    GODADDY("GoDaddy"),
    NAMECHEAP("Namecheap");

    private final String displayName;

    ProviderType(String displayName) {
        this.displayName = displayName;
    }

    public String getDisplayName() {
        return displayName;
    }

    public static List<ProviderType> getAllProviders(){
        return Arrays.asList(CLOUDFLARE,TENCENT);
    }
}
