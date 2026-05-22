package com.doubledimple.ociserver.service.oracle.impl;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.CloudTenancy;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.CloudTenancyRepository;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.template.MessageTemplate;
import com.doubledimple.ocicommon.utils.DateTimeUtils;
import com.doubledimple.ociserver.config.annotations.UseSocksProxy;
import com.doubledimple.ociserver.config.task.PingConnTimeTask;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.IpVnicSwitchRequest;
import com.doubledimple.ociserver.pojo.request.SysImageBackupRequest;
import com.doubledimple.ociserver.service.DnsRecordService;
import com.doubledimple.ociserver.service.InstanceDetailsService;
import com.doubledimple.ociserver.service.oracle.OciStartComputeHelper;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.pojo.request.IpSwitchRequest;
import com.doubledimple.ociserver.pojo.request.SecurityRuleDTO;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.pojo.response.InstanceTrafficVO;
import com.doubledimple.ociserver.pojo.response.OciGroupResp;
import com.doubledimple.ociserver.service.OciIpRangeService;
import com.doubledimple.ociserver.service.OciSshConnService;
import com.doubledimple.ociserver.service.SecurityRuleService;
import com.doubledimple.ociserver.utils.oracle.OciIpv6Utils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.AuthenticationDetailsProvider;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.ComputeWaiters;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.*;
import com.oracle.bmc.core.requests.*;
import com.oracle.bmc.core.responses.*;
import com.oracle.bmc.http.client.jersey.JerseyHttpProvider;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.AddUserToGroupDetails;
import com.oracle.bmc.identity.model.Compartment;
import com.oracle.bmc.identity.model.CreateUserDetails;
import com.oracle.bmc.identity.requests.AddUserToGroupRequest;
import com.oracle.bmc.identity.requests.CreateOrResetUIPasswordRequest;
import com.oracle.bmc.identity.requests.CreateUserRequest;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import com.oracle.bmc.identity.requests.ListGroupsRequest;
import com.oracle.bmc.identity.requests.ListUsersRequest;
import com.oracle.bmc.identity.responses.CreateOrResetUIPasswordResponse;
import com.oracle.bmc.identity.responses.CreateUserResponse;
import com.oracle.bmc.identity.responses.ListCompartmentsResponse;
import com.oracle.bmc.identity.responses.ListGroupsResponse;
import com.oracle.bmc.identity.responses.ListUsersResponse;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeanUtils;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.util.StringUtils;

import javax.annotation.Resource;
import javax.persistence.criteria.Predicate;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadLocalRandom;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.enums.ProviderType.getAllProviders;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE;
import static com.doubledimple.ocicommon.utils.JschUtils.enableRootLogin;
import static com.doubledimple.ociserver.config.constant.GenPojoUtils.bootPojo;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.resetInstance;
import static com.oracle.bmc.core.model.ClusterNetworkSummary.LifecycleState.Running;
import static com.oracle.bmc.core.model.ClusterNetworkSummary.LifecycleState.Stopped;
import static com.oracle.bmc.core.model.CreatePublicIpDetails.Lifetime.Ephemeral;

/**
 * @author doubleDimple
 * @date 2024:10:27日 14:23
 */
@Service
@Slf4j
public class OracleInstanceServiceImpl implements OracleInstanceService {

    private static int maxRetries = 20;

    private static final String IPV6_NETWORKS_CIDR = "::/0";

    private static final String BOOT_VOLUME_NAME = "(Boot Volume)";

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OciClassLoader ociClassLoader;

    @Resource
    @Lazy
    private MessageFactory messageFactory;

    @Resource
    private OciIpRangeService ociIpRangeService;

    @Resource
    OciSshConnService ociSshConnService;

    @Resource
    SecurityRuleService securityRuleService;

    @Resource
    InstanceDetailsService instanceDetailsService;

    @Resource
    CloudSshConnRepository cloudSshConnRepository;

    @Resource
    CloudTenancyRepository cloudTenancyRepository;

    @Resource
    @Lazy
    DnsRecordService dnsRecordService;

    @Resource
    private ApplicationEventPublisher eventPublisherChangeIp;

    @Resource
    ScheduledThreadPoolExecutor delayedTaskExecutor;

    @Resource
    PingConnTimeTask pingConnTimeTask;


    private final Map<String, String> ipSwitchTasks = new ConcurrentHashMap<>();



    /**
     * 查询所有租户的实例信息
     * @return
     */
    @Override
    public List<Instance> getAllInstances(AuthenticationDetailsProvider provider) {
        List<Instance> allInstances = new ArrayList<>();
        JerseyHttpProvider httpProvider = JerseyHttpProvider.getInstance();
        // 首先获取所有compartments
        try(IdentityClient identityClient = IdentityClient.builder()
                .httpProvider(httpProvider)
                .build(provider);
            ComputeClient computeClient = ComputeClient.builder()
                    .httpProvider(httpProvider)
                    .build(provider)){


            ListCompartmentsRequest listCompartmentsRequest = ListCompartmentsRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                    .compartmentIdInSubtree(true)
                    .lifecycleState(Compartment.LifecycleState.Active)
                    .build();

            ListCompartmentsResponse compartmentsResponse = identityClient.listCompartments(listCompartmentsRequest);

            // 遍历每个compartment获取实例
            List<String> compartmentIds = new ArrayList<>();
            compartmentIds.add(provider.getTenantId()); // 添加根compartment
            compartmentsResponse.getItems().forEach(c -> compartmentIds.add(c.getId()));

            for (String compartmentId : compartmentIds) {
                ListInstancesRequest listRequest = ListInstancesRequest.builder()
                        .compartmentId(compartmentId)
                        //.lifecycleState(Instance.LifecycleState.Running)
                        .build();

                ListInstancesResponse response = computeClient.listInstances(listRequest);
                allInstances.addAll(response.getItems());

                // 处理分页
                String nextPage = response.getOpcNextPage();
                while (nextPage != null) {
                    listRequest = ListInstancesRequest.builder()
                            .compartmentId(compartmentId)
                            .page(nextPage)
                            .build();
                    response = computeClient.listInstances(listRequest);
                    allInstances.addAll(response.getItems());
                    nextPage = response.getOpcNextPage();
                }
            }
        } catch (Exception e) {
            log.warn("获取实例列表失败: {}", e.getMessage());
        }
        return allInstances;
    }

    // 获取指定区域的实例
    public List<Instance> getInstancesByRegion(AuthenticationDetailsProvider provider, String region) {
        List<Instance> instances = new ArrayList<>();

        try (ComputeClient computeClient = ComputeClient.builder()
                .httpProvider(JerseyHttpProvider.getInstance())
                .region(region)
                .build(provider)) {

            ListInstancesRequest listRequest = ListInstancesRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .build();

            ListInstancesResponse response = computeClient.listInstances(listRequest);
            instances.addAll(response.getItems());

            // 处理分页
            String nextPage = response.getOpcNextPage();
            while (nextPage != null) {
                listRequest = ListInstancesRequest.builder()
                        .compartmentId(provider.getTenantId())
                        .page(nextPage)
                        .build();
                response = computeClient.listInstances(listRequest);
                instances.addAll(response.getItems());
                nextPage = response.getOpcNextPage();
            }
        } catch (Exception e) {
            log.error("获取区域 {} 的实例列表失败: {}", region, e.getMessage(), e);
        }

        return instances;
    }

    // 获取实例详细信息的方法
    public void printInstanceDetails(Instance instance) {
        log.info("Instance Details:");
        log.info("ID: {}", instance.getId());
        log.info("Name: {}", instance.getDisplayName());
        log.info("State: {}", instance.getLifecycleState());
        log.info("Shape: {}", instance.getShape());
        log.info("Time Created: {}", instance.getTimeCreated());
        log.info("Availability Domain: {}", instance.getAvailabilityDomain());
        log.info("Fault Domain: {}", instance.getFaultDomain());
        log.info("Compartment ID: {}", instance.getCompartmentId());



        // 获取实例的标签
        if (instance.getFreeformTags() != null) {
            log.info("Freeform Tags:");
            instance.getFreeformTags().forEach((key, value) ->
                    log.info("  {}: {}", key, value));
        }

        if (instance.getDefinedTags() != null) {
            log.info("Defined Tags:");
            instance.getDefinedTags().forEach((namespace, tags) -> {
                log.info("  Namespace: {}", namespace);
                tags.forEach((key, value) ->
                        log.info("    {}: {}", key, value));
            });
        }
    }


