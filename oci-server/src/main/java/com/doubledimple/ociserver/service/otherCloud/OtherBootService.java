package com.doubledimple.ociserver.service.otherCloud;

import cn.hutool.core.lang.UUID;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.CloudTenancy;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.OtherBootInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.CloudTenancyRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.OtherBootInstanceRepository;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpMachineTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpPublicImageEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.gcp.GcpInstanceCreateDto;
import com.doubledimple.ociserver.pojo.gcp.InstanceInfo;
import com.doubledimple.ociserver.pojo.gcp.OperationResponse;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.cloud.CloudInstanceServiceFactory;
import com.doubledimple.ociserver.service.cloud.CreateInstanceCommand;
import com.doubledimple.ociserver.service.cloud.mapper.GcpInstanceMapper;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.utils.google.GcpApiUtil;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.web.client.HttpClientErrorException;

import javax.annotation.Resource;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.IntStream;

import static com.doubledimple.ocicommon.template.MessageTemplate.GCP_LEGACY_MESSAGE_TEMPLATE;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.genAsiaTime;

/**
 * GCP 旁路兼容层：保留 OTHER_BOOT_INSTANCE + /other API，
 * 创建/同步同时写入 instance_detail，并逐步委托 CloudInstanceService。
 */
@Slf4j
@Service
public class OtherBootService {

    @Resource
    OtherBootInstanceRepository otherBootInstanceRepository;

    @Resource
    GcpApiUtil gcpApiUtil;

    @Resource
    TenantService tenantService;

    @Resource
    private MessageFactory messageFactory;

    @Resource
    private CloudTenancyRepository cloudTenancyRepository;

    @Resource
    private CloudInstanceServiceFactory cloudInstanceServiceFactory;

    @Resource
    private OracleInstanceDetailRepository instanceDetailRepository;

    @Transactional
    public void saveBatch(List<OtherBootInstance> instanceList) {
        otherBootInstanceRepository.saveAll(instanceList);
    }

    /**
     * 创建GCP实例
     */
    @Transactional
    public void createGcpInstances(GcpInstanceCreateDto createDto) {
        log.info("开始创建GCP实例: {}", createDto);

        try {
            IntStream.range(0, createDto.getInstanceCount())
                    .parallel()
                    .forEach(i -> {
                        String instanceName = createDto.getInstanceCount() > 1
                                ? createDto.getInstanceName() + "-" + (i + 1)
                                : createDto.getInstanceName();
                        createSingleGcpInstance(createDto, instanceName, i);
                    });

        } catch (Exception e) {
            log.error("创建GCP实例失败", e);
            throw new RuntimeException("创建实例失败: " + e.getMessage(), e);
        }
    }

    private void createSingleGcpInstance(GcpInstanceCreateDto createDto, String instanceName, int index) {
        final String bootId = generateBootId();
        // 密码只生成一次，DB / 云端脚本 / 通知共用
        final String rootPassword = generateRandomPassword();
        try {
            if (Boolean.TRUE.equals(createDto.getIsCustomMachine()) && !createDto.isValidCustomMachineConfig()) {
                throw new IllegalArgumentException("自定义机器配置不符合GCP规则");
            }

            OtherBootInstance bootInstance = new OtherBootInstance();
            bootInstance.setBootId(bootId);
            bootInstance.setTenantId(createDto.getTenantId());
            bootInstance.setInstanceName(instanceName);
            bootInstance.setZone(createDto.getZone());
            setMachineTypeInfoWithCustom(bootInstance, createDto);
            bootInstance.setDisk(createDto.getDiskSize());
            bootInstance.setInstanceCount(1);
            bootInstance.setStatus(1);
            bootInstance.setArchitecture(getArchitectureFromImage(createDto.getSourceImage()));
            bootInstance.setRootPassword(rootPassword);
            bootInstance.setPublicIp("0.0.0.0");

            String actualMachineType = createDto.getActualMachineType();
            String remark = String.format("GCP实例: %s, 区域: %s, 配置: %s",
                    instanceName, createDto.getZone(), createDto.getMachineConfigDescription());
            bootInstance.setRemark(remark);
            bootInstance.setCloudType(CloudTypeEnum.GOOGLE_CLOUD.getType());

            otherBootInstanceRepository.save(bootInstance);
            log.info("GCP实例记录已保存: {} machineType={}", bootId, actualMachineType);

            createGcpInstanceOnCloud(createDto, instanceName, bootId, bootInstance, rootPassword, actualMachineType);

        } catch (Exception e) {
            log.error("创建GCP实例记录失败: {}", instanceName, e);
            throw new RuntimeException("创建实例失败: " + instanceName + " - " + e.getMessage(), e);
        }
    }

