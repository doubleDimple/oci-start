package com.doubledimple.ociserver.service.oracle;

import org.springframework.http.ResponseEntity;

import java.util.Map;

public interface VnicService {

    /**
    * @Description: 一键配置负载均衡
    * @Param: [java.lang.String]
    * @return: org.springframework.http.ResponseEntity<java.util.Map<java.lang.String,java.lang.Object>>
    * @Author: doubleDimple
    * @Date: 8/23/25 11:50 AM
    */
    public ResponseEntity<Map<String, Object>> configureLoadBalancer(String instanceId);

    /**
     * @Description: 一键还原网络配置
     * @Param: [java.lang.String]
     * @return: org.springframework.http.ResponseEntity<java.util.Map<java.lang.String,java.lang.Object>>
     * @Author: doubleDimple
     * @Date: 8/23/25 11:50 AM
     */
    public ResponseEntity<Map<String, Object>> restoreNetwork(String instanceId);
}
