package com.doubledimple.ociserver.service.cloud.gcp;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpPublicImageEnum;
import com.doubledimple.ociserver.pojo.gcp.InstanceInfo;
import com.doubledimple.ociserver.pojo.gcp.OperationResponse;
import com.doubledimple.ociserver.service.cloud.AbstractCloudInstanceService;
import com.doubledimple.ociserver.service.cloud.CloudCapability;
import com.doubledimple.ociserver.service.cloud.CreateInstanceCommand;
import com.doubledimple.ociserver.service.cloud.credential.CloudCredential;
import com.doubledimple.ociserver.service.cloud.gcp.client.GcpComputeClient;
import com.doubledimple.ociserver.service.cloud.gcp.client.GcpNetworkClient;
import com.doubledimple.ociserver.service.cloud.mapper.GcpInstanceMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * GCP 实例策略实现。底层走 GcpComputeClient / GcpNetworkClient。
 */
@Service
@Slf4j
public class GcpCloudInstanceService extends AbstractCloudInstanceService {

    private static final List<Integer> DEFAULT_PORTS = Arrays.asList(22, 80, 443);

    @Resource
    private GcpCredentialResolver gcpCredentialResolver;

    @Resource
    private GcpComputeClient gcpComputeClient;

    @Resource
    private GcpNetworkClient gcpNetworkClient;

    @Override
    public CloudTypeEnum getCloudType() {
        return CloudTypeEnum.GOOGLE_CLOUD;
    }

    @Override
    public CloudCapability capability() {
        return CloudCapability.gcp();
    }

    @Override
    protected String defaultUsername() {
        return "root";
    }