    private void setMachineTypeInfoWithCustom(OtherBootInstance bootInstance, GcpInstanceCreateDto createDto) {
        if (Boolean.TRUE.equals(createDto.getIsCustomMachine())) {
            bootInstance.setOcpu(createDto.getCustomCpuCount());
            bootInstance.setMemory(createDto.getCustomMemoryMb() / 1024);
        } else {
            setMachineTypeInfo(bootInstance, createDto.getMachineType());
        }
    }

    private void createGcpInstanceOnCloud(GcpInstanceCreateDto createDto,
                                          String instanceName,
                                          String bootId,
                                          OtherBootInstance bootInstance,
                                          String rootPassword,
                                          String actualMachineType) {
        Long tenantId = createDto.getTenantId();
        Tenant tenant = tenantService.getById(tenantId);
        if (tenant == null) {
            return;
        }

        try {
            CreateInstanceCommand cmd = new CreateInstanceCommand();
            cmd.setInstanceName(instanceName);
            cmd.setZone(createDto.getZone());
            cmd.setRegion(createDto.getRegion());
            cmd.setMachineType(actualMachineType);
            cmd.setCustomMachine(createDto.getIsCustomMachine());
            cmd.setDiskSizeGb(createDto.getDiskSize());
            cmd.setImageRef(createDto.getSourceImage());
            cmd.setRootPassword(rootPassword);
            if (createDto.getCpuCount() != null) {
                cmd.setCpuCount(createDto.getCpuCount().intValue());
            }
            if (createDto.getMemoryGb() != null) {
                cmd.setMemoryGb(createDto.getMemoryGb().intValue());
            }

            // 统一走 CloudInstanceService（写入 instance_detail）
            cloudInstanceServiceFactory.get(CloudTypeEnum.GOOGLE_CLOUD).create(tenant, cmd);

            // 同步回 OTHER 表状态（兼容旧列表）
            refreshOtherFromCloud(tenant, bootId, instanceName, createDto.getZone(), rootPassword);

            String machineConfig = Boolean.TRUE.equals(createDto.getIsCustomMachine())
                    ? String.format("自定义 %d核 %.1fGB", createDto.getCustomCpuCount(), createDto.getCustomMemoryMb() / 1024.0)
                    : actualMachineType;

            String format = String.format(GCP_LEGACY_MESSAGE_TEMPLATE,
                    genAsiaTime(),
                    machineConfig,
                    createDto.getZone(),
                    instanceName,
                    rootPassword);
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(format);

        } catch (Exception e) {
            log.error("创建GCP实例失败: {}", instanceName, e);
            updateInstanceStatus(bootId, 0, "创建失败: " + e.getMessage());
        }
    }