    /*public List<InstanceDetails> listAllInstances(AuthenticationDetailsProvider provider,Tenant tenant) {
        List<InstanceDetails> allInstancesDetails = new ArrayList<>();
        List<Instance> instances = getAllInstances(provider);
        log.info("Found {} instances", instances.size());
        Long tenantId = tenant.getId();
        for (Instance instance : instances) {
            InstanceDetails allInstancesFullDetail = getInstancesDetails(provider, instance, tenantId);
            if (null != allInstancesFullDetail){
                allInstancesDetails.add(allInstancesFullDetail);
            }
        }
        return allInstancesDetails;
    }*/

    // 按状态过滤实例
    public List<Instance> getInstancesByState(List<Instance> instances, Instance.LifecycleState state) {
        return instances.stream()
                .filter(instance -> instance.getLifecycleState().equals(state))
                .collect(Collectors.toList());
    }

    // 按形状过滤实例
    public List<Instance> getInstancesByShape(List<Instance> instances, String shape) {
        return instances.stream()
                .filter(instance -> instance.getShape().equals(shape))
                .collect(Collectors.toList());
    }

    // 统计实例数量
    public Map<String, Long> countInstancesByState(List<Instance> instances) {
        return instances.stream()
                .collect(Collectors.groupingBy(
                        instance -> instance.getLifecycleState().toString(),
                        Collectors.counting()
                ));
    }

    @Override
    public Page<InstanceDetailsRes> getAllInstances(int page, int size, String tenantId) {
        Pageable pageable = PageRequest.of(page, size, Sort.by("tenantId").ascending());

        // 创建 Specification 用于动态查询
        Specification<InstanceDetails> specification = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();

            // 当 instanceId 不为空时添加查询条件
            if (StringUtils.hasText(tenantId)) {
                predicates.add(criteriaBuilder.equal(root.get("tenantId"), Long.parseLong(tenantId)));
            }
            return predicates.isEmpty() ? null : criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        // 使用 Specification 进行查询
        Page<InstanceDetails> content = oracleInstanceDetailRepository.findAll(specification, pageable);
        List<InstanceDetailsRes> instanceDetailsResList = new ArrayList<>();

        if (!content.getContent().isEmpty()) {
            List<InstanceDetails> contentDb = content.getContent();
            for (InstanceDetails instanceDetails : contentDb) {
                InstanceDetailsRes instanceDetailsRes = new InstanceDetailsRes();
                BeanUtils.copyProperties(instanceDetails, instanceDetailsRes);
                instanceDetailsRes.setId(instanceDetails.getId().toString());
                Optional<CloudTenancy> byTenancyNameAndType = cloudTenancyRepository.findByTenancyNameAndType(instanceDetails.getInstanceId(), 2);
                if (byTenancyNameAndType.isPresent()){
                    instanceDetailsRes.setRemark(byTenancyNameAndType.get().getDefName());
                }else {
                    instanceDetailsRes.setRemark("未设置");
                }
                // 设置默认值
                if (!StringUtils.hasText(instanceDetailsRes.getDisplayName())) {
                    instanceDetailsRes.setDisplayName("无");
                }
                if (!StringUtils.hasText(instanceDetailsRes.getIpv6Addresses())){
                    instanceDetailsRes.setIpv6Addresses("");
                }
                instanceDetailsRes.setUserName(getTenantName(instanceDetails.getTenantId()));
                instanceDetailsRes.setCpuAndMem(instanceDetailsRes.getOcpus() + "C" + instanceDetailsRes.getMemoryInGBs()+"G");
                if (!StringUtils.hasText(instanceDetails.getProcessorDescription())){
                    instanceDetailsRes.setProcessorDescription("NONE");
                }
                if (!StringUtils.hasText(instanceDetails.getArchitecture())){
                    instanceDetailsRes.setArchitecture("NONE");
                }
                //查询租户名和区域
                Optional<Tenant> byId = tenantRepository.findById(instanceDetails.getTenantId());
                if (byId.isPresent()){
                    instanceDetailsRes.setTenancyName(byId.get().getTenancyName());
                    instanceDetailsRes.setRegionName(RegionEnum.getNameSimple(byId.get().getRegion()));
                    instanceDetailsRes.setRegionCode(RegionEnum.getRegionCode(byId.get().getRegion()));
                    instanceDetailsRes.setFlagUrl(RegionEnum.getFlagUrl(byId.get().getRegion()));
                }
                if (!StringUtils.hasText(instanceDetails.getVpusPerGB())){
                    instanceDetailsRes.setVpusPerGB("0");
                }

                instanceDetailsRes.setTenantIdStr(String.valueOf(instanceDetails.getTenantId()));

                // 设置其他默认值
                setDefaultValues(instanceDetailsRes);

                instanceDetailsResList.add(instanceDetailsRes);
            }
        }

        return new PageImpl<>(instanceDetailsResList, content.getPageable(), content.getTotalElements());
    }

    private void setDefaultValues(InstanceDetailsRes instanceDetailsRes) {
        if (instanceDetailsRes.getBootVolumeSizeInGBs() == null) {
            instanceDetailsRes.setBootVolumeSizeInGBs(0L);
        }
        if (instanceDetailsRes.getPublicIps() == null) {
            instanceDetailsRes.setPublicIps("0.0.0.0");
        }
        if (instanceDetailsRes.getPrivateIps() == null) {
            instanceDetailsRes.setPrivateIps("0.0.0.0");
        }
        if (instanceDetailsRes.getAvailabilityDomain() == null) {
            instanceDetailsRes.setAvailabilityDomain("空");
        }
    }

    /**
    * @Description: 根据tennetid分页查询
    * @Param: [java.lang.String, int, int]
    * @return: org.springframework.data.domain.Page<com.doubledimple.ociserver.response.InstanceDetailsRes>
    * @Author doubleDimple
    * @Date: 2/22/25 10:15 AM
    */
    @Override
    public Page<InstanceDetailsRes> getInstancePageByTenantId(String tenantId, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        // 使用tenantId查询并分页
        Page<InstanceDetails> content = oracleInstanceDetailRepository.getInstanceDetailPageByTenantId(Long.valueOf(tenantId), pageable);
        List<InstanceDetailsRes> instanceDetailsResList = new ArrayList<>();
        if (content.getContent().size() > 0) {
            List<InstanceDetails> contentDb = content.getContent();
            for (InstanceDetails instanceDetails : contentDb) {
                InstanceDetailsRes instanceDetailsRes = new InstanceDetailsRes();
                BeanUtils.copyProperties(instanceDetails, instanceDetailsRes);
                // id 类型不匹配（long → String），BeanUtils 会跳过，需手动赋值
                instanceDetailsRes.setId(String.valueOf(instanceDetails.getId()));

                // 设置显示名称默认值
                if (!StringUtils.hasText(instanceDetailsRes.getDisplayName())) {
                    instanceDetailsRes.setDisplayName("无");
                }

                // 获取并设置租户名称
                instanceDetailsRes.setUserName(getTenantName(instanceDetails.getTenantId()));

                // 设置引导卷大小默认值
                if (instanceDetailsRes.getBootVolumeSizeInGBs() == null) {
                    instanceDetailsRes.setBootVolumeSizeInGBs(0L);
                }

                // 设置公网IP默认值
                if (instanceDetailsRes.getPublicIps() == null) {
                    instanceDetailsRes.setPublicIps("0.0.0.0");
                }

                // 设置私网IP默认值
                if (instanceDetailsRes.getPrivateIps() == null) {
                    instanceDetailsRes.setPrivateIps("0.0.0.0");
                }

                // 设置可用区默认值
                if (instanceDetailsRes.getAvailabilityDomain() == null) {
                    instanceDetailsRes.setAvailabilityDomain("空");
                }

                if (instanceDetailsRes.getTimeCreated() == null){
                    instanceDetailsRes.setTimeCreated(DateTimeUtils.getCurrentDateTime());
                }

                instanceDetailsResList.add(instanceDetailsRes);
            }
            return new PageImpl<>(instanceDetailsResList, content.getPageable(), content.getTotalElements());
        } else {
            return new PageImpl<>(instanceDetailsResList, content.getPageable(), content.getTotalElements());
        }
    }

