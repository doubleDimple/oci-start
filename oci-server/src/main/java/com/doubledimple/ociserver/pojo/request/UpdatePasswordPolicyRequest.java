package com.doubledimple.ociserver.pojo.request;


import lombok.Data;

@Data
public class UpdatePasswordPolicyRequest {
    private String tenantId;
    private boolean enablePasswordExpiry;
    private Integer expiryDays; // 可选，默认90天
}