    private void refreshOtherFromCloud(Tenant tenant, String bootId, String instanceName, String zone, String rootPassword) {
        try {
            InstanceInfo info = gcpApiUtil.getInstance(tenant.getTenancy(), zone, instanceName, tenant.getKeyFile());
            OtherBootInstance instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
            if (instance == null) {
                return;
            }
            instance.setRootPassword(rootPassword);
            if (info != null && "RUNNING".equalsIgnoreCase(info.getStatus())) {
                String ip = info.getExternalIP();
                instance.setStatus(2);
                instance.setPublicIp(StringUtils.isNotBlank(ip) ? ip : "0.0.0.0");
                instance.setRemark("实例已启动");
            } else {
                instance.setStatus(1);
                instance.setRemark("实例启动中");
            }
            otherBootInstanceRepository.save(instance);
        } catch (Exception e) {
            log.warn("回写 OTHER_BOOT_INSTANCE 状态失败: {}", instanceName, e);
            updateInstanceStatus(bootId, 1, "实例创建已提交，等待启动");
        }
    }

    private void updateInstanceStatus(String bootId, int status, String remark) {
        updateInstanceStatus(bootId, status, null, remark);
    }

    private void updateInstanceStatus(String bootId, int status, String publicIp, String remark) {
        try {
            OtherBootInstance instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
            if (instance != null) {
                instance.setStatus(status);
                if (publicIp != null) {
                    instance.setPublicIp(publicIp);
                }
                if (remark != null) {
                    instance.setRemark(remark);
                }
                otherBootInstanceRepository.save(instance);
            }
        } catch (Exception e) {
            log.error("更新实例状态失败: {}", bootId, e);
        }
    }

    private String getArchitectureFromImage(String sourceImageUrl) {
        if (sourceImageUrl != null && sourceImageUrl.contains("arm64")) {
            return "ARM64";
        }
        return "X86_64";
    }

    private void setMachineTypeInfo(OtherBootInstance bootInstance, String machineType) {
        try {
            GcpMachineTypeEnum mt = GcpMachineTypeEnum.getByName(machineType);
            if (mt != null) {
                bootInstance.setOcpu((int) Math.ceil(mt.getVCpuCount()));
                bootInstance.setMemory((int) Math.ceil(mt.getMemoryGb()));
                return;
            }
            if (machineType != null && machineType.contains("e2-micro")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(1);
            } else if (machineType != null && machineType.contains("e2-small")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(2);
            } else if (machineType != null && machineType.contains("e2-medium")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(4);
            } else if (machineType != null && machineType.contains("e2-standard-2")) {
                bootInstance.setOcpu(2);
                bootInstance.setMemory(8);
            } else if (machineType != null && machineType.contains("e2-standard-4")) {
                bootInstance.setOcpu(4);
                bootInstance.setMemory(16);
            } else {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(4);
            }
        } catch (Exception e) {
            bootInstance.setOcpu(1);
            bootInstance.setMemory(4);
        }
    }

    public static String generateBootId() {
        return "gcp-" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
    }

    private String generateRandomPassword() {
        String charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        StringBuilder password = new StringBuilder();
        password.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ".charAt((int) (Math.random() * 26)));
        password.append("abcdefghijklmnopqrstuvwxyz".charAt((int) (Math.random() * 26)));
        password.append("0123456789".charAt((int) (Math.random() * 10)));
        for (int i = 3; i < 16; i++) {
            password.append(charset.charAt((int) (Math.random() * charset.length())));
        }
        char[] chars = password.toString().toCharArray();
        for (int i = 0; i < chars.length; i++) {
            int randomIndex = (int) (Math.random() * chars.length);
            char temp = chars[i];
            chars[i] = chars[randomIndex];
            chars[randomIndex] = temp;
        }
        return new String(chars);
    }

    public List<OtherBootInstance> getGcpInstancesByTenant(Long tenantId) {
        return otherBootInstanceRepository.findByTenantIdAndCloudType(tenantId, CloudTypeEnum.GOOGLE_CLOUD.getType());
    }

