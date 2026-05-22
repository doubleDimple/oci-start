package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class CloudflareConfig {
    private String apiToken;
    private String zoneId;
    private String email;
    private boolean enabled;
}
