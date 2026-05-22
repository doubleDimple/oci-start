package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import java.time.LocalDateTime;

@Data
public class ApiTokenConfig {
    private boolean enabled;
    private String tokenName;
    private String tokenValue;
    private int expirationDays;
    private LocalDateTime createdAt;
    private LocalDateTime expiresAt;
    private String description;
    private boolean allowSwaggerAccess;
}
