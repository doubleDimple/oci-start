package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class EdgeOneConfigRequest {
    private boolean enabled;
    private String secretId;
    private String secretKey;
    private String region;
}
