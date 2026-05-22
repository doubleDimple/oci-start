package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class TrafficTrendRequest extends TrafficQueryRequest {
    private String instanceId;
}