    @Override
    @Transactional
    public String enableOrRefreshIpv6(Long instanceDetailId, boolean forceNewAddress) {
        log.info("开始执行ipv6开启 instance ID: {}, force new address: {}", instanceDetailId, forceNewAddress);

        // Get instance details
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(instanceDetailId)
                .orElseThrow(() -> new RuntimeException("Instance details not found with ID: " + instanceDetailId));

        long tenantId = instanceDetails.getTenantId();
        String instanceId = instanceDetails.getInstanceId();

        // Get tenant information
        Tenant tenant = tenantRepository.findById(tenantId)
                .orElseThrow(() -> new RuntimeException("Tenant not found with ID: " + tenantId));

        // Load OCI configuration
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider);
             IdentityClient identityClient = IdentityClient.builder().build(provider);
             ComputeClient computeClient = ComputeClient.builder().build(provider)) {

            // Get VNIC associated with instance
            Vnic vnic = OciIpv6Utils.getVnic(computeClient, virtualNetworkClient, instanceId, compartmentId);

            // Ensure VCN has IPv6 enabled
            Vcn vcn = OciIpv6Utils.ensureVcnWithIpv6(virtualNetworkClient, compartmentId);

            // Ensure subnet has IPv6 CIDR block
            Subnet subnet = OciIpv6Utils.ensureSubnetWithIpv6(
                    virtualNetworkClient, identityClient, compartmentId, vcn.getId());

            // Ensure IPv6 internet gateway exists
            OciIpv6Utils.ensureIpv6InternetGateway(virtualNetworkClient, compartmentId, vcn.getId());

            // Enable or refresh IPv6 address
            String ipv6Address = OciIpv6Utils.enableOrRefreshVnicIpv6(
                    virtualNetworkClient, vnic.getId(), forceNewAddress);

            // Update instance details
            instanceDetails.setIpv6Addresses(ipv6Address);
            oracleInstanceDetailRepository.saveAndFlush(instanceDetails);

            //检查是否存在ipv6的协议,存在不在开启,不存在,开启下
            //检查是否存在入站协议(ingress)
            //检查是否存在出站协议(egress)
            //IPV6_NETWORKS_CIDR
            checkProtocol(tenant);

            //重新引导实例
            resetInstance(tenant,instanceId);

            log.info("IPv6 开启成功 地址: {}", ipv6Address);
            return ipv6Address;

        } catch (Exception e) {
            log.error("Failed to enable IPv6: {}", e.getMessage(), e);
            throw new RuntimeException("ipv6 开启失败,请稍后再试");
        }
    }

    private void checkProtocol(Tenant tenant) {
        try {
            List<SecurityRuleDTO> ingressRules = securityRuleService.getSecurityRules(String.valueOf(tenant.getId()), "ingress");

            Optional<SecurityRuleDTO> ipv6IngressProtocol = ingressRules.stream()
                    .filter(rule -> rule.getSource().equals(IPV6_NETWORKS_CIDR))
                    .findFirst();

            if (!ipv6IngressProtocol.isPresent()){
                log.debug("入站协议不存在,需要生成");
                securityRuleService.singleIpv6Rule(tenant);
            }
        } catch (Exception e) {
            log.error("开启协议出现异常,请稍后再试 reason:{}",e.getMessage(),e);
        }

    }

    @Override
    @Transactional
    public ResponseEntity<?> killInstance(Long instanceDetailId) {
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(instanceDetailId).get();
        long tenantId = instanceDetails.getTenantId();
        String instanceId = instanceDetails.getInstanceId();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try(ComputeClient computeClient = ComputeClient.builder().build(provider)) {

            // 创建终止实例的请求
            // preserveBootVolume设置为false表示同时删除引导卷
            TerminateInstanceRequest terminateInstanceRequest = TerminateInstanceRequest.builder()
                    .instanceId(instanceId)
                    .preserveBootVolume(false)
                    .build();

            // 发送终止请求
            computeClient.terminateInstance(terminateInstanceRequest);

            // 终止请求发送成功
            log.debug("实例终止请求已发送,实例ID: " + instanceId);
            oracleInstanceDetailRepository.deleteById(instanceDetailId);
            oracleInstanceDetailRepository.flush();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        return ResponseEntity.ok().body("success");
    }

    @Override
    public void sendCode(Long instanceDetailId,String code) {
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(instanceDetailId).get();
        long tenantId = instanceDetails.getTenantId();
        Tenant tenant = tenantRepository.findById(tenantId).get();

        try {
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE,tenant.getUserName(),instanceDetails.getDisplayName(),code));
        } catch (Exception e) {
            log.error("消息发送失败,{}", e.getMessage(),e);
        }
    }

    /**
    * @Description: 修改cpu和内存大小
    * @Param: [java.lang.String, java.lang.Integer, java.lang.Integer]
    * @return: void
    * @Author doubleDimple
    * @Date: 11/25/24 12:46 PM
    */
    @Override
    public void updateInstanceConfig(String instanceDetailId, Integer cpu, Integer memory) {
        log.info("Updating instance configuration - instanceId: {}, cpu: {}, memory: {}GB",
                instanceDetailId, cpu, memory);
        Long aLong = Long.valueOf(instanceDetailId);
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(aLong).get();
        long tenantId = instanceDetails.getTenantId();
        String instanceId = instanceDetails.getInstanceId();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String shape = instanceDetails.getShape();
        try(ComputeClient computeClient = ComputeClient.builder().build(provider)) {
            // 构建更新请求
            UpdateInstanceShapeConfigDetails build = UpdateInstanceShapeConfigDetails.builder()
                    .memoryInGBs(memory.floatValue())
                    .ocpus(cpu.floatValue())
                    .build();
            UpdateInstanceDetails updateInstanceDetails = UpdateInstanceDetails.builder()
                    .shape(shape)  // 使用弹性配置的形状
                    .shapeConfig(build)
                    .build();

            UpdateInstanceRequest updateInstanceRequest = UpdateInstanceRequest.builder()
                    .instanceId(instanceId)
                    .updateInstanceDetails(updateInstanceDetails)
                    .build();

            // 发送更新请求
            computeClient.updateInstance(updateInstanceRequest);
            waitForInstanceUpdate(computeClient,instanceId);
            instanceDetails.setOcpus(cpu);
            instanceDetails.setMemoryInGBs(memory);
            oracleInstanceDetailRepository.saveAndFlush(instanceDetails);
        }catch (Exception e){
            log.error("修改实例配置出现错误: {}",e.getMessage(),e);
            throw new RuntimeException("配置更新失败：" + e.getMessage(), e);
        }
    }

    @Override
    public boolean updateInstanceName(String instanceDetailId, String newName) {
        Long aLong = Long.valueOf(instanceDetailId);
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(aLong).get();
        String bootVolumeId = instanceDetails.getBootVolumeId();
        long tenantId = instanceDetails.getTenantId();
        String instanceId = instanceDetails.getInstanceId();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try(ComputeClient computeClient = ComputeClient.builder().build(provider);
            BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            // 构建OCI更新请求
            UpdateInstanceDetails updateInstanceDetails = UpdateInstanceDetails.builder()
                    .displayName(newName)
                    .build();

            // 构建请求
            UpdateInstanceRequest updateRequest = UpdateInstanceRequest.builder()
                    .instanceId(instanceId)
                    .updateInstanceDetails(updateInstanceDetails)
                    .build();

            // 发送更新请求
            computeClient.updateInstance(updateRequest);

            // 等待实例更新完成
            waitForInstanceUpdate(computeClient, instanceId);
            log.info("实例名称更新成功: {} -> {}", instanceId, newName);
            instanceDetails.setDisplayName(newName);
            oracleInstanceDetailRepository.saveAndFlush(instanceDetails);

            //修改实例名称的同时修改引导卷名称
            String bootVolumeName = newName + BOOT_VOLUME_NAME;
            UpdateBootVolumeDetails.Builder updateDetailsBuilder = UpdateBootVolumeDetails.builder();
            updateDetailsBuilder.displayName(bootVolumeName);

            UpdateBootVolumeDetails updateDetails = updateDetailsBuilder.build();

            UpdateBootVolumeRequest updateBootVolumeRequest = UpdateBootVolumeRequest.builder()
                    .bootVolumeId(bootVolumeId)
                    .updateBootVolumeDetails(updateDetails)
                    .build();
            blockstorageClient.updateBootVolume(updateBootVolumeRequest);
            return true;
        }catch (Exception e){
            log.error("修改实例名称出现异常,{}",e.getMessage(),e);
            return false;
        }

    }

    /**
    * 缩小引导卷
    */
    @Override
    public ResponseEntity<ApiResponse> handleShrink(String instanceDetailId, Long diskNum) {
        return ResponseEntity.ok().body(ApiResponse.builder().success(true).message("success").build());
    }

    /**
    * 出创普通用户
    */
    @Override
    public String createOciUser(Long tenantId,String username,String email) {
        return createBaseOciUser(tenantId, username, email, "oci-start-create-user");
    }

    /**
    * 创建管理员用户
    */
    @Override
    public String createOciAdminUser(Long tenantId, String username, String email,String groupId) {
        String password = createBaseOciUser(tenantId, username, email, "oci-admin-user");

        // 添加到管理员组
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try(IdentityClient identityClient = IdentityClient.builder().build(provider)) {
            // 查找用户ID
            ListUsersRequest listUsersRequest = ListUsersRequest.builder()
                    .compartmentId(compartmentId)
                    .name(username)
                    .build();
            ListUsersResponse listUsersResponse = identityClient.listUsers(listUsersRequest);
            String userId = listUsersResponse.getItems().get(0).getId();

            // 查找Administrators组
            if (groupId != null) {
                // 将用户添加到Administrators组
                addUserToGroup(identityClient, userId, groupId);
                log.info("用户 {} 已添加到Administrators组", username);
            } else {
                log.error("未找到Administrators组");
                throw new RuntimeException("未找到Administrators组");
            }
        } catch (Exception e) {
            log.error("将用户添加到管理员组时出错:", e);
            throw new RuntimeException(e);
        }

        return password;
    }

    @Override
    public List<OciGroupResp> findGroup(Long tenantId) {
        List<OciGroupResp> groupRespList = new ArrayList<>();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try(IdentityClient identityClient = IdentityClient.builder().build(provider)) {
            ListGroupsRequest listRequest = ListGroupsRequest.builder()
                    .compartmentId(compartmentId)
                    .build();

            ListGroupsResponse listResponse = identityClient.listGroups(listRequest);

            if (!listResponse.getItems().isEmpty()) {
                listResponse.getItems().forEach(group -> {
                    OciGroupResp ociGroupResp = new OciGroupResp();
                    ociGroupResp.setGroupId(group.getId());
                    ociGroupResp.setGroupName(group.getName());
                    groupRespList.add(ociGroupResp);
                });

            }
        }catch (Exception e){
            log.error("查询用户组时出错:", e);
            throw new RuntimeException(e);
        }
        return groupRespList;
    }


    /**
     * 创建基础OCI用户并返回密码
     */
    private String createBaseOciUser(Long tenantId, String username, String email, String description) {
        String password = "";
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();
        String userId = "";

        try(IdentityClient identityClient = IdentityClient.builder().build(provider)) {
            // 1. 创建用户
            CreateUserDetails createUserDetails = CreateUserDetails.builder()
                    .compartmentId(compartmentId)
                    .name(username)
                    .email(email)
                    .description(description)
                    .build();

            CreateUserRequest request = CreateUserRequest.builder()
                    .createUserDetails(createUserDetails)
                    .build();

            CreateUserResponse response = identityClient.createUser(request);
            userId = response.getUser().getId();

            // 设置初始密码
            CreateOrResetUIPasswordResponse orResetUIPassword = identityClient.createOrResetUIPassword(
                    CreateOrResetUIPasswordRequest
                            .builder()
                            .userId(userId)
                            .build());
            password = orResetUIPassword.getUIPassword().getPassword();
            log.info("创建用户:{} 的初始密码是:{}", username, password);

            return password;
        } catch (Exception e) {
            log.error("创建用户时出错:", e);
            throw new RuntimeException(e);
        }
    }

    // 将用户添加到组
    private void addUserToGroup(IdentityClient identityClient, String userId, String groupId) {
        try {
            AddUserToGroupDetails addUserToGroupDetails = AddUserToGroupDetails.builder()
                    .userId(userId)
                    .groupId(groupId)
                    .build();

            AddUserToGroupRequest addUserToGroupRequest = AddUserToGroupRequest.builder()
                    .addUserToGroupDetails(addUserToGroupDetails)
                    .build();

            identityClient.addUserToGroup(addUserToGroupRequest);
        } catch (Exception e) {
            log.error("将用户添加到组时出错:", e);
            throw new RuntimeException(e);
        }
    }

    /**
    * @Description: 修改备注
    * @Param: [java.lang.Long, java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 2/16/25 10:55 AM
    */
    @Override
    @Transactional
    public void updateRemark(Long instanceDetailId, String remark) {
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(instanceDetailId).get();
        if (null != instanceDetails){
            Optional<CloudTenancy> byTenancyName = cloudTenancyRepository.findByTenancyNameAndType(instanceDetails.getInstanceId(), 2);
            if (byTenancyName.isPresent()){
                CloudTenancy cloudTenancy = byTenancyName.get();
                cloudTenancy.setDefName(remark);
                cloudTenancyRepository.save(cloudTenancy);
            }else{
                CloudTenancy cloudTenancy = new CloudTenancy();
                cloudTenancy.setTenancyName(instanceDetails.getInstanceId());
                cloudTenancy.setCloudType(1);
                cloudTenancy.setType(2);
                cloudTenancy.setDefName(remark);
                cloudTenancyRepository.save(cloudTenancy);
            }
            log.info("实例 {} 备注更新成功", instanceDetailId);
        }
    }

    @Override
    @Transactional
    public void getInstanceDetails(List<InstanceTrafficVO> collect) {
        try {
            for (InstanceTrafficVO instanceTrafficVO : collect) {
                String tenancy = instanceTrafficVO.getTenancy();
                String instanceId = instanceTrafficVO.getInstanceId();
                //先查询同步过的实例是否存在该实例
                InstanceDetails byInstanceId = oracleInstanceDetailRepository.findByInstanceId(instanceId);
                if (null != byInstanceId){
                    instanceTrafficVO.setPublicIp(byInstanceId.getPublicIps());
                    instanceTrafficVO.setDisplayName(byInstanceId.getDisplayName());
                    instanceTrafficVO.setState(byInstanceId.getState());
                    instanceTrafficVO.setPrivateIp(byInstanceId.getPrivateIps());
                }else{
                    List<Tenant> tenantList = tenantRepository.findByTenancyAndNoParent(tenancy);
                    if (tenantList.size() > 0){
                        Tenant tenant = tenantList.get(0);
                        setDetailByInstanceId(tenant, instanceId, instanceTrafficVO);
                        //todo 需要保存不
                        //oracleInstanceDetailRepository.saveAndFlush(instanceDetails);
                    }
                }
            }
        } catch (Exception e) {
            log.warn("查询当前的实例详细信息出现异常,实例被终止或无权限");
        }
    }

    /**
    * 停止实例
    */
    @Override
    @Transactional
    public void stopInstance(String instanceId, String tenancy) {
        List<Tenant> byTenancy = tenantRepository.findByTenancy(tenancy);
        if (byTenancy.size() > 0){
            Tenant tenant = byTenancy.get(0);
            SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
            try(ComputeClient computeClient = ComputeClient.builder().build(provider)) {
                 InstanceDetails byInstanceId = oracleInstanceDetailRepository.findByInstanceId(instanceId);
                 if (null != byInstanceId){
                     if (byInstanceId.getState().equalsIgnoreCase(Running.getValue())){
                        computeClient.instanceAction(
                                InstanceActionRequest.builder()
                                        .instanceId(instanceId)
                                        .action("STOP")
                                        .build());

                        byInstanceId.setState(Stopped.getValue());
                        oracleInstanceDetailRepository.saveAndFlush(byInstanceId);
                     }
                 }else{
                     computeClient.instanceAction(
                             InstanceActionRequest.builder()
                                     .instanceId(instanceId)
                                     .action("STOP")
                                     .build()
                     );
                 }
            }catch (Exception e){
                log.error("停止实例失败,原因为:{}",e.getMessage(), e);
            }
        }

    }


    @Override
    public boolean stopInstanceByInstanceId(String id) {
        Optional<InstanceDetails> optionalInstanceDetails = oracleInstanceDetailRepository.findById(Long.valueOf(id));
        if (optionalInstanceDetails.isPresent()){
            InstanceDetails instanceDetails = optionalInstanceDetails.get();
            String instanceId = instanceDetails.getInstanceId();
            Optional<Tenant> byId = tenantRepository.findById(instanceDetails.getTenantId());
            if (byId.isPresent()){
                stopInstance(instanceId, byId.get().getTenancy());
            }
        }
        return true;
    }

    @Override
    public boolean startInstance(String id) {
        Optional<InstanceDetails> optionalInstanceDetails = oracleInstanceDetailRepository.findById(Long.valueOf(id));

        if (optionalInstanceDetails.isPresent()){
            InstanceDetails instanceDetails = optionalInstanceDetails.get();
            String instanceId = instanceDetails.getInstanceId();
            Optional<Tenant> byId = tenantRepository.findById(instanceDetails.getTenantId());
            if (byId.isPresent()){
                Tenant tenant = byId.get();
                SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
                try(ComputeClient computeClient = ComputeClient.builder().build(provider)) {
                        if (instanceDetails.getState().equalsIgnoreCase(Stopped.getValue())){
                            computeClient.instanceAction(
                                    InstanceActionRequest.builder()
                                            .instanceId(instanceId)
                                            .action("START")
                                            .build());
                            instanceDetails.setState(Running.getValue());
                            oracleInstanceDetailRepository.saveAndFlush(instanceDetails);
                        }
                }catch (Exception e){
                    log.error("停止实例失败,原因为:{}",e.getMessage(), e);
                }
            }
        }
        return true;
    }

    @Override
    public InstanceDetails getInstanceByInstanceId(String instanceId) {
        return oracleInstanceDetailRepository.findByInstanceId(instanceId);
    }

    @Override
    public void updateInstance(InstanceDetails instance) {
        log.info("保存SSH配置,请求参数是:{}", JSONUtil.toJsonStr(instance));
        ociSshConnService.saveOrUpdate(instance);

    }

    @Override
    public InstanceDetails getInstanceById(Long valueOf) {
        return oracleInstanceDetailRepository.findById(valueOf).get();
    }

    /**
    * 系统备份镜像
    */
    @Override
    public ResponseEntity<?> sysImageBackUp(SysImageBackupRequest sysImageBackupRequest) {
        InstanceDetails instanceDetails = getInstanceById(sysImageBackupRequest.getInstanceId());
        Optional<CloudSshConn> byInstanceId = cloudSshConnRepository.findByInstanceId(String.valueOf(instanceDetails.getInstanceId()));
        if (byInstanceId.isPresent()){
            Optional<Tenant> byId = tenantRepository.findById(instanceDetails.getTenantId());
            User user = bootPojo(byId.get(), instanceDetails.getArchitecture());
            CloudSshConn cloudSshConn = byInstanceId.get();
            instanceDetails.setUsername("root");
            instanceDetails.setPort(22);
            instanceDetails.setPassword(cloudSshConn.getPassword());
            //对实例执行一次连接测试
            ScriptResult root = enableRootLogin(instanceDetails.getPublicIps(), "root", instanceDetails.getPassword(), instanceDetails.getPassword(), 22);
            if (root.isSuccess()){
                log.debug("root用户登录成功");
                instanceDetailsService.doBootVolumeBackUpNoAuth(instanceDetails, user, instanceDetails.getBootVolumeId());
                //备份成功,修改实例详情的备份状态
                instanceDetails.setSysImageBackup(1);
                oracleInstanceDetailRepository.save(instanceDetails);
            }else {
                ResponseEntity.BodyBuilder builder = ResponseEntity.status(HttpStatus.NOT_FOUND);
                builder.body("当前实例通过ssh连接错误,无法执行备份操作,请检查实例密码以及状态");
                return builder.build();
            }
        }else{
            ResponseEntity.BodyBuilder builder = ResponseEntity.status(HttpStatus.NOT_FOUND);
            builder.body("实例密码不存在,请先将实例在本面板平台进行一次ssh连接测试后再次备份");
            return builder.build();
        }
        return ResponseEntity.ok().build();
    }

    @Override
    public ResponseEntity<?> switchVnicToSpecificIpRange(IpVnicSwitchRequest request) {
        Map<String, Object> result = new HashMap<>();
        List<String> cidrList = request.getCidrRanges();
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findByInstanceId(request.getInstanceId());
        String instanceId = instanceDetails.getInstanceId();
        String publicIpsDb = instanceDetails.getPublicIps();
        Tenant tenant = tenantRepository.findById(instanceDetails.getTenantId()).get();

        //如果cidr不为空,检测cidr是不是输入正确
        List<String> cidrs = ociIpRangeService.findCidrsByRegionAndCidrIn(tenant.getRegion(), cidrList);
        if (cidrs.size() == 0){
            log.info("当前用户:{} 的实例:{} 填写的cidr全部错误,未在指定区域: {} 找到,已切换为随机生成",tenant.getUserName(),instanceId,tenant.getRegion());
        }
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        try(VirtualNetworkClient vnClient = VirtualNetworkClient.builder().build(provider);
            ComputeClient computeClient = ComputeClient.builder().build(provider)) {

            if (ipSwitchTasks.containsKey(instanceId)){
                log.warn("当前用户:{} 的实例:{} 已有任务在切换ip中,不要再次点击",tenant.getUserName(),instanceId);
                result.put("status", "error");
                result.put("message", "IP切换失败: " + "API 权限不足,无法切换IP,请在控制台添加相关权限");
                return ResponseEntity.badRequest().body(result);
            }else{
                ipSwitchTasks.put(instanceId,instanceId);
            }


            String newPublicIp = "";
            Vnic vnic = getVnicById(request.getVnicId(),computeClient,provider,vnClient);
            if (CollectionUtils.isEmpty(cidrs)){
                newPublicIp = reassignEphemeralPublicIp(vnic,vnClient,provider.getTenantId());
                // 9. 构建成功响应
                Map<String, String> details = new HashMap<>();
                details.put("oldIp", publicIpsDb);
                details.put("newIp", newPublicIp);

                result.put("status", "success");
                result.put("message", "IP切换成功");
                result.put("details", details);
                instanceDetails.setPublicIps(newPublicIp);
                oracleInstanceDetailRepository.saveAndFlush(instanceDetails);
                ipSwitchTasks.remove(instanceId);

                //发消息
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MessageTemplate.MESSAGE_CONFIG_IP_SWITCH_TEMPLATE,tenant.getUserName(),instanceId,publicIpsDb,newPublicIp));
                return ResponseEntity.ok(result);
            }

            // 循环尝试获取符合 CIDR 范围的 IP
            int retryCount = 0;

            do {
                try {
                    newPublicIp = reassignEphemeralPublicIp(vnic, vnClient, provider.getTenantId());
                    int randomIntInterval = ThreadLocalRandom.current().nextInt(60 * 1000, 80 * 1000);

                    if (!OciUtils.isIpInCidrList(newPublicIp, cidrs)) {
                        log.warn("用户：[{}] 的 实例：[{}] ，获取到的IP：{} 不在给定的 CIDR 网段中，{} 秒后将继续更换公共IP...",
                                tenant.getUserName(), instanceId,
                                newPublicIp, randomIntInterval / 1000);
                    } else {
                        ipSwitchTasks.remove(instanceId);

                        instanceDetails.setPublicIps(newPublicIp);
                        oracleInstanceDetailRepository.saveAndFlush(instanceDetails);

                        // 构建成功响应
                        Map<String, String> details = new HashMap<>();
                        details.put("oldIp", publicIpsDb);
                        details.put("newIp", newPublicIp);

                        result.put("status", "success");
                        result.put("message", "IP切换成功");
                        result.put("details", details);
                        break;
                    }

                    Thread.sleep(randomIntInterval);
                } catch (InterruptedException e) {
                    throw new RuntimeException(e);
                } catch (BmcException ociException) {
                    log.error("用户：[{}] ，区域：[{}] ，实例：[{}] ，更换公共IP失败，原因：{}",
                            tenant.getUserName(), tenant.getRegion(), instanceId,
                            ociException.getMessage());
                }

                retryCount++; // 增加重试次数
            } while (retryCount < maxRetries
                    && !OciUtils.isIpInCidrList(newPublicIp, cidrs)
                    && ipSwitchTasks.get(instanceId) != null);

            if (retryCount >= maxRetries) {
                log.error("用户：[{}] 的 实例：[{}] ，已达到最大重试次数 [{}] 次，停止更换IP。",
                        tenant.getUserName(), instanceId, maxRetries);
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            ipSwitchTasks.remove(instanceId);
            log.warn("当前用户:{} 的实例:{} 执行失败.....,原因为:{}",tenant.getUserName(),instanceId,e.getMessage(),e);
            result.put("status", "error");
            result.put("message", "IP切换失败: {}"+e.getMessage());
            return ResponseEntity.badRequest().body(result);
        }
    }

    @Override
    @Transactional
    public ApiResponse enablePing(int cloudType) {
        try {
            // 批量更新指定cloudType的所有实例，将enablePing设置为1
            int updatedCount = oracleInstanceDetailRepository.updateEnablePingByCloudType(cloudType, 1);

            if (updatedCount > 0) {
                return ApiResponse.success("成功启用 " + updatedCount + " 个实例的Ping检测");
            } else {
                return ApiResponse.error("未找到cloudType为 " + cloudType + " 的实例");
            }
        } catch (Exception e) {
            return ApiResponse.error("启用Ping检测失败：" + e.getMessage());
        }
    }

    @Override
    @Transactional
    public ApiResponse disablePing(int cloudType) {
        try {
            // 批量更新指定cloudType的所有实例，将enablePing设置为0
            int updatedCount = oracleInstanceDetailRepository.updateEnablePingByCloudType(cloudType, 0);

            if (updatedCount > 0) {
                return ApiResponse.success("成功关闭 " + updatedCount + " 个实例的Ping检测");
            } else {
                return ApiResponse.error("未找到cloudType为 " + cloudType + " 的实例");
            }
        } catch (Exception e) {
            return ApiResponse.error("关闭Ping检测失败：" + e.getMessage());
        }
    }

    @Override
    public ApiResponse batchPing(int i) {
        pingConnTimeTask.batchPing();
        return ApiResponse.success("批量ping成功");
    }

    private Vnic getVnicById(String vnicId,ComputeClient computeClient,SimpleAuthenticationDetailsProvider provider,VirtualNetworkClient vnClient) {
        // 4. 获取实例的VNIC信息
        ListVnicAttachmentsRequest listVnicRequest = ListVnicAttachmentsRequest.builder()
                .compartmentId(provider.getTenantId())
                .vnicId(vnicId)
                .build();

        Vnic vnic = null;
        ListVnicAttachmentsResponse listVnicAttachmentsResponse = computeClient.listVnicAttachments(listVnicRequest);
        List<VnicAttachment> items = listVnicAttachmentsResponse.getItems();
        for (VnicAttachment item : items) {
            try {
                GetVnicRequest getVnicRequest =
                        GetVnicRequest.builder().vnicId(item.getVnicId()).build();
                GetVnicResponse getVnicResponse = vnClient.getVnic(getVnicRequest);
                vnic = getVnicResponse.getVnic();

            } catch (Exception e) {
                log.debug("当前vnic获取失败");
            }
        }
        return vnic;
    }

    /**
    * 根据instanceid设置值
    */
    private InstanceDetails setDetailByInstanceId(Tenant tenant, String instanceId,InstanceTrafficVO instanceTrafficVO) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        InstanceDetails details = getInstanceDetails(provider, instanceId, provider.getTenantId());
        instanceTrafficVO.setPublicIp(details.getPublicIps());
        instanceTrafficVO.setDisplayName(details.getDisplayName());
        instanceTrafficVO.setState(details.getState());
        instanceTrafficVO.setPrivateIp(details.getPrivateIps());
        return details;
    }

    /**
    * @Description: 扩容
    * @Param: [java.lang.String, java.lang.Long]
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author doubleDimple
    * @Date: 11/26/24 7:13 PM
    */
    @Override
    @Transactional
    public ResponseEntity<ApiResponse> handleExpansion(String instanceDetailId, Long bootVolumeSize) {
        Long aLong = Long.valueOf(instanceDetailId);
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(aLong).get();
        long tenantId = instanceDetails.getTenantId();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try(ComputeClient computeClient = ComputeClient.builder().build(provider);
                BlockstorageClient blockstorageClient = BlockstorageClient.builder().build(provider)) {
            // 获取实例信息
            GetInstanceResponse instanceResponse = computeClient.getInstance(
                    GetInstanceRequest.builder()
                            .instanceId(instanceDetails.getInstanceId())
                            .build()
            );
            Instance instance = instanceResponse.getInstance();

            BootVolume bootVolume = OciStartComputeHelper.getBootVolume(blockstorageClient, computeClient, instance, compartmentId);

            if (null != bootVolume){
                // 直接执行扩容操作
                UpdateBootVolumeDetails updateDetails = UpdateBootVolumeDetails.builder()
                        .sizeInGBs(bootVolumeSize)
                        .build();
                blockstorageClient.updateBootVolume(
                        UpdateBootVolumeRequest.builder()
                                .bootVolumeId(bootVolume.getId())
                                .updateBootVolumeDetails(updateDetails)
                                .build());
                instanceDetails.setBootVolumeSizeInGBs(bootVolumeSize);
                oracleInstanceDetailRepository.saveAndFlush(instanceDetails);
                return ResponseEntity.ok(ApiResponse.builder().success(true).message("引导卷扩容成功").build());
            }else {
                return ResponseEntity.ok(ApiResponse.builder().success(false).message("原引导卷获取失败").build());
            }

        } catch (Exception e) {
            log.error("引导卷扩容失败", e);
            return ResponseEntity.internalServerError()
                    .body(ApiResponse.builder().success(false).message("引导卷扩容失败: " + e.getMessage()).build());
        }
    }

    private void waitForInstanceUpdate(ComputeClient computeClient, String instanceId) throws Exception {
        GetInstanceRequest getInstanceRequest = GetInstanceRequest.builder()
                .instanceId(instanceId)
                .build();

        ComputeWaiters waiters = computeClient.getWaiters();
        GetInstanceResponse response = waiters.forInstance(
                getInstanceRequest,
                Instance.LifecycleState.Running
        ).execute();
    }



    @UseSocksProxy
    @Override
    public ResponseEntity<?> checkAccountStatus(long tenantId) {
        Map<String, Object> result = new HashMap<>();
        Tenant tenant = tenantRepository.findById(tenantId).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        Map<String, String> checks = new HashMap<>();
        try(IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            try {
                // todo 暂时不做shape测活了 0. 尝试列出shape,
                /*if (!checkAllDomainsIsShapeEnabled(tenant)){
                    checks.put("shape被禁止", "异常");
                    result.put("status", "error");
                    result.put("message", "账号状态异常");
                    result.put("checks", checks);
                    return ResponseEntity.ok(result);
                }*/
                // 1. 尝试获取用户信息
                /*GetUserRequest getUserRequest = GetUserRequest.builder()
                        .userId(provider.getUserId())
                        .build();
                identityClient.getUser(getUserRequest);*/
                checks.put("认证状态", "正常");

                // 2. 尝试列出Compartments
                ListCompartmentsRequest listCompartmentsRequest = ListCompartmentsRequest.builder()
                        .compartmentId(provider.getTenantId())
                        .build();
                identityClient.listCompartments(listCompartmentsRequest);

                checks.put("Compartments访问", "正常");

                checks.put("计算服务访问", "正常");
                result.put("checks", checks);
                result.put("status","success");
            } catch (Exception e) {
                checks.put(e.getMessage(), "异常");
                result.put("status", "error");
                result.put("message", "账号状态异常");
                result.put("checks", checks);
            }

        } catch (Exception e) {
            result.put("status", "error");
            result.put("message", "检测过程发生错误: " + e.getMessage());
        }
        return ResponseEntity.ok(result);
    }

    private String getTenantName(long tenantId) {
        return tenantRepository.findById(tenantId)
                .map(Tenant::getUserName)
                .orElse("空");
    }

    public InstanceDetails getInstanceDetails(
            AuthenticationDetailsProvider provider,
            String instanceId,
            String compartmentId) {

        InstanceDetails details = new InstanceDetails();

        try(ComputeClient computeClient = ComputeClient.builder().build(provider);
            VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {

            // 获取实例信息
            GetInstanceRequest getInstanceRequest = GetInstanceRequest.builder()
                    .instanceId(instanceId)
                    .build();

            GetInstanceResponse instanceResponse = computeClient.getInstance(getInstanceRequest);
            Instance instance = instanceResponse.getInstance();

            // 设置实例名称和状态
            details.setDisplayName(instance.getDisplayName());
            details.setState(instance.getLifecycleState().getValue());


            ListVnicAttachmentsRequest listVnicAttachmentsRequest = ListVnicAttachmentsRequest.builder()
                    .compartmentId(compartmentId)
                    .instanceId(instanceId)
                    .build();

            ListVnicAttachmentsResponse vnicAttachmentsResponse = computeClient.listVnicAttachments(listVnicAttachmentsRequest);
            List<VnicAttachment> vnicAttachments = vnicAttachmentsResponse.getItems();

            // 获取VNIC详情来获取IP信息
            if (!vnicAttachments.isEmpty()) {
                String vnicId = vnicAttachments.get(0).getVnicId();

                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                        .vnicId(vnicId)
                        .build();

                GetVnicResponse vnicResponse = virtualNetworkClient.getVnic(getVnicRequest);
                Vnic vnic = vnicResponse.getVnic();

                // 设置IP地址
                details.setPublicIps(vnic.getPublicIp());
                details.setPrivateIps(vnic.getPrivateIp());
            }

        } catch (Exception e) {
            log.warn("获取实例详情时发生错误: {}",e.getMessage());
        }

        return details;
    }





    @Transactional
    @Override
    public ResponseEntity<?> changePublicIp(Long instanceDetailId) {
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(instanceDetailId).get();
        String instanceId = instanceDetails.getInstanceId();
        String publicIpsDb = instanceDetails.getPublicIps();
        Tenant tenant = tenantRepository.findById(instanceDetails.getTenantId()).get();
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        VirtualNetworkClient vnClient = VirtualNetworkClient.builder().build(provider);
        ComputeClient computeClient = ComputeClient.builder().build(provider);
        Random random = new Random(); // 用于生成随机数
        Map<String, Object> result = new HashMap<>();
        String privateIpId = "";
        try{

            // 获取实例的VNIC信息
            Vnic vnic = getVnic(computeClient,vnClient,instanceId,tenant.getTenancy());
            if (vnic == null) {
                throw new RuntimeException("未找到实例的VNIC");
            }

            String oldPublicIp = vnic.getPublicIp();

            // 获取公共IP的OCID
            ListPublicIpsRequest listRequest = ListPublicIpsRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .scope(ListPublicIpsRequest.Scope.Region)
                    .lifetime(ListPublicIpsRequest.Lifetime.Reserved)
                    .build();
            List<PublicIp> publicIps = vnClient.listPublicIps(listRequest)
                    .getItems()
                    .stream()
                    .filter(ip -> (null == oldPublicIp ? publicIpsDb : oldPublicIp).equals(ip.getIpAddress()))
                    .collect(Collectors.toList());

            if (!publicIps.isEmpty()) {
                DeletePublicIpRequest deletePublicIpRequest = DeletePublicIpRequest.builder()
                        .publicIpId(publicIps.get(0).getId())
                        .build();
                vnClient.deletePublicIp(deletePublicIpRequest);
                log.info("已删除旧的公共IP: " + oldPublicIp);

                // 等待 5 秒
                try {
                    Thread.sleep(5000); // 等待5秒
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.warn("等待删除IP的过程中被中断");
                }
            }

            // 通常返回主私有IP
            privateIpId =  getprivateIpId(vnic,vnClient);

            // 3. 创建并分配新的公共IP
            String newPublicIp = doCreatePublicIp(provider,privateIpId,vnClient);

            // 8. 更新数据库中的IP信息
            instanceDetails.setPublicIps(newPublicIp);
            oracleInstanceDetailRepository.saveAndFlush(instanceDetails);

            // 9. 构建成功响应
            Map<String, String> details = new HashMap<>();
            details.put("oldIp", publicIpsDb);
            details.put("newIp", newPublicIp);

            result.put("status", "success");
            result.put("message", "IP切换成功");
            result.put("details", details);

        }catch (Exception e){
            if (e instanceof BmcException){
                BmcException err = (BmcException) e;
                if (err.getStatusCode() == 404 && err.getServiceCode().equals("NotAuthorizedOrNotFound")){
                    log.warn("IP切换过程出错: " + "API 权限不足,无法切换IP,请在控制台添加相关权限");
                    result.put("status", "error");
                    result.put("message", "IP切换失败: " + "API 权限不足,无法切换IP,请在控制台添加相关权限");
                    return ResponseEntity.badRequest().body(result);
                }else if (err.getStatusCode() == 400 && err.getServiceCode().equalsIgnoreCase("LimitExceeded")){
                    for (int y= 0;y<5;y++){
                        try {
                            int delay = 5000 + random.nextInt(5000); // 生成 5000 到 10000 毫秒之间的随机数
                            log.info("等待 " + delay / 1000 + " 秒后继续...");
                            Thread.sleep(delay);
                        } catch (InterruptedException ex) {
                            Thread.currentThread().interrupt();
                            log.warn("创建ip的过程被中断");
                        }
                        log.info("request limit retry.....");
                        doCreatePublicIp(provider,privateIpId,vnClient);
                    }
                }
            }
            result.put("status", "error");
            result.put("message", "IP切换失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(result);
        }finally {
            vnClient.close();
            computeClient.close();
        }

        return ResponseEntity.ok(result);
    }

    @Override
    public ResponseEntity<?> changePublicIp2(Long instanceId) {
        return null;
    }

    private Vnic getVnic(ComputeClient computeClient,VirtualNetworkClient vnClient, String instanceId, String tenancy) {
        // 4. 获取实例的VNIC信息
        ListVnicAttachmentsRequest listVnicRequest = ListVnicAttachmentsRequest.builder()
                .compartmentId(tenancy)
                .instanceId(instanceId)
                .build();

        Vnic vnic = null;
        ListVnicAttachmentsResponse listVnicAttachmentsResponse = computeClient.listVnicAttachments(listVnicRequest);
        List<VnicAttachment> items = listVnicAttachmentsResponse.getItems();
        for (VnicAttachment item : items) {
            try {
                GetVnicRequest getVnicRequest =
                        GetVnicRequest.builder().vnicId(item.getVnicId()).build();
                GetVnicResponse getVnicResponse = vnClient.getVnic(getVnicRequest);
                if (getVnicResponse.getVnic().getIsPrimary()){
                    vnic = getVnicResponse.getVnic();
                }
            } catch (Exception e) {
                log.debug("当前vnic获取失败");
            }
        }
        return vnic;
    }

    private String doCreatePublicIp(SimpleAuthenticationDetailsProvider provider,String privateIpId,VirtualNetworkClient vnClient) {
        CreatePublicIpDetails createDetails = CreatePublicIpDetails.builder()
                .compartmentId(provider.getTenantId())
                .lifetime(CreatePublicIpDetails.Lifetime.Reserved)
                .privateIpId(privateIpId)
                .build();

        CreatePublicIpRequest createRequest = CreatePublicIpRequest.builder()
                .createPublicIpDetails(createDetails)
                .build();

        CreatePublicIpResponse createResponse = vnClient.createPublicIp(createRequest);
        String newPublicIp = createResponse.getPublicIp().getIpAddress();

        log.info("已创建并分配新的公共IP: " + newPublicIp);
        return newPublicIp;
    }

    @Override
    public ResponseEntity<?> switchToSpecificIpRange(IpSwitchRequest request) {
        Map<String, Object> result = new HashMap<>();
        List<String> cidrList = request.getCidrRanges();
        InstanceDetails instanceDetails = oracleInstanceDetailRepository.findById(request.getTenantId()).get();
        String instanceId = instanceDetails.getInstanceId();
        String publicIpsDb = instanceDetails.getPublicIps();
        Tenant tenant = tenantRepository.findById(instanceDetails.getTenantId()).get();

        //如果cidr不为空,检测cidr是不是输入正确
        List<String> cidrs = ociIpRangeService.findCidrsByRegionAndCidrIn(tenant.getRegion(), cidrList);
        if (cidrs.size() == 0){
            log.info("当前用户:{} 的实例:{} 填写的cidr全部错误,未在指定区域: {} 找到,已切换为随机生成",tenant.getUserName(),instanceId,tenant.getRegion());
        }
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        try(VirtualNetworkClient vnClient = VirtualNetworkClient.builder().build(provider);
            ComputeClient computeClient = ComputeClient.builder().build(provider)) {

            if (ipSwitchTasks.containsKey(instanceId)){
                log.warn("当前用户:{} 的实例:{} 已有任务在切换ip中,不要再次点击",tenant.getUserName(),instanceId);
                result.put("status", "error");
                result.put("message", "IP切换失败: " + "API 权限不足,无法切换IP,请在控制台添加相关权限");
                return ResponseEntity.badRequest().body(result);
            }else{
                ipSwitchTasks.put(instanceId,instanceId);
            }


            String newPublicIp = "";
            Vnic vnic = getVnic(computeClient, vnClient, instanceId, tenant.getTenancy());
            if (CollectionUtils.isEmpty(cidrs)){
                newPublicIp = reassignEphemeralPublicIp(vnic,vnClient,provider.getTenantId());
                // 9. 构建成功响应
                Map<String, String> details = new HashMap<>();
                details.put("oldIp", publicIpsDb);
                details.put("newIp", newPublicIp);

                result.put("status", "success");
                result.put("message", "IP切换成功");
                result.put("details", details);
                instanceDetails.setPublicIps(newPublicIp);
                oracleInstanceDetailRepository.saveAndFlush(instanceDetails);
                ipSwitchTasks.remove(instanceId);

                //拿着ip去查询dns记录
                dnsRecordService.queryDnsRecordAndRefreshAndChange(tenant,instanceId,publicIpsDb,newPublicIp, getAllProviders());

                //发消息
                //messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MessageTemplate.MESSAGE_CONFIG_IP_SWITCH_TEMPLATE,tenant.getUserName(),instanceId,publicIpsDb,newPublicIp));
                return ResponseEntity.ok(result);
            }

            // 循环尝试获取符合 CIDR 范围的 IP
            int retryCount = 0;

            do {
                try {
                    newPublicIp = reassignEphemeralPublicIp(vnic, vnClient, provider.getTenantId());
                    int randomIntInterval = ThreadLocalRandom.current().nextInt(60 * 1000, 80 * 1000);

                    if (!OciUtils.isIpInCidrList(newPublicIp, cidrs)) {
                        log.warn("用户：[{}] 的 实例：[{}] ，获取到的IP：{} 不在给定的 CIDR 网段中，{} 秒后将继续更换公共IP...",
                                tenant.getUserName(), instanceId,
                                newPublicIp, randomIntInterval / 1000);
                    } else {
                        ipSwitchTasks.remove(instanceId);

                        instanceDetails.setPublicIps(newPublicIp);
                        oracleInstanceDetailRepository.saveAndFlush(instanceDetails);

                        // 构建成功响应
                        Map<String, String> details = new HashMap<>();
                        details.put("oldIp", publicIpsDb);
                        details.put("newIp", newPublicIp);

                        result.put("status", "success");
                        result.put("message", "IP切换成功");
                        result.put("details", details);
                        break;
                    }

                    Thread.sleep(randomIntInterval);
                } catch (InterruptedException e) {
                    throw new RuntimeException(e);
                } catch (BmcException ociException) {
                    log.error("用户：[{}] ，区域：[{}] ，实例：[{}] ，更换公共IP失败，原因：{}",
                            tenant.getUserName(), tenant.getRegion(), instanceId,
                            ociException.getMessage());
                }

                retryCount++; // 增加重试次数
            } while (retryCount < maxRetries
                    && !OciUtils.isIpInCidrList(newPublicIp, cidrs)
                    && ipSwitchTasks.get(instanceId) != null);

            if (retryCount >= maxRetries) {
                log.error("用户：[{}] 的 实例：[{}] ，已达到最大重试次数 [{}] 次，停止更换IP。",
                        tenant.getUserName(), instanceId, maxRetries);
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            ipSwitchTasks.remove(instanceId);
            log.warn("当前用户:{} 的实例:{} 执行失败.....,原因为:{}",tenant.getUserName(),instanceId,e.getMessage(),e);
            result.put("status", "error");
            result.put("message", "IP切换失败: {}"+e.getMessage());
            return ResponseEntity.badRequest().body(result);
        }

    }

    private String getprivateIpId(Vnic vnic,VirtualNetworkClient vnClient) {
        ListPrivateIpsRequest listPrivateIpsRequest = ListPrivateIpsRequest.builder()
                .vnicId(vnic.getId())
                .build();

        List<PrivateIp> privateIps = vnClient.listPrivateIps(listPrivateIpsRequest)
                .getItems();

        if (privateIps.isEmpty()) {
            throw new RuntimeException("未找到VNIC关联的私有IP");
        }

        // 通常返回主私有IP
        return privateIps.get(0).getId();

    }


    /**
     * 最新的切换公共ip
     * @param vnic
     * @param virtualNetworkClient
     * @param compartmentId
     * @return
     */
    public String reassignEphemeralPublicIp(Vnic vnic,VirtualNetworkClient virtualNetworkClient,String compartmentId) {
        if (vnic == null) {
            throw new RuntimeException("当前实例的VNIC不存在");
        }
        String vnicId = vnic.getId();
        if (vnicId != null) {
            // Step 1: 解除当前的 Public IP（如果已存在）
            GetVnicRequest getVnicRequest = GetVnicRequest.builder().vnicId(vnicId).build();
            String existingPublicIpAddress = virtualNetworkClient.getVnic(getVnicRequest).getVnic().getPublicIp();
            if (existingPublicIpAddress != null) {
                // Step 1: 查找公网 IP 的 OCID
                GetPublicIpByIpAddressRequest getPublicIpByIpAddressRequest = GetPublicIpByIpAddressRequest.builder()
                        .getPublicIpByIpAddressDetails(
                                GetPublicIpByIpAddressDetails.builder()
                                        .ipAddress(existingPublicIpAddress)
                                        .build())
                        .build();

                String existingPublicIpId = virtualNetworkClient.getPublicIpByIpAddress(getPublicIpByIpAddressRequest).getPublicIp().getId();

                DeletePublicIpRequest deleteRequest = DeletePublicIpRequest.builder()
                        .publicIpId(existingPublicIpId)
                        .build();
                virtualNetworkClient.deletePublicIp(deleteRequest);
            }
        }

        try {
            String privateIpId = getprivateIpId(vnic, virtualNetworkClient);
            // Step 1: 创建一个 Reserved Public IP
            CreatePublicIpDetails createPublicIpDetails = CreatePublicIpDetails.builder()
                    .compartmentId(compartmentId)
                    .lifetime(Ephemeral)  // 设置为 Reserved
                    .displayName("oci-start-publicIp")
                    .privateIpId(privateIpId)
                    .build();
            CreatePublicIpRequest createRequest = CreatePublicIpRequest.builder()
                    .createPublicIpDetails(createPublicIpDetails)
                    .build();

            PublicIp reservedPublicIp = virtualNetworkClient.createPublicIp(createRequest).getPublicIp();
//            log.info("Reserved Public IP created: {}", reservedPublicIp.getIpAddress());

            // Step 2: 使用 UpdatePublicIpRequest 将 Reserved Public IP 关联到 VNIC
            UpdatePublicIpDetails updatePublicIpDetails = UpdatePublicIpDetails.builder()
                    .privateIpId(privateIpId)
                    .build();
            UpdatePublicIpRequest updateRequest = UpdatePublicIpRequest.builder()
                    .publicIpId(reservedPublicIp.getId())
                    .updatePublicIpDetails(updatePublicIpDetails)
                    .build();

            virtualNetworkClient.updatePublicIp(updateRequest);
//            log.info("Reserved Public IP attached to VNIC: " + reservedPublicIp.getIpAddress());
            return reservedPublicIp.getIpAddress();
        } catch (Exception e) {
            releaseUnusedPublicIps(compartmentId,virtualNetworkClient);
            throw new RuntimeException(e);
        }
    }

    public void releaseUnusedPublicIps(String compartmentId,VirtualNetworkClient virtualNetworkClient) {
        ListPublicIpsRequest listPublicIpsRequest = ListPublicIpsRequest.builder()
                .compartmentId(compartmentId)
                .scope(ListPublicIpsRequest.Scope.Region)
                .build();

        ListPublicIpsResponse response = virtualNetworkClient.listPublicIps(listPublicIpsRequest);
        for (PublicIp publicIp : response.getItems()) {
            if (publicIp.getAssignedEntityId() == null) {  // 检查是否未分配到实例
                DeletePublicIpRequest deleteRequest = DeletePublicIpRequest.builder()
                        .publicIpId(publicIp.getId())
                        .build();
                virtualNetworkClient.deletePublicIp(deleteRequest);
                log.info("Released unused Public IP: {}", publicIp.getIpAddress());
            }
        }
    }

    private void waitForVolumeDetachment(String volumeId,ComputeClient computeClient) throws InterruptedException {
        boolean detached = false;
        int attempts = 0;
        final int maxAttempts = 30;  // 最多等待30次

        while (!detached && attempts < maxAttempts) {
            try {
                GetVolumeAttachmentResponse attachmentResponse = computeClient.getVolumeAttachment(
                        GetVolumeAttachmentRequest.builder()
                                .volumeAttachmentId(volumeId)
                                .build()
                );

                if ("DETACHED".equals(attachmentResponse.getVolumeAttachment().getLifecycleState().getValue())) {
                    detached = true;
                } else {
                    Thread.sleep(10000);  // 等待10秒
                    attempts++;
                }
            } catch (BmcException e) {
                if (e.getStatusCode() == 404) {
                    // 如果找不到附加信息，说明已经分离
                    detached = true;
                } else {
                    throw e;
                }
            }
        }

        if (!detached) {
            throw new RuntimeException("等待引导卷分离超时");
        }
    }

    @Scheduled(fixedRate = 300000) // 5 minutes
    public void cleanupIpSwitchTasks() {
        ipSwitchTasks.clear();
    }

    @Override
    public ApiResponse deleteInstanceRecord(Long id) {
        try {
            if (!oracleInstanceDetailRepository.existsById(id)) {
                return ApiResponse.error("记录不存在");
            }
            oracleInstanceDetailRepository.deleteById(id);
            return ApiResponse.success("删除成功");
        } catch (Exception e) {
            log.error("删除实例记录失败, id={}", id, e);
            return ApiResponse.error("删除失败：" + e.getMessage());
        }
    }
}
