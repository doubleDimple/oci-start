package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName GoogleConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-01-19 11:11
 */
@Data
public class GoogleConfigRequest {
    private boolean enabled;
    private String email;
    private String clientId;
    private String clientSecret;
    private String redirectUri;
}
