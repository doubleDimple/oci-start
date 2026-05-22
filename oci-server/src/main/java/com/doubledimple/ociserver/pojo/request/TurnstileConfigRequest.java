package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * Cloudflare Turnstile 配置请求
 */
@Data
public class TurnstileConfigRequest {
    private boolean enabled;
    private String siteKey;
    private String secretKey;
}
