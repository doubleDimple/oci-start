package com.doubledimple.ociserver.pojo.dto;

import lombok.Data;

@Data
public class TenantTransferRequest {
    private Long tenantId;
    private String transferAmount;
}
