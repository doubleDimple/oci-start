package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class FeishuConfig {
    private String webhook;
    private String secret;
    private boolean enabled;
}
