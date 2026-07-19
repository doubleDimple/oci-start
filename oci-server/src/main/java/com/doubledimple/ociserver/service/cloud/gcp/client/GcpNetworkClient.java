package com.doubledimple.ociserver.service.cloud.gcp.client;

import com.doubledimple.ociserver.utils.google.GcpApiUtil;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.io.IOException;
import java.util.Map;

/**
 * GCP 网络相关门面（外网 IP 等）。
 */
@Component
public class GcpNetworkClient {

    @Resource
    private GcpApiUtil gcpApiUtil;

    public Map<String, Object> switchExternalIp(String projectId, String zone, String instanceName, String credentialsPath)
            throws IOException {
        return gcpApiUtil.switchInstanceExternalIp(projectId, zone, instanceName, credentialsPath);
    }

    public String getExternalIp(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return gcpApiUtil.getInstanceExternalIp(projectId, zone, instanceName, credentialsPath);
    }
}
