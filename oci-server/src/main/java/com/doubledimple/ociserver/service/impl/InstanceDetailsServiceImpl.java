package com.doubledimple.ociserver.service.impl;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.pojo.request.TenancyDetail;
import com.doubledimple.ociserver.service.InstanceDetailsService;
import com.doubledimple.ociserver.service.OciSshConnService;
import com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.model.BootVolume;
import com.oracle.bmc.core.model.BootVolumeBackup;
import com.oracle.bmc.core.model.Instance;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeanUtils;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;

import static com.doubledimple.ocicommon.utils.JschUtils.verifyPasswordChange;
import static com.doubledimple.ociserver.utils.oracle.OciBackUpUtils.deleteBootVolumeBackup;
import static com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil.BUCKET_NAME;
import static com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil.OBJECT_NAME_PATH_PREFIX;
import static com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil.deleteObject;
import static com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil.getOrCreateBucket;
import static com.doubledimple.ociserver.utils.oracle.OciObjectStorageUtil.uploadJsonString;
import static com.doubledimple.ociserver.utils.oracle.OciBackUpUtils.createBootVolumeBackup;
import static com.doubledimple.ociserver.utils.oracle.OciBackUpUtils.hasBootVolumeBackup;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getBootVolume;

/**
 * @version 1.0.0
 * @ClassName InstanceDetailsServiceImpl
 * @Description TODO
 * @Author doubleDImple
 * @Date 2025-04-02 14:11
 */
@Service
@Slf4j
public class InstanceDetailsServiceImpl implements InstanceDetailsService {

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    OciSshConnService ociSshConnService;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    OciClassLoader ociClassLoader;

