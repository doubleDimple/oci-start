package com.doubledimple.ociserver.service.cloud.oci;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.service.cloud.AbstractCloudInstanceService;
import com.doubledimple.ociserver.service.cloud.CloudCapability;
import com.doubledimple.ociserver.service.cloud.CreateInstanceCommand;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.List;

/**
 * OCI 实例策略：委托既有 OciUtils / 抢机链路。
 * create 走 BOOT_INSTANCE 抢机，不在此直接开通。
 */
@Service
@Slf4j
public class OciCloudInstanceService extends AbstractCloudInstanceService {

    @Resource
    private OciCredentialResolver ociCredentialResolver;

    @Override
    public CloudTypeEnum getCloudType() {
        return CloudTypeEnum.ORACLE_CLOUD;
    }

    @Override
    public CloudCapability capability() {
        return CloudCapability.oci();
    }

    @Override
    public List<InstanceDetails> listRemote(Tenant tenant) throws Exception {
        ociCredentialResolver.resolve(tenant);
        return OciUtils.getAllInstancesByTenant(tenant);
    }

    @Override
    public void start(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isStartStop(), "start");
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        OciUtils.startInstance(provider, local.getInstanceId());
        local.setState("RUNNING");
        instanceDetailRepository.save(local);
    }

    @Override
    public void stop(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isStartStop(), "stop");
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        OciUtils.stopInstance(provider, local.getInstanceId());
        local.setState("STOPPED");
        instanceDetailRepository.save(local);
    }

    @Override
    public void reboot(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isReboot(), "reboot");
        // OCI 无单独 reboot 工具时：stop + start
        stop(local, tenant);
        start(local, tenant);
    }

    @Override
    public void terminate(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isTerminate(), "terminate");
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        OciUtils.terminateInstance(provider, local.getInstanceId(), false);
        instanceDetailRepository.delete(local);
    }

    @Override
    public String changePublicIp(InstanceDetails local, Tenant tenant) throws Exception {
        requireCapability(capability().isChangePublicIp(), "changePublicIp");
        // 复杂 reserved IP 逻辑仍在 OracleInstanceServiceImpl，此处不重复实现
        throw new UnsupportedOperationException("OCI 换 IP 请继续使用既有 /oci/changeIp 接口");
    }

    @Override
    public void create(Tenant tenant, CreateInstanceCommand cmd) throws Exception {
        requireCapability(capability().isCreateDirect(), "create");
        throw new UnsupportedOperationException("OCI 创建请走抢机任务 BOOT_INSTANCE / OpenBoot");
    }
}