    @Transactional
    public void deleteGcpInstance(String bootId) {
        OtherBootInstance instance = null;
        try {
            instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
            if (instance != null) {
                Long tenantId = instance.getTenantId();
                Tenant byId = tenantService.getById(tenantId);
                if (byId != null) {
                    String projectId = byId.getTenancy();
                    String credentialsPath = byId.getKeyFile();
                    String instanceName = instance.getInstanceName();
                    String zone = instance.getZone();

                    OperationResponse operationResponse = gcpApiUtil.deleteInstance(projectId, zone, instanceName, credentialsPath);
                    log.info("GCP实例删除结果: {}", JSON.toJSONString(operationResponse));

                    // 同步删 instance_detail
                    deleteInstanceDetailByName(tenantId, instanceName);

                    otherBootInstanceRepository.delete(instance);
                    log.info("GCP实例记录已从数据库删除: {}", bootId);
                }
            }
        } catch (Exception e) {
            if (e instanceof HttpClientErrorException) {
                HttpClientErrorException error = (HttpClientErrorException) e;
                if (error.getStatusCode() == HttpStatus.NOT_FOUND) {
                    log.warn("GCP实例删除失败: 实例不存在");
                    if (instance != null) {
                        deleteInstanceDetailByName(instance.getTenantId(), instance.getInstanceName());
                        otherBootInstanceRepository.delete(instance);
                    }
                    return;
                }
            }
            log.error("删除GCP实例失败: {}", bootId, e);
        }
    }

    private void deleteInstanceDetailByName(Long tenantId, String instanceName) {
        if (tenantId == null || StringUtils.isBlank(instanceName)) {
            return;
        }
        List<InstanceDetails> list = instanceDetailRepository.findByTenantId(tenantId);
        if (CollectionUtils.isEmpty(list)) {
            return;
        }
        for (InstanceDetails d : list) {
            if (instanceName.equals(d.getDisplayName())) {
                instanceDetailRepository.delete(d);
            }
        }
    }

    public Page<OtherBootInstance> getInstancesByTenantAndCloudType(Long tenantId, Integer cloudType, Pageable pageable) {
        Page<OtherBootInstance> page = otherBootInstanceRepository.findByTenantIdAndCloudType(tenantId, cloudType, pageable);
        List<OtherBootInstance> instances = page.getContent();

        if (!CollectionUtils.isEmpty(instances)) {
            instances.forEach(instance -> {
                Tenant byId = tenantService.getById(instance.getTenantId());
                if (byId != null) {
                    Optional<CloudTenancy> byTenancyNameAndType = cloudTenancyRepository.findByTenancyNameAndType(byId.getTenancy(), 1);
                    if (byTenancyNameAndType.isPresent()) {
                        instance.setDefName(byTenancyNameAndType.get().getDefName());
                    } else {
                        instance.setDefName("未设置");
                    }
                } else {
                    instance.setDefName("未设置");
                }
            });
        }
        return page;
    }

    public Page<OtherBootInstance> getInstancesByCloudType(Integer cloudType, Pageable pageable) {
        Page<OtherBootInstance> page = otherBootInstanceRepository.findByCloudType(cloudType, pageable);
        List<OtherBootInstance> instances = page.getContent();
        if (!CollectionUtils.isEmpty(instances)) {
            instances.forEach(instance -> {
                Tenant byId = tenantService.getById(instance.getTenantId());
                if (byId != null) {
                    Optional<CloudTenancy> byTenancyNameAndType = cloudTenancyRepository.findByTenancyNameAndType(byId.getTenancy(), 1);
                    if (byTenancyNameAndType.isPresent()) {
                        instance.setDefName(byTenancyNameAndType.get().getDefName());
                    } else {
                        instance.setDefName("未设置");
                    }
                } else {
                    instance.setDefName("未设置");
                }
            });
        }
        return page;
    }

    public void deleteByTenantId(Long tenantId) {
        otherBootInstanceRepository.deleteByTenantId(tenantId);
    }

