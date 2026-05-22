package com.doubledimple.ociserver.config.event;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.PingUtil;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.AccountTypeEnum;
import com.doubledimple.ociserver.service.InstanceDetailsService;
import com.doubledimple.ociserver.service.SecurityRuleService;
import com.oracle.bmc.core.model.BootVolume;
import com.oracle.bmc.core.model.Instance;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

import java.util.Optional;

import static com.doubledimple.ocicommon.utils.JschUtils.enableRootLogin;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getBootVolume;

/**
 * @version 1.0.0
 * @ClassName InstanceBackUpEventListener
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-13 21:40
 */
@Component
@Slf4j
public class InstanceBackUpEventListener {

    @Resource
    InstanceDetailsService instanceDetailsService;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    SecurityRuleService securityRuleService;

    @Async
    @EventListener
    public void handleInstanceBackUpEvent(InstanceBackUpEvent event) {
        log.debug("handleInstanceBackUpEvent 开始执行......: {}", JSON.toJSONString(event.getInstanceData()));
        try {
            OracleInstanceDetail instanceData = event.getInstanceData();
            Instance instance = instanceData.getInstance();
            User user = instanceData.getUser();
            Optional<Tenant> byId = tenantRepository.findById(user.getId());
            if (!byId.isPresent()) {
                return;
            }
            Tenant tenant = byId.get();
            String accountType = tenant.getAccountType();

            if (StringUtils.isEmpty(accountType) || accountType.equals(AccountTypeEnum.UN_KNOW_ACCOUNT.getType())){
                return;
            }
            //判断下权限,权限不足,舍弃
            /*TenancyDetail tenancyDetail = ociClassLoader.loadManyRegions(tenant);
            if (null == tenancyDetail.getAccountTypeEnum()){
                return;
            }*/

            BootVolume bootVolume = getBootVolume(instanceData.getInstance(), tenant);

            InstanceDetails instanceDetails = new InstanceDetails();
            String processorDescription = instance.getShapeConfig().getProcessorDescription();
            String compartmentId = instance.getCompartmentId();
            Float ocpus = instance.getShapeConfig().getOcpus();
            instanceDetails.setInstanceId(instance.getId());
            instanceDetails.setOcpus(ocpus.intValue());
            instanceDetails.setDisplayName(instance.getDisplayName());
            instanceDetails.setShape(instance.getShape());
            instanceDetails.setProcessorDescription(processorDescription);
            instanceDetails.setArchitecture(instanceData.getArchitecture());
            String value = instance.getLifecycleState().getValue();
            instanceDetails.setState(value);
            instanceDetails.setCompartmentId(compartmentId);
            instanceDetails.setTenantId(user.getId());
            instanceDetails.setMemoryInGBs(instance.getShapeConfig().getMemoryInGBs().intValue());

            //引导卷信息
            instanceDetails.setBootVolumeId(bootVolume.getId());
            instanceDetails.setBootVolumeName(bootVolume.getDisplayName());
            instanceDetails.setBootVolumeSizeInGBs(bootVolume.getSizeInGBs());
            instanceDetails.setVpusPerGB(String.valueOf(bootVolume.getVpusPerGB() == null ? 0L : bootVolume.getVpusPerGB()));
            instanceDetails.setPublicIps(instanceData.getPublicIp());
            instanceDetails.setPrivateIps(instanceData.getPrivateIp());
            //保存开机密码
            instanceDetails.setUsername("root");
            instanceDetails.setPort(22);
            instanceDetails.setPassword(user.getRootPassword());
            instanceDetails.setAvailabilityDomain(instance.getAvailabilityDomain());
            if (!PingUtil.ping(instanceData.getPublicIp()).isReachable()) {
                log.debug("当前ip无法ping通,执行协议开启后再次尝试");
                securityRuleService.checkAndEnableRule(tenant);
            }
            ScriptResult root = enableRootLogin(instanceData.getPublicIp(), "root", instanceData.getRootPasswd(), instanceData.getRootPasswd(), 22);
            if (root.isSuccess()){
                log.debug("root用户登录成功");
                instanceDetailsService.doBootVolumeBackUpNoAuth(instanceDetails, user, bootVolume.getId());
            }else {
                log.debug("root用户登录失败");
            }
        } catch (Exception e) {
            log.warn("handleInstanceBackUpEvent 出现异常,异常原因:{} 忽略",e.getMessage());
        }
        log.info("handleInstanceBackUpEvent end execute success......" );
    }
}
