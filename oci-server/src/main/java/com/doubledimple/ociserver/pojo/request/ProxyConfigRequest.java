package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class ProxyConfigRequest {
    private boolean enabled;
    private String type;
    private String host;
    private int port;
}
