package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:11:24日 12:55
 */
@Data
public class DingTalkConfigRequest {
    private boolean enabled;
    private String webhook;
    private String secret;
}
