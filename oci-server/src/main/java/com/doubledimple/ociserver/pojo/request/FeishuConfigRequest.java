package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class FeishuConfigRequest {
    private String webhook;
    private String secret;
    private boolean enabled;
    private Boolean keepWebhook;
    private Boolean keepSecret;

    // Preserve the previous Java constructor as well as the default JSON contract.
    public FeishuConfigRequest(String webhook, String secret, boolean enabled) {
        this.webhook = webhook;
        this.secret = secret;
        this.enabled = enabled;
    }
}
