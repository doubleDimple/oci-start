package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.ocicommon.enums.TencentRegion;
import lombok.Data;
import org.apache.commons.lang3.StringUtils;

@Data
public class EdgeOneConfig {
    private boolean enabled;
    private String secretId;
    private String secretKey;

    private String region = "ap-beijing";

    // getters and setters
    public String getRegion() {
        return StringUtils.isNotEmpty(region) ? region : TencentRegion.AP_BEIJING.getCode();
    }
}