    @Transactional
    public String refreshInstance(String bootId) throws IOException {
        OtherBootInstance instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
        String instanceName = "";
        try {
            if (instance != null) {
                Tenant tenant = tenantService.getById(instance.getTenantId());
                if (tenant != null) {
                    String projectId = tenant.getTenancy();
                    String credentialsPath = tenant.getKeyFile();
                    instanceName = instance.getInstanceName();
                    InstanceInfo instanceInfo = gcpApiUtil.getInstance(projectId, instance.getZone(), instance.getInstanceName(), credentialsPath);

                    if (instanceInfo != null && "RUNNING".equals(instanceInfo.getStatus())) {
                        String externalIp = extractExternalIp(instanceInfo);
                        updateInstanceStatus(bootId, 2, externalIp, "实例已启动");
                        upsertInstanceDetail(tenant, instanceInfo, instance.getRootPassword());
                        log.info("GCP实例已启动: {} IP: {}", instanceName, externalIp);
                    } else {
                        updateInstanceStatus(bootId, 1, "实例启动中");
                    }
                }
            }
        } catch (Exception e) {
            if (e instanceof HttpClientErrorException) {
                HttpClientErrorException error = (HttpClientErrorException) e;
                if (error.getStatusCode() == HttpStatus.NOT_FOUND) {
                    otherBootInstanceRepository.delete(instance);
                    return HttpStatus.NOT_FOUND.toString();
                }
            }
        }
        return "SUCCESS";
    }

    private void upsertInstanceDetail(Tenant tenant, InstanceInfo info, String rootPassword) {
        InstanceDetails mapped = GcpInstanceMapper.toInstanceDetails(info, tenant.getId(), tenant.getTenancy());
        if (mapped == null) {
            return;
        }
        InstanceDetails existing = instanceDetailRepository.findByInstanceId(mapped.getInstanceId());
        if (existing != null) {
            existing.setState(mapped.getState());
            existing.setPublicIps(mapped.getPublicIps());
            existing.setPrivateIps(mapped.getPrivateIps());
            existing.setShape(mapped.getShape());
            existing.setOcpus(mapped.getOcpus());
            existing.setMemoryInGBs(mapped.getMemoryInGBs());
            if (StringUtils.isNotBlank(rootPassword)) {
                existing.setPassword(rootPassword);
            }
            instanceDetailRepository.save(existing);
        } else {
            if (StringUtils.isNotBlank(rootPassword)) {
                mapped.setPassword(rootPassword);
            }
            mapped.setUsername("root");
            instanceDetailRepository.save(mapped);
        }
    }

    private String extractExternalIp(InstanceInfo instanceInfo) {
        try {
            String externalIP = instanceInfo.getExternalIP();
            return (externalIP != null && !externalIP.isEmpty()) ? externalIP : "0.0.0.0";
        } catch (Exception e) {
            return "0.0.0.0";
        }
    }

    @Transactional
    public String changeIp(String bootId) {
        OtherBootInstance instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
        if (instance != null && instance.getStatus() == 2) {
            Tenant tenant = tenantService.getById(instance.getTenantId());
            if (tenant != null) {
                String projectId = tenant.getTenancy();
                String credentialsPath = tenant.getKeyFile();
                String instanceName = instance.getInstanceName();
                try {
                    Map<String, Object> stringObjectMap = gcpApiUtil.switchInstanceExternalIp(projectId, instance.getZone(), instanceName, credentialsPath);
                    String newExternalIp = (String) stringObjectMap.get("newExternalIp");
                    if (newExternalIp != null) {
                        instance.setPublicIp(newExternalIp);
                        otherBootInstanceRepository.save(instance);

                        // 同步 instance_detail
                        List<InstanceDetails> details = instanceDetailRepository.findByTenantId(tenant.getId());
                        if (!CollectionUtils.isEmpty(details)) {
                            for (InstanceDetails d : details) {
                                if (instanceName.equals(d.getDisplayName())) {
                                    d.setPublicIps(newExternalIp);
                                    instanceDetailRepository.save(d);
                                }
                            }
                        }
                    }
                } catch (Exception e) {
                    log.error("切换ip失败", e);
                    return "FAIL";
                }
            }
        }
        return "SUCCESS";
    }
}
