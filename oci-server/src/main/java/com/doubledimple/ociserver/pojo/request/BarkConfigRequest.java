package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName BarkConfigRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 22:34
 */
@Data
public class BarkConfigRequest {
    private String url;
    private String deviceKey;
    private boolean enabled;
}
