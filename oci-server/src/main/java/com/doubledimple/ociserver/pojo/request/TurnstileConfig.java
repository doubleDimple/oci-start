package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * Cloudflare Turnstile 验证配置
 */
@Data
public class TurnstileConfig {
    private boolean enabled;
    private String siteKey;
    private String secretKey;
}
