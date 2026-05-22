package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class MfaConfigRequest {
    private boolean enabled;
    private String issuer;
}
