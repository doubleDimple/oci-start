package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class GoogleConfig {
    private boolean enabled;
    private String email;
    private String clientId;
    private String clientSecret;
    private String redirectUri;
}