    @Override
    public List<InstanceDetails> listRemote(Tenant tenant) throws Exception {
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);
        List<InstanceInfo> infos = gcpComputeClient.listAllInstances(
                cred.getProjectOrTenancyId(), cred.getCredentialsPath());
        List<InstanceDetails> result = new ArrayList<InstanceDetails>();
        if (CollectionUtils.isEmpty(infos)) {
            return result;
        }
        for (InstanceInfo info : infos) {
            InstanceDetails d = GcpInstanceMapper.toInstanceDetails(
                    info, tenant.getId(), cred.getProjectOrTenancyId());
            if (d != null) {
                result.add(d);
            }
        }
        return result;
    }

    @Override
    public void start(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isStartStop(), "start");
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);
        String zone = resolveZone(local);
        String name = resolveName(local);
        gcpComputeClient.startInstance(cred.getProjectOrTenancyId(), zone, name, cred.getCredentialsPath());
        local.setState("RUNNING");
        instanceDetailRepository.save(local);
    }

    @Override
    public void stop(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isStartStop(), "stop");
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);
        String zone = resolveZone(local);
        String name = resolveName(local);
        gcpComputeClient.stopInstance(cred.getProjectOrTenancyId(), zone, name, cred.getCredentialsPath());
        local.setState("STOPPED");
        instanceDetailRepository.save(local);
    }

    @Override
    public void reboot(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isReboot(), "reboot");
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);
        String zone = resolveZone(local);
        String name = resolveName(local);
        gcpComputeClient.resetInstance(cred.getProjectOrTenancyId(), zone, name, cred.getCredentialsPath());
        local.setState("RUNNING");
        instanceDetailRepository.save(local);
    }

    @Override
    public void terminate(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isTerminate(), "terminate");
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);
        String zone = resolveZone(local);
        String name = resolveName(local);
        try {
            gcpComputeClient.deleteInstance(cred.getProjectOrTenancyId(), zone, name, cred.getCredentialsPath());
        } catch (Exception e) {
            log.warn("删除 GCP 云端实例失败(将仍删本地): {}/{}", zone, name, e);
        }
        instanceDetailRepository.delete(local);
    }

    @Override
    public String changePublicIp(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isChangePublicIp(), "changePublicIp");
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);
        String zone = resolveZone(local);
        String name = resolveName(local);
        Map<String, Object> result = gcpNetworkClient.switchExternalIp(
                cred.getProjectOrTenancyId(), zone, name, cred.getCredentialsPath());
        String newIp = result == null ? null : (String) result.get("newExternalIp");
        if (StringUtils.isNotBlank(newIp)) {
            local.setPublicIps(newIp);
            instanceDetailRepository.save(local);
        }
        return newIp;
    }

    @Override
    public void create(Tenant tenant, CreateInstanceCommand cmd) throws Exception {
        requireCapability(capability().isCreateDirect(), "create");
        if (cmd == null || StringUtils.isBlank(cmd.getInstanceName()) || StringUtils.isBlank(cmd.getZone())) {
            throw new IllegalArgumentException("创建参数不完整: instanceName/zone 必填");
        }
        CloudCredential cred = gcpCredentialResolver.resolve(tenant);

        String machineType = cmd.getMachineType();
        if (StringUtils.isBlank(machineType)) {
            machineType = "e2-medium";
        }
        String rootPassword = cmd.getRootPassword();
        if (StringUtils.isBlank(rootPassword)) {
            throw new IllegalArgumentException("rootPassword 不能为空");
        }
        int disk = cmd.getDiskSizeGb() == null ? 20 : cmd.getDiskSizeGb();
        GcpPublicImageEnum imageEnum = resolveImage(cmd.getImageRef());

        Map<String, Object> result = gcpComputeClient.createWithLimitedPorts(
                cred.getProjectOrTenancyId(),
                cmd.getZone(),
                cmd.getInstanceName(),
                machineType,
                imageEnum,
                disk,
                rootPassword,
                DEFAULT_PORTS,
                cred.getCredentialsPath()
        );

        // 等待 operation
        Object opObj = result == null ? null : result.get("instanceOperation");
        if (opObj instanceof OperationResponse) {
            OperationResponse op = (OperationResponse) opObj;
            if (StringUtils.isNotBlank(op.getSelfLink())) {
                try {
                    gcpComputeClient.waitForOperation(op.getSelfLink(), cred.getCredentialsPath(), 180);
                } catch (Exception e) {
                    log.warn("等待 GCP 创建 operation 超时/失败: {}", cmd.getInstanceName(), e);
                }
            }
        }

        // 轮询实例 RUNNING + IP
        InstanceDetails detail = waitAndBuildDetail(tenant, cred, cmd, machineType, disk, rootPassword, imageEnum);
        instanceDetailRepository.save(detail);
        log.info("GCP 实例已写入 instance_detail: {} state={} ip={}",
                detail.getDisplayName(), detail.getState(), detail.getPublicIps());
    }

    private InstanceDetails waitAndBuildDetail(Tenant tenant,
                                               CloudCredential cred,
                                               CreateInstanceCommand cmd,
                                               String machineType,
                                               int disk,
                                               String rootPassword,
                                               GcpPublicImageEnum imageEnum) throws Exception {
        InstanceInfo info = null;
        for (int i = 0; i < 30; i++) {
            try {
                info = gcpComputeClient.getInstance(
                        cred.getProjectOrTenancyId(), cmd.getZone(), cmd.getInstanceName(), cred.getCredentialsPath());
                if (info != null && "RUNNING".equalsIgnoreCase(info.getStatus())
                        && StringUtils.isNotBlank(info.getExternalIP())) {
                    break;
                }
            } catch (Exception e) {
                log.debug("轮询实例未就绪: {}", cmd.getInstanceName());
            }
            Thread.sleep(5000L);
        }

        InstanceDetails detail;
        if (info != null) {
            detail = GcpInstanceMapper.toInstanceDetails(info, tenant.getId(), cred.getProjectOrTenancyId());
        } else {
            detail = new InstanceDetails();
            detail.setTenantId(tenant.getId());
            detail.setCloudType(CloudTypeEnum.GOOGLE_CLOUD.getType());
            detail.setInstanceId(cmd.getZone() + "/" + cmd.getInstanceName());
            detail.setDisplayName(cmd.getInstanceName());
            detail.setAvailabilityDomain(cmd.getZone());
            detail.setShape(machineType);
            detail.setState("PROVISIONING");
            detail.setCompartmentId("projects/" + cred.getProjectOrTenancyId());
            detail.setBootVolumeSizeInGBs((long) disk);
            detail.setPublicIps("");
            detail.setPrivateIps("");
        }
        detail.setPassword(rootPassword);
        detail.setUsername("root");
        detail.setPort(22);
        if (cmd.getCpuCount() != null) {
            detail.setOcpus(cmd.getCpuCount());
        }
        if (cmd.getMemoryGb() != null) {
            detail.setMemoryInGBs(cmd.getMemoryGb());
        }
        if (imageEnum != null) {
            detail.setArchitecture(imageEnum.getArchitecture() == null ? "X86_64" : imageEnum.getArchitecture());
        }
        detail.setRemark(String.format("GCP %s %s", cmd.getZone(), machineType));
        return detail;
    }

    private GcpPublicImageEnum resolveImage(String imageRef) {
        if (StringUtils.isBlank(imageRef)) {
            return GcpPublicImageEnum.DEBIAN_12_X86;
        }
        if (imageRef.contains("arm64")) {
            return GcpPublicImageEnum.DEBIAN_12_ARM64;
        }
        GcpPublicImageEnum byName = GcpPublicImageEnum.getByImageName(imageRef);
        if (byName != null) {
            return byName;
        }
        return GcpPublicImageEnum.DEBIAN_12_X86;
    }

    private String resolveZone(InstanceDetails local) {
        if (StringUtils.isNotBlank(local.getAvailabilityDomain())) {
            return local.getAvailabilityDomain();
        }
        // instanceId 可能是 zone/name
        if (StringUtils.isNotBlank(local.getInstanceId()) && local.getInstanceId().contains("/")) {
            return local.getInstanceId().substring(0, local.getInstanceId().indexOf('/'));
        }
        throw new IllegalArgumentException("GCP 实例缺少 zone(availabilityDomain)");
    }

    private String resolveName(InstanceDetails local) {
        if (StringUtils.isNotBlank(local.getDisplayName())) {
            return local.getDisplayName();
        }
        if (StringUtils.isNotBlank(local.getInstanceId()) && local.getInstanceId().contains("/")) {
            return local.getInstanceId().substring(local.getInstanceId().indexOf('/') + 1);
        }
        return local.getInstanceId();
    }
}
