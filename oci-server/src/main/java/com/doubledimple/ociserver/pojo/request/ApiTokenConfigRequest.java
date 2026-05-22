package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class ApiTokenConfigRequest {
    private boolean enabled;
    private String tokenName;
    private int expirationDays = 30; // 默认30天
    private String description;
    private boolean allowSwaggerAccess = true; // 默认允许访问Swagger
}
