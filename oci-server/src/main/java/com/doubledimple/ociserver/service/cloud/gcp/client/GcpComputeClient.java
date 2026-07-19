package com.doubledimple.ociserver.service.cloud.gcp.client;

import com.doubledimple.ocicommon.enums.gcp.GcpPublicImageEnum;
import com.doubledimple.ociserver.pojo.gcp.InstanceInfo;
import com.doubledimple.ociserver.pojo.gcp.OperationResponse;
import com.doubledimple.ociserver.utils.google.GcpApiUtil;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.io.IOException;
import java.util.List;
import java.util.Map;

/**
 * GCP Compute 门面：新代码走此客户端，底层暂委托 GcpApiUtil，便于后续替换 SDK。
 */
@Component
public class GcpComputeClient {

    @Resource
    private GcpApiUtil gcpApiUtil;

    public List<InstanceInfo> listAllInstances(String projectId, String credentialsPath) throws IOException {
        return gcpApiUtil.getAllInstance(projectId, credentialsPath);
    }

    public InstanceInfo getInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return gcpApiUtil.getInstance(projectId, zone, instanceName, credentialsPath);
    }

    public OperationResponse deleteInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return gcpApiUtil.deleteInstance(projectId, zone, instanceName, credentialsPath);
    }

    public OperationResponse startInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return gcpApiUtil.startInstance(projectId, zone, instanceName, credentialsPath);
    }

    public OperationResponse stopInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return gcpApiUtil.stopInstance(projectId, zone, instanceName, credentialsPath);
    }

    public OperationResponse resetInstance(String projectId, String zone, String instanceName, String credentialsPath) throws IOException {
        return gcpApiUtil.resetInstance(projectId, zone, instanceName, credentialsPath);
    }

    public Map<String, Object> createWithLimitedPorts(String projectId,
                                                      String zone,
                                                      String instanceName,
                                                      String machineType,
                                                      GcpPublicImageEnum imageEnum,
                                                      int diskSizeGb,
                                                      String rootPassword,
                                                      List<Integer> allowedPorts,
                                                      String credentialsPath) throws IOException {
        return gcpApiUtil.createInstanceRootPassAndFirewall(
                projectId, zone, instanceName, machineType, imageEnum, diskSizeGb, rootPassword, allowedPorts, credentialsPath);
    }

    public OperationResponse waitForOperation(String operationUrl, String credentialsPath, int timeoutSeconds)
            throws IOException, InterruptedException {
        return gcpApiUtil.waitForOperation(operationUrl, credentialsPath, timeoutSeconds);
    }
}
