package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:11:24日 13:01
 */
@Data
public class DingTalkConfig {
    private boolean enabled;
    private String webhook;
    private String secret;
}
