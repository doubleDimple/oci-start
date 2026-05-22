package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import java.time.LocalDateTime;

@Data
public class ApiTokenResponse {
    private String tokenName;
    private String tokenValue;
    private String description;
    private LocalDateTime createdAt;
    private LocalDateTime expiresAt;
    private boolean enabled;
    private boolean allowSwaggerAccess;
    private int daysUntilExpiration;
}
