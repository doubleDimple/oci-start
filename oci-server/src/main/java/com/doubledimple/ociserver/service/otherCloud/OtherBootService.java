package com.doubledimple.ociserver.service.otherCloud;

import cn.hutool.core.lang.UUID;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.CloudTenancy;
import com.doubledimple.dao.entity.OtherBootInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.CloudTenancyRepository;
import com.doubledimple.dao.repository.OtherBootInstanceRepository;
import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpMachineTypeEnum;
import com.doubledimple.ocicommon.enums.gcp.GcpPublicImageEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.gcp.GcpInstanceCreateDto;
import com.doubledimple.ociserver.pojo.gcp.InstanceInfo;
import com.doubledimple.ociserver.pojo.gcp.OperationResponse;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.utils.google.GcpApiUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.web.client.HttpClientErrorException;

import javax.annotation.Resource;
import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.IntStream;

import static com.doubledimple.ocicommon.enums.gcp.GcpMachineTypeEnum.getCustomerCpu;
import static com.doubledimple.ocicommon.template.MessageTemplate.GCP_LEGACY_MESSAGE_TEMPLATE;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.genAsiaTime;

/**
 *
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
            // 并行创建多个实例
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

    /**
     * 创建单个GCP实例
     */
    /**
     * 创建单个GCP实例（支持自定义配置）
     */
    private void createSingleGcpInstance(GcpInstanceCreateDto createDto, String instanceName, int index) {
        final String bootId = generateBootId();
        try {
            // 1. 验证自定义机器配置
            if (Boolean.TRUE.equals(createDto.getIsCustomMachine()) && !createDto.isValidCustomMachineConfig()) {
                throw new IllegalArgumentException("自定义机器配置不符合GCP规则");
            }

            // 2. 先保存到数据库
            OtherBootInstance bootInstance = new OtherBootInstance();
            bootInstance.setBootId(bootId);
            bootInstance.setTenantId(createDto.getTenantId());
            bootInstance.setInstanceName(instanceName);
            bootInstance.setZone(createDto.getZone());

            // 设置机器类型信息（支持自定义）
            setMachineTypeInfoWithCustom(bootInstance, createDto);

            bootInstance.setDisk(createDto.getDiskSize());
            bootInstance.setInstanceCount(1); // 单个实例
            bootInstance.setStatus(1); // 开机中
            bootInstance.setArchitecture(getArchitectureFromImage(createDto.getSourceImage()));
            bootInstance.setRootPassword(generateRandomPassword());
            bootInstance.setPublicIp("0.0.0.0"); // 初始IP

            // 设置备注信息，包含机器配置描述
            String remark = String.format("GCP实例: %s, 区域: %s, 配置: %s",
                    instanceName, createDto.getZone(), createDto.getMachineConfigDescription());
            bootInstance.setRemark(remark);

            bootInstance.setCloudType(CloudTypeEnum.GOOGLE_CLOUD.getType());

            // 保存到数据库
            otherBootInstanceRepository.save(bootInstance);
            log.info("GCP实例记录已保存到数据库: {} - {}", bootId, createDto.getMachineConfigDescription());

            // 3. 异步调用GCP API创建实例
            createGcpInstanceAsync(createDto, instanceName, bootId, bootInstance);

        } catch (Exception e) {
            log.error("创建GCP实例记录失败: {}", instanceName, e);
            throw new RuntimeException("创建实例失败: " + instanceName + " - " + e.getMessage(), e);
        }
    }

    /**
     * 设置机器类型信息（支持自定义配置）
     */
    private void setMachineTypeInfoWithCustom(OtherBootInstance bootInstance, GcpInstanceCreateDto createDto) {
        if (Boolean.TRUE.equals(createDto.getIsCustomMachine())) {
            // 自定义机器类型
            bootInstance.setOcpu(createDto.getCustomCpuCount());
            bootInstance.setMemory(createDto.getCustomMemoryMb() / 1024); // 转换为GB

            log.info("设置自定义机器类型: {} CPU, {}MB 内存",
                    createDto.getCustomCpuCount(), createDto.getCustomMemoryMb());
        } else {
            // 预定义机器类型，使用原有逻辑
            setMachineTypeInfo(bootInstance, createDto.getMachineType());

            log.info("设置预定义机器类型: {}", createDto.getMachineType());
        }
    }

    /**
     * 异步创建GCP实例
     */
    /**
     * 异步创建GCP实例（支持自定义配置）
     */
    private void createGcpInstanceAsync(GcpInstanceCreateDto createDto, String instanceName, String bootId, OtherBootInstance bootInstance) {
        Long tenantId = createDto.getTenantId();
        Tenant tenant = tenantService.getById(tenantId);
        if (tenant == null) return;
        String projectId = tenant.getTenancy();
        String credentialsPath = tenant.getKeyFile();

        try {
            // 从sourceImage URL中解析镜像信息
            GcpPublicImageEnum imageEnum = parseImageFromUrl(createDto.getSourceImage());
            if (imageEnum == null) {
                // 如果解析失败，使用默认镜像
                imageEnum = GcpPublicImageEnum.DEBIAN_12_X86;
            }

            // 生成随机密码
            String rootPassword = generateRandomPassword();

            // 定义需要开放的端口
            List<Integer> allowedPorts = Arrays.asList(22, 80, 443, 8080, 3389);

            // 获取实际的机器类型（可能是自定义的）
            GcpMachineTypeEnum customerCpu = getCustomerCpu(createDto.getCustomCpuCount());
            String actualMachineType = customerCpu != null ? customerCpu.getName() : GcpMachineTypeEnum.E2_STANDARD_2.getName();
            boolean isCustomMachine = Boolean.TRUE.equals(createDto.getIsCustomMachine());

            log.info("开始创建GCP实例: {} - 机器类型: {} (自定义: {})",
                    instanceName, actualMachineType, isCustomMachine);

            // 调用GCP API创建实例（使用修改后的方法，自动支持自定义）
            /*Map<String, Object> result = gcpApiUtil.createInstanceRootPassAndFirewall(
                    projectId,
                    createDto.getZone(),
                    instanceName,
                    actualMachineType, // 传入实际机器类型（可能是自定义格式）
                    imageEnum,
                    createDto.getDiskSize(),
                    rootPassword,
                    allowedPorts,
                    credentialsPath
            );*/

            Map<String, Object> result = gcpApiUtil.createInstanceWithAllPortsOpen(
                    projectId,
                    createDto.getZone(),
                    instanceName,
                    actualMachineType,
                    imageEnum,
                    createDto.getDiskSize(),
                    rootPassword,
                    credentialsPath
            );

            log.info("GCP实例创建请求已提交: {} -> {}", instanceName, result);

            // 更新数据库记录
            updateInstanceWithCreationResult(bootId, rootPassword, result);

            // 发送消息通知
            String machineConfig = isCustomMachine ?
                    String.format("自定义 %d核 %.1fGB", createDto.getCustomCpuCount(), createDto.getCustomMemoryMb() / 1024.0) :
                    actualMachineType;

            String format = String.format(GCP_LEGACY_MESSAGE_TEMPLATE,
                    genAsiaTime(),
                    machineConfig,
                    createDto.getZone(),
                    bootInstance.getInstanceName(),
                    bootInstance.getRootPassword());
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(format);

        } catch (Exception e) {
            log.error("异步创建GCP实例失败: {}", instanceName, e);
            updateInstanceStatus(bootId, 0, "创建失败: " + e.getMessage());
        }
    }

    /**
     * 等待实例准备就绪
     */
    private void waitForInstanceReady(String zone, String instanceName, String bootId,String projectId,String credentialsPath) {
        try {
            // 等待一段时间让实例启动
            Thread.sleep(15000); // 等待30秒

            // 获取实例信息
            InstanceInfo instanceInfo = gcpApiUtil.getInstance(projectId, zone, instanceName, credentialsPath);

            if (instanceInfo != null && "RUNNING".equals(instanceInfo.getStatus())) {
                // 获取外部IP
                String externalIp = extractExternalIp(instanceInfo);
                updateInstanceStatus(bootId, 2, externalIp, "实例已启动");
                log.info("GCP实例已启动: {} IP: {}", instanceName, externalIp);
            } else {
                updateInstanceStatus(bootId, 1, "实例启动中");
            }

        } catch (Exception e) {
            log.warn("获取实例状态失败: {}", instanceName, e);
            // 不更新状态，保持开机中状态
        }
    }

    /**
     * 从实例信息中提取外部IP
     */
    private String extractExternalIp(Object instanceInfo) {
        try {
            if (instanceInfo instanceof InstanceInfo) {
                InstanceInfo instance = (InstanceInfo) instanceInfo;
                String externalIP = instance.getExternalIP();
                return (externalIP != null && !externalIP.isEmpty()) ? externalIP : "0.0.0.0";
            }
            return "0.0.0.0";
        } catch (Exception e) {
            log.error("提取外部IP时发生错误", e);
            return "0.0.0.0";
        }
    }

    /**
     * 更新实例创建结果
     */
    private void updateInstanceWithCreationResult(String bootId, String rootPassword, Map<String, Object> result) {
        try {
            OtherBootInstance instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
            if (instance != null) {
                instance.setRootPassword(rootPassword);
                instance.setStatus(1); // 开机中

                // 从结果中提取信息更新备注
                String remark = instance.getRemark();
                if (result.containsKey("firewallRuleCreated")) {
                    remark += " 防火墙: " + result.get("firewallRuleName");
                }
                instance.setRemark(remark);

                otherBootInstanceRepository.save(instance);
            }
        } catch (Exception e) {
            log.error("更新实例创建结果失败: {}", bootId, e);
        }
    }

    /**
     * 更新实例状态
     */
    private void updateInstanceStatus(String bootId, int status, String remark) {
        updateInstanceStatus(bootId, status, null, remark);
    }

    /**
     * 更新实例状态和IP
     */
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

    /**
     * 从镜像URL解析镜像枚举
     */
    private GcpPublicImageEnum parseImageFromUrl(String sourceImageUrl) {
        try {
            // URL格式: projects/debian-cloud/global/images/debian-12-bookworm-v20250610
            if (sourceImageUrl.contains("debian-12-bookworm-v") && sourceImageUrl.contains("arm64")) {
                return GcpPublicImageEnum.DEBIAN_12_ARM64;
            } else if (sourceImageUrl.contains("debian-12-bookworm-v")) {
                return GcpPublicImageEnum.DEBIAN_12_X86;
            }
            return GcpPublicImageEnum.DEBIAN_12_X86; // 默认
        } catch (Exception e) {
            return GcpPublicImageEnum.DEBIAN_12_X86;
        }
    }

    /**
     * 从镜像信息获取架构
     */
    private String getArchitectureFromImage(String sourceImageUrl) {
        if (sourceImageUrl.contains("arm64")) {
            return "ARM64";
        }
        return "X86_64";
    }

    /**
     * 根据机器类型设置CPU和内存信息
     */
    private void setMachineTypeInfo(OtherBootInstance bootInstance, String machineType) {
        try {
            // 解析常见的机器类型
            if (machineType.contains("e2-micro")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(1);
            } else if (machineType.contains("e2-small")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(2);
            } else if (machineType.contains("e2-medium")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(4);
            } else if (machineType.contains("e2-standard-2")) {
                bootInstance.setOcpu(2);
                bootInstance.setMemory(8);
            } else if (machineType.contains("e2-standard-4")) {
                bootInstance.setOcpu(4);
                bootInstance.setMemory(16);
            } else if (machineType.contains("n1-standard-1")) {
                bootInstance.setOcpu(1);
                bootInstance.setMemory(4); // 3.75GB向上取整
            } else if (machineType.contains("n1-standard-2")) {
                bootInstance.setOcpu(2);
                bootInstance.setMemory(8); // 7.5GB向上取整
            } else if (machineType.contains("n1-standard-4")) {
                bootInstance.setOcpu(4);
                bootInstance.setMemory(15);
            } else {
                // 默认值
                bootInstance.setOcpu(1);
                bootInstance.setMemory(4);
            }
        } catch (Exception e) {
            // 设置默认值
            bootInstance.setOcpu(1);
            bootInstance.setMemory(4);
        }
    }

    /**
     * 生成Boot ID
     */
    public static String generateBootId() {
        return "gcp-" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
    }

    /**
     * 生成随机密码
     */
    private String generateRandomPassword() {
        String charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        StringBuilder password = new StringBuilder();

        // 确保包含至少一个大写字母
        password.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ".charAt((int) (Math.random() * 26)));

        // 确保包含至少一个小写字母
        password.append("abcdefghijklmnopqrstuvwxyz".charAt((int) (Math.random() * 26)));

        // 确保包含至少一个数字
        password.append("0123456789".charAt((int) (Math.random() * 10)));

        // 填充剩余长度
        for (int i = 3; i < 16; i++) {
            password.append(charset.charAt((int) (Math.random() * charset.length())));
        }

        // 打乱密码字符顺序
        char[] chars = password.toString().toCharArray();
        for (int i = 0; i < chars.length; i++) {
            int randomIndex = (int) (Math.random() * chars.length);
            char temp = chars[i];
            chars[i] = chars[randomIndex];
            chars[randomIndex] = temp;
        }

        return new String(chars);
    }

    /**
     * 获取租户的GCP实例列表
     */
    public List<OtherBootInstance> getGcpInstancesByTenant(Long tenantId) {
        return otherBootInstanceRepository.findByTenantIdAndCloudType(tenantId, CloudTypeEnum.GOOGLE_CLOUD.getType());
    }

    /**
     * 删除GCP实例
     */
    @Transactional
    public void deleteGcpInstance(String bootId) {
        OtherBootInstance instance = null;
        try {
            instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
            if (instance != null) {
                Long tenantId = instance.getTenantId();
                Tenant byId = tenantService.getById(tenantId);
                if (byId != null){
                    String projectId = byId.getTenancy();
                    String credentialsPath = byId.getKeyFile();
                    // 从备注中解析实例名称和区域
                    String instanceName = instance.getInstanceName();
                    String zone = instance.getZone();

                    OperationResponse operationResponse = gcpApiUtil.deleteInstance(projectId, zone, instanceName, credentialsPath);
                    log.info("GCP实例删除结果: {}", JSON.toJSONString(operationResponse ));
                    /*if (instanceName != null && zone != null) {
                        // 调用GCP API删除实例
                        CompletableFuture.runAsync(() -> {
                            try {
                                gcpApiUtil.deleteInstance(projectId, zone, instanceName, credentialsPath);
                                log.info("GCP实例删除请求已提交: {}", instanceName);
                            } catch (Exception e) {
                                log.error("删除GCP实例失败: {}", instanceName, e);
                            }
                        });
                    }*/

                    // 从数据库中删除记录
                    otherBootInstanceRepository.delete(instance);
                    log.info("GCP实例记录已从数据库删除: {}", bootId);
                }
            }
        } catch (Exception e) {
            if (e instanceof HttpClientErrorException){
                HttpClientErrorException error = (HttpClientErrorException) e;
                if (error.getStatusCode() == HttpStatus.NOT_FOUND){
                    log.warn("GCP实例删除失败: " + "实例不存在");
                    otherBootInstanceRepository.delete(instance);
                    return;
                }
            }
            log.error("删除GCP实例失败: {}", bootId, e);
        }
    }

    /**
     * 从备注中提取实例名称
     */
    private String extractInstanceNameFromRemark(String remark) {
        try {
            if (remark != null && remark.contains("GCP实例: ")) {
                String[] parts = remark.split("GCP实例: ")[1].split(" ");
                return parts[0];
            }
        } catch (Exception e) {
            log.warn("从备注中提取实例名称失败: {}", remark);
        }
        return null;
    }

    /**
     * 从备注中提取区域
     */
    private String extractZoneFromRemark(String remark) {
        try {
            if (remark != null && remark.contains("区域: ")) {
                String[] parts = remark.split("区域: ");
                if (parts.length > 1) {
                    return parts[1].split(" ")[0];
                }
            }
        } catch (Exception e) {
            log.warn("从备注中提取区域失败: {}", remark);
        }
        return null;
    }

    /**
     * 获取租户的实例列表（分页）
     */
    public Page<OtherBootInstance> getInstancesByTenantAndCloudType(Long tenantId, Integer cloudType, Pageable pageable) {
        Page<OtherBootInstance> page = otherBootInstanceRepository.findByTenantIdAndCloudType(tenantId, cloudType, pageable);
        // 获取分页中的列表数据
        List<OtherBootInstance> instances = page.getContent();

        if (!CollectionUtils.isEmpty( instances)){
            // 修改列表中对象的某个值（示例：修改状态字段）
            instances.forEach(instance -> {
                Tenant byId = tenantService.getById(instance.getTenantId());
                if (byId != null){
                    Optional<CloudTenancy> byTenancyNameAndType = cloudTenancyRepository.findByTenancyNameAndType(byId.getTenancy(), 1);
                    if (byTenancyNameAndType.isPresent()){
                        instance.setDefName(byTenancyNameAndType.get().getDefName());
                    }else {
                        instance.setDefName("未设置");
                    }
                }else {
                    instance.setDefName("未设置");
                }
            });
        }


        return page;
    }

    public Page<OtherBootInstance> getInstancesByCloudType(Integer cloudType, Pageable pageable) {
        Page<OtherBootInstance> page = otherBootInstanceRepository.findByCloudType(cloudType, pageable);

        // 获取分页中的列表数据
        List<OtherBootInstance> instances = page.getContent();
        if (!CollectionUtils.isEmpty(instances)){
            // 修改列表中对象的某个值（示例：修改状态字段）
            instances.forEach(instance -> {
                Tenant byId = tenantService.getById(instance.getTenantId());
                if (byId != null){
                    Optional<CloudTenancy> byTenancyNameAndType = cloudTenancyRepository.findByTenancyNameAndType(byId.getTenancy(), 1);
                    if (byTenancyNameAndType.isPresent()){
                        instance.setDefName(byTenancyNameAndType.get().getDefName());
                    }else {
                        instance.setDefName("未设置");
                    }
                }else{
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
            if (instance != null){
                Tenant tenant = tenantService.getById(instance.getTenantId());
                if (tenant != null){
                    String projectId = tenant.getTenancy();
                    String credentialsPath = tenant.getKeyFile();
                    instanceName = instance.getInstanceName();
                    InstanceInfo instanceInfo = gcpApiUtil.getInstance(projectId, instance.getZone(), instance.getInstanceName(), credentialsPath);

                    if (instanceInfo != null && "RUNNING".equals(instanceInfo.getStatus())) {
                        // 获取外部IP
                        String externalIp = extractExternalIp(instanceInfo);
                        updateInstanceStatus(bootId, 2, externalIp, "实例已启动");
                        log.info("GCP实例已启动: {} IP: {}", instanceName, externalIp);
                    } else {
                        updateInstanceStatus(bootId, 1, "实例启动中");
                    }
                }
            }
        } catch (Exception e) {
            if (e instanceof HttpClientErrorException){
                HttpClientErrorException error = (HttpClientErrorException) e;
                if (error.getStatusCode() == HttpStatus.NOT_FOUND){
                    otherBootInstanceRepository.delete( instance);
                    return HttpStatus.NOT_FOUND.toString();
                }
            }
        }
        return "SUCCESS";
    }

    /**
    * 切换实例ip
    */
    @Transactional
    public String changeIp(String bootId) {
        OtherBootInstance instance = otherBootInstanceRepository.findByBootIdAndCloudType(bootId, CloudTypeEnum.GOOGLE_CLOUD.getType());
        if (instance != null && instance.getStatus() == 2) {
            Tenant tenant = tenantService.getById(instance.getTenantId());
            if (tenant != null){
                String projectId = tenant.getTenancy();
                String credentialsPath = tenant.getKeyFile();
                String instanceName = instance.getInstanceName();
                try {
                    Map<String, Object> stringObjectMap = gcpApiUtil.switchInstanceExternalIp(projectId, instance.getZone(), instanceName, credentialsPath);
                    String newExternalIp = (String) stringObjectMap.get("newExternalIp");
                    if (newExternalIp != null){
                        instance.setPublicIp(newExternalIp);
                    }
                    otherBootInstanceRepository.save( instance);
                } catch (Exception e) {
                    log.error("切换ip失败D");
                    return "FAIL";
                }
            }
        }
        return "SUCCESS";

    }
}