    @Override
    public void doSyncInstance(User user, OracleInstanceDetail instanceData,SimpleAuthenticationDetailsProvider provider) {
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider);
             ComputeClient computeClient = ComputeClient.builder().build(provider)) {
            InstanceDetails instanceDetails = new InstanceDetails();
            Instance instance = instanceData.getInstance();
            String compartmentId = instance.getCompartmentId();
            String processorDescription = instance.getShapeConfig().getProcessorDescription();
            InstanceDetails byInstanceId = oracleInstanceDetailRepository.findByInstanceId(instance.getId());
            if (null != byInstanceId){
                BeanUtils.copyProperties(byInstanceId,instanceDetails);
            }
            Float ocpus = instance.getShapeConfig().getOcpus();
            instanceDetails.setInstanceId(instance.getId());
            instanceDetails.setOcpus(ocpus.intValue());
            instanceDetails.setDisplayName(instance.getDisplayName());
            instanceDetails.setShape(instance.getShape());
            instanceDetails.setProcessorDescription(processorDescription);
            instanceDetails.setArchitecture(instanceData.getArchitecture());
            String value = instance.getLifecycleState().getValue();
            if (value.equalsIgnoreCase(Instance.LifecycleState.Terminated.getValue())) {
                return;
            }
            instanceDetails.setState(value);
            instanceDetails.setCompartmentId(compartmentId);
            instanceDetails.setTenantId(user.getId());
            instanceDetails.setMemoryInGBs(instance.getShapeConfig().getMemoryInGBs().intValue());

            //引导卷信息
            BootVolume bootVolume = null;
            try {
                bootVolume = getBootVolume(blockstorageClient, computeClient, instance, compartmentId);
            } catch (Exception e) {
                log.warn("instance get boot volume fail,reason:{}",e.getMessage());
            }
            if (null != bootVolume) {
                instanceDetails.setBootVolumeId(bootVolume.getId());
                instanceDetails.setBootVolumeName(bootVolume.getDisplayName());
                instanceDetails.setBootVolumeSizeInGBs(bootVolume.getSizeInGBs());
                instanceDetails.setVpusPerGB(String.valueOf(bootVolume.getVpusPerGB()));
            } else {
                log.error("用户:{}创建的实例:{}无法获取引导卷信息,实例创建失败", user.getUserName(),JSONUtil.toJsonStr(instance));
                throw new RuntimeException("创建的实例无法获取引导卷信息");
            }
            instanceDetails.setPublicIps(instanceData.getPublicIp());
            instanceDetails.setPrivateIps(instanceData.getPrivateIp());
            oracleInstanceDetailRepository.save(instanceDetails);
            //保存开机密码
            instanceDetails.setUsername("root");
            instanceDetails.setPort(22);
            instanceDetails.setPassword(user.getRootPassword());
            ociSshConnService.saveOrUpdate(instanceDetails);

        } catch (Exception e){
            log.error("创建实例成功后同步出现异常,",e);
        }
    }

    /**
    * @Description: 执行引导卷备份逻辑
    */
    @Override
    public void doBootVolumeBackUp(InstanceDetails instanceDetails, User user, String bootVolumeId) {
        try {
            String tenantId = user.getUserId();
            String architecture = user.getArchitecture();

            Tenant tenant = tenantRepository.findParentByChildTenantId(tenantId);
            // 提前返回：租户不存在或非主区域
            if (null == tenant || !tenant.getIsHomeRegion()) {
                return;
            }

            TenancyDetail tenancyDetail = ociClassLoader.loadManyRegions(tenant);
            if (null == tenancyDetail.getAccountTypeEnum()){
                log.debug("当前账号:{}限制了权限,不在生成备份",tenant.getTenancy());
                return;
            }


            // 检查引导卷备份是否已存在
            BootVolumeBackup bootVolumeBackup = hasBootVolumeBackup(tenant, architecture);
            if (null != bootVolumeBackup) {
                return;
            }

            String objectName = OBJECT_NAME_PATH_PREFIX + architecture;
            // 确保存储桶存在并上传配置
            if (getOrCreateBucket(tenant)) {
                uploadJsonString(tenant,BUCKET_NAME, objectName, JSONUtil.toJsonStr(instanceDetails));
            }


            // 创建引导卷备份
            log.debug("当前租户:{}的引导卷备份不存在,需要创建备份引导卷", tenantId);
            String bootVolumeBackupId = createBootVolumeBackup(tenant, bootVolumeId, architecture);

            // 如果创建失败，提前返回
            if (null == bootVolumeBackupId) {
                //删除对象存储的配置文件
                deleteObject(tenant, objectName);
                return;
            }
            // 创建成功，处理后续步骤
            log.debug("引导卷备份添加成功,id是:{}", bootVolumeBackupId);
        } catch (Exception e) {
            log.warn("doBootVolumeBackUp 出现异常,原因为:{}",e.getMessage());
        }
    }

    /**
    * @Description: 不需要再执行查询是否所有权限的备份
    * @Param: [com.doubledimple.ociserver.domain.InstanceDetails, com.doubledimple.ociserver.domain.dto.User, java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 5/10/25 10:05 PM
    */
    @Override
    public void doBootVolumeBackUpNoAuth(InstanceDetails instanceDetails, User user, String bootVolumeId) {
        try {
            String tenantId = user.getUserId();
            String architecture = user.getArchitecture();

            Tenant tenant = tenantRepository.findParentByChildTenantId(tenantId);
            // 提前返回：租户不存在或非主区域
            if (null == tenant || !tenant.getIsHomeRegion()) {
                return;
            }

            String objectName = OBJECT_NAME_PATH_PREFIX + architecture;
            // 确保存储桶存在并上传配置
            if (getOrCreateBucket(tenant)) {
                //判断 当前架构是否已经存在,不存在再上传,存在,无需再次上产
                String s = OciObjectStorageUtil.downloadJsonString(tenant, OBJECT_NAME_PATH_PREFIX + architecture);
                if (null == s){
                    uploadJsonString(tenant,BUCKET_NAME, objectName, JSONUtil.toJsonStr(instanceDetails));
                }
            }

            // 检查引导卷备份是否已存在
            BootVolumeBackup bootVolumeBackup = hasBootVolumeBackup(tenant, architecture);
            if (null == bootVolumeBackup) {
                // 创建引导卷备份
                log.debug("当前租户:{}的引导卷备份不存在,需要创建备份引导卷", tenantId);
                String bootVolumeBackupId = createBootVolumeBackup(tenant, bootVolumeId, architecture);
                // 创建成功，处理后续步骤
                log.debug("引导卷备份添加成功,id是:{}", bootVolumeBackupId);
            }
        } catch (Exception e) {
            log.warn("doBootVolumeBackUp 出现异常,原因为:{}",e.getMessage());
        }
    }

    @Override
    public void doBootVolumeBackUpNoAuthReplace(InstanceDetails instanceDetails, User user, String bootVolumeId) {
        try {
            String tenantId = user.getUserId();
            String architecture = user.getArchitecture();

            Tenant tenant = tenantRepository.findParentByChildTenantId(tenantId);
            // 提前返回：租户不存在或非主区域
            if (null == tenant || !tenant.getIsHomeRegion()) {
                return;
            }

            String objectName = OBJECT_NAME_PATH_PREFIX + architecture;
            // 确保存储桶存在并上传配置
            if (getOrCreateBucket(tenant)) {
                //判断 当前架构是否已经存在,不存在再上传,存在,无需再次上产
                uploadJsonString(tenant,BUCKET_NAME, objectName, JSONUtil.toJsonStr(instanceDetails));

            }

            // 检查引导卷备份是否已存在
            BootVolumeBackup bootVolumeBackup = hasBootVolumeBackup(tenant, architecture);
            if (null != bootVolumeBackup){
                deleteBootVolumeBackup(tenant, bootVolumeBackup.getId());
            }
            // 创建引导卷备份
            log.debug("当前租户:{}的引导卷备份不存在,需要创建备份引导卷", tenantId);
            String bootVolumeBackupId = createBootVolumeBackup(tenant, bootVolumeId, architecture);
            // 创建成功，处理后续步骤
            log.debug("引导卷备份添加成功,id是:{}", bootVolumeBackupId);

        } catch (Exception e) {
            log.warn("doBootVolumeBackUp 出现异常,原因为:{}",e.getMessage());
        }
    }
}
