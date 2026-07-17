package com.doubledimple.ociserver.utils.oracle;

import cn.hutool.core.net.Ipv4Util;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.TemInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.response.BootVolumeRes;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicManagementUtils;
import com.oracle.bmc.Realm;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.AuthenticationDetailsProvider;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.BlockstorageClient;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.AddSubnetIpv6CidrDetails;
import com.oracle.bmc.core.model.AttachBootVolumeDetails;
import com.oracle.bmc.core.model.AttachParavirtualizedVolumeDetails;
import com.oracle.bmc.core.model.BootVolume;
import com.oracle.bmc.core.model.BootVolumeAttachment;
import com.oracle.bmc.core.model.BootVolumeSourceFromBootVolumeDetails;
import com.oracle.bmc.core.model.CreateBootVolumeDetails;
import com.oracle.bmc.core.model.CreateInternetGatewayDetails;
import com.oracle.bmc.core.model.CreateSubnetDetails;
import com.oracle.bmc.core.model.EgressSecurityRule;
import com.oracle.bmc.core.model.IcmpOptions;
import com.oracle.bmc.core.model.IngressSecurityRule;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.InstanceSourceViaBootVolumeDetails;
import com.oracle.bmc.core.model.InternetGateway;
import com.oracle.bmc.core.model.LaunchInstanceAgentConfigDetails;
import com.oracle.bmc.core.model.LaunchInstanceDetails;
import com.oracle.bmc.core.model.PortRange;
import com.oracle.bmc.core.model.RouteRule;
import com.oracle.bmc.core.model.RouteTable;
import com.oracle.bmc.core.model.SecurityList;
import com.oracle.bmc.core.model.Shape;
import com.oracle.bmc.core.model.Subnet;
import com.oracle.bmc.core.model.TcpOptions;
import com.oracle.bmc.core.model.UpdateInstanceDetails;
import com.oracle.bmc.core.model.UpdateInstanceSourceViaBootVolumeDetails;
import com.oracle.bmc.core.model.UpdateInternetGatewayDetails;
import com.oracle.bmc.core.model.UpdateRouteTableDetails;
import com.oracle.bmc.core.model.UpdateSecurityListDetails;
import com.oracle.bmc.core.model.Vcn;
import com.oracle.bmc.core.model.Vnic;
import com.oracle.bmc.core.model.VnicAttachment;
import com.oracle.bmc.core.model.VolumeAttachment;
import com.oracle.bmc.core.requests.AddIpv6SubnetCidrRequest;
import com.oracle.bmc.core.requests.AttachBootVolumeRequest;
import com.oracle.bmc.core.requests.AttachVolumeRequest;
import com.oracle.bmc.core.requests.CreateBootVolumeRequest;
import com.oracle.bmc.core.requests.CreateInternetGatewayRequest;
import com.oracle.bmc.core.requests.CreateSubnetRequest;
import com.oracle.bmc.core.requests.DeleteBootVolumeRequest;
import com.oracle.bmc.core.requests.DetachBootVolumeRequest;
import com.oracle.bmc.core.requests.DetachVolumeRequest;
import com.oracle.bmc.core.requests.GetBootVolumeRequest;
import com.oracle.bmc.core.requests.GetInstanceRequest;
import com.oracle.bmc.core.requests.GetRouteTableRequest;
import com.oracle.bmc.core.requests.GetSecurityListRequest;
import com.oracle.bmc.core.requests.GetSubnetRequest;
import com.oracle.bmc.core.requests.GetVcnRequest;
import com.oracle.bmc.core.requests.GetVnicRequest;
import com.oracle.bmc.core.requests.GetVolumeAttachmentRequest;
import com.oracle.bmc.core.requests.InstanceActionRequest;
import com.oracle.bmc.core.requests.ListBootVolumeAttachmentsRequest;
import com.oracle.bmc.core.requests.ListInstancesRequest;
import com.oracle.bmc.core.requests.ListInternetGatewaysRequest;
import com.oracle.bmc.core.requests.ListShapesRequest;
import com.oracle.bmc.core.requests.ListSubnetsRequest;
import com.oracle.bmc.core.requests.ListVcnsRequest;
import com.oracle.bmc.core.requests.ListVnicAttachmentsRequest;
import com.oracle.bmc.core.requests.ListVolumeAttachmentsRequest;
import com.oracle.bmc.core.requests.TerminateInstanceRequest;
import com.oracle.bmc.core.requests.UpdateInstanceRequest;
import com.oracle.bmc.core.requests.UpdateInternetGatewayRequest;
import com.oracle.bmc.core.requests.UpdateRouteTableRequest;
import com.oracle.bmc.core.requests.UpdateSecurityListRequest;
import com.oracle.bmc.core.responses.AttachBootVolumeResponse;
import com.oracle.bmc.core.responses.CreateInternetGatewayResponse;
import com.oracle.bmc.core.responses.CreateSubnetResponse;
import com.oracle.bmc.core.responses.GetBootVolumeResponse;
import com.oracle.bmc.core.responses.GetSubnetResponse;
import com.oracle.bmc.core.responses.GetVnicResponse;
import com.oracle.bmc.core.responses.ListInstancesResponse;
import com.oracle.bmc.core.responses.ListShapesResponse;
import com.oracle.bmc.core.responses.ListSubnetsResponse;
import com.oracle.bmc.core.responses.ListVcnsResponse;
import com.oracle.bmc.core.responses.ListVnicAttachmentsResponse;
import com.oracle.bmc.http.client.jersey.JerseyHttpProvider;
import com.oracle.bmc.identity.Identity;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.AvailabilityDomain;
import com.oracle.bmc.identity.model.Compartment;
import com.oracle.bmc.identity.model.CreateAuthTokenDetails;
import com.oracle.bmc.identity.model.RegionSubscription;
import com.oracle.bmc.identity.requests.CreateAuthTokenRequest;
import com.oracle.bmc.identity.requests.ListAvailabilityDomainsRequest;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import com.oracle.bmc.identity.requests.ListRegionSubscriptionsRequest;
import com.oracle.bmc.identity.responses.CreateAuthTokenResponse;
import com.oracle.bmc.identity.responses.ListAvailabilityDomainsResponse;
import com.oracle.bmc.identity.responses.ListCompartmentsResponse;
import com.oracle.bmc.identity.responses.ListRegionSubscriptionsResponse;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.PasswordPolicy;
import com.oracle.bmc.identitydomains.requests.ListPasswordPoliciesRequest;
import com.oracle.bmc.identitydomains.responses.ListPasswordPoliciesResponse;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.util.CollectionUtils;

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH;
import static com.doubledimple.ociserver.config.exception.ErrorCode.NOT_AUTH_NOT_FUND;
import static com.doubledimple.ociserver.utils.oracle.VCNFlowLogsUtils.getVcnSubnets;
import static com.oracle.bmc.Region.register;
import static com.oracle.bmc.core.model.ClusterNetworkSummary.LifecycleState.Running;
import static com.oracle.bmc.core.model.Instance.LifecycleState.Stopped;
import static com.oracle.bmc.workrequests.model.WorkRequestSummary.Status.Failed;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @author doubleDimple
 * @date 2024:11:16日 19:29
 */
@Slf4j
public class OciUtils {

    public static final String DEFAULT_PASSWD = "OciStart2025";

    public static boolean isIpInCidrList(String ip, List<String> cidrList) {
        long ipLong = Ipv4Util.ipv4ToLong(ip);

        for (String cidr : cidrList) {
            String[] cidrParts = cidr.split("/");
            String cidrIp = cidrParts[0];
            int maskLength = Integer.parseInt(cidrParts[1]);

            long cidrIpLong = Ipv4Util.ipv4ToLong(cidrIp);
            long mask = (1L << (32 - maskLength)) - 1;

            if ((ipLong & ~mask) == (cidrIpLong & ~mask)) {
                return true;
            }
        }
        return false;
    }


    /**
     * @Description: 获取搜索一区域
     * @Param:
     * @return:
     * @Author doubleDimple
     * @Date: 3/16/25 6:50 AM
     */
    public static List<RegionSubscription> queryRegions(SimpleAuthenticationDetailsProvider provider) {
        List<RegionSubscription> nonHomeRegions = new ArrayList<>();
        try (Identity identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取当前账号订阅的所有区域
            ListRegionSubscriptionsRequest listRegionSubscriptionsRequest =
                    ListRegionSubscriptionsRequest.builder()
                            .tenancyId(provider.getTenantId())
                            .build();
            ListRegionSubscriptionsResponse listRegionSubscriptionsResponse =
                    identityClient.listRegionSubscriptions(listRegionSubscriptionsRequest);

            nonHomeRegions = listRegionSubscriptionsResponse.getItems();
        } catch (Exception e) {
            log.error("获取区域失败", e);
            return nonHomeRegions;
        }
        return nonHomeRegions;
    }


    /**
     * @Description: 获取provider
     * @Param: [com.doubledimple.ociserver.domain.Tenant]
     * @return: com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider
     * @Author doubleDimple
     * @Date: 3/16/25 6:54 AM
     */
    public static SimpleAuthenticationDetailsProvider getProvider(Tenant tenant) {
        // 定时任务 / 静态工具统一入口：按父租户绑定代理到当前线程
        TenantProxyBinder.applyForTenant(tenant);
        return SimpleAuthenticationDetailsProvider.builder()
                .userId(tenant.getTenantId())
                .fingerprint(tenant.getFingerprint())
                .tenantId(tenant.getTenancy())
                .privateKeySupplier(() -> {
                    try {
                        return new FileInputStream(tenant.getKeyFile());
                    } catch (FileNotFoundException e) {
                        e.printStackTrace();
                        return null;
                    }
                })
                .region(Region.fromRegionId(RegionEnum.getRegionCode(tenant.getRegion()))).build();
    }

    public static SimpleAuthenticationDetailsProvider getProviderInner(Tenant tenant) {
        TenantProxyBinder.applyForTenant(tenant);
        return SimpleAuthenticationDetailsProvider.builder()
                .userId(tenant.getTenantId())
                .fingerprint(tenant.getFingerprint())
                .tenantId(tenant.getTenancy())
                .privateKeySupplier(() -> {
                    try {
                        return new FileInputStream(tenant.getTmpKeyFile());
                    } catch (FileNotFoundException e) {
                        e.printStackTrace();
                        return null;
                    }
                })
                .region(Region.fromRegionId(RegionEnum.getRegionCode(tenant.getRegion()))).build();
    }

    public static SimpleAuthenticationDetailsProvider getProvider(User user) {
        // User.id = tenant 表主键；有则绑父租户代理，无则走全局共享池（并清掉线程上残留代理）
        Long tenantPk = (user != null && user.getId() > 0) ? user.getId() : null;
        TenantProxyBinder.applyForTenantId(tenantPk);
        return SimpleAuthenticationDetailsProvider.builder()
                .userId(user.getUserId())
                .fingerprint(user.getFingerprint())
                .tenantId(user.getTenancy())
                .privateKeySupplier(() -> {
                    try {
                        return new FileInputStream(user.getKeyFile());
                    } catch (FileNotFoundException e) {
                        e.printStackTrace();
                        return null;
                    }
                }).region(Region.fromRegionId(user.getRegion())).build();
    }

    /**
     * 根据tenant获取实例详情
     */
    public static List<InstanceDetails> getAllInstancesByTenant(Tenant tenant) {
        Long id = tenant.getId();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        List<InstanceDetails> allInstances = new ArrayList<>();
        JerseyHttpProvider httpProvider = JerseyHttpProvider.getInstance();
        // 首先获取所有compartments
        try (IdentityClient identityClient = IdentityClient.builder().httpProvider(httpProvider).clientConfigurator(ProxyContext.get()).build(provider);
             ComputeClient computeClient = ComputeClient.builder().httpProvider(httpProvider).clientConfigurator(ProxyContext.get()).build(provider);
             BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            ListCompartmentsRequest listCompartmentsRequest = ListCompartmentsRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                    .compartmentIdInSubtree(true)
                    .lifecycleState(Compartment.LifecycleState.Active)
                    .build();

            ListCompartmentsResponse compartmentsResponse = identityClient.listCompartments(listCompartmentsRequest);

            // 遍历每个compartment获取实例
            List<String> compartmentIds = new ArrayList<>();
            compartmentIds.add(provider.getTenantId());
            compartmentsResponse.getItems().forEach(c -> compartmentIds.add(c.getId()));

            for (String compartmentId : compartmentIds) {
                ListInstancesRequest listRequest = ListInstancesRequest.builder()
                        .compartmentId(compartmentId)
                        .limit(100)
                        .build();

                ListInstancesResponse response = computeClient.listInstances(listRequest);
                List<Instance> items = response.getItems();
                String architecture = "NONE";
                for (Instance instance : items) {
                    String processorDescription = instance.getShapeConfig().getProcessorDescription();
                    if (processorDescription.contains("Ampere") || processorDescription.contains("Altra")) {
                        architecture = "ARM";
                    } else if (processorDescription.contains("AMD") ||
                            processorDescription.contains("Intel") ||
                            processorDescription.contains("Xeon")) {
                        architecture = "AMD";
                    }
                    List<VnicCreationResult> instanceVnics = VnicManagementUtils.getInstanceVnics(tenant, instance.getId(),instance.getCompartmentId());
                    InstanceDetails instanceDetails = new InstanceDetails();
                    Float ocpus = instance.getShapeConfig().getOcpus();
                    instanceDetails.setInstanceId(instance.getId());
                    instanceDetails.setOcpus(ocpus.intValue());
                    instanceDetails.setDisplayName(instance.getDisplayName());
                    instanceDetails.setShape(instance.getShape());
                    instanceDetails.setProcessorDescription(processorDescription);
                    instanceDetails.setArchitecture(architecture);
                    String value = instance.getLifecycleState().getValue();
                    if (value.equalsIgnoreCase(Instance.LifecycleState.Terminated.getValue())) {
                        continue;
                    }
                    instanceDetails.setState(value);
                    instanceDetails.setCompartmentId(compartmentId);
                    instanceDetails.setTenantId(id);
                    instanceDetails.setMemoryInGBs(instance.getShapeConfig().getMemoryInGBs().intValue());

                    //引导卷信息
                    BootVolume bootVolume = null;
                    try {
                        bootVolume = getBootVolume(blockstorageClient, computeClient, instance, compartmentId);
                    } catch (Exception e) {
                        log.warn("instance get boot volume fail,reason:{}",e.getMessage());
                    }
                    if (null != bootVolume) {
                        Long vpusPerGB = bootVolume.getVpusPerGB() == null ? 0L : bootVolume.getVpusPerGB();
                        instanceDetails.setVpusPerGB(String.valueOf(vpusPerGB));
                        instanceDetails.setBootVolumeId(bootVolume.getId());
                        instanceDetails.setBootVolumeName(bootVolume.getDisplayName());
                        instanceDetails.setBootVolumeSizeInGBs(bootVolume.getSizeInGBs());
                    } else {
                        instanceDetails.setVpusPerGB("0");
                        instanceDetails.setBootVolumeId("-1");
                        instanceDetails.setBootVolumeName("无");
                        instanceDetails.setBootVolumeSizeInGBs(0L);
                    }

                    //获取实例的ip信息
                    Vnic vnic = getVnicPrimary(provider, instance, compartmentId);
                    if (null != vnic) {
                        instanceDetails.setPublicIps(vnic.getPublicIp());
                        instanceDetails.setPrivateIps(vnic.getPrivateIp());
                        if (!CollectionUtils.isEmpty(vnic.getIpv6Addresses())) {
                            instanceDetails.setIpv6Addresses(String.join(",", vnic.getIpv6Addresses()));
                        }
                        instanceDetails.setAvailabilityDomain(vnic.getAvailabilityDomain());
                    } else {
                        instanceDetails.setPublicIps("0.0.0.0");
                        instanceDetails.setPrivateIps("0.0.0.0");
                        instanceDetails.setIpv6Addresses("");
                        instanceDetails.setAvailabilityDomain("空");
                    }

                    //vnic信息
                    if (!CollectionUtils.isEmpty(instanceVnics)){
                        instanceDetails.setVnicIds(instanceVnics.stream().map(VnicCreationResult::getVnicId).collect(Collectors.joining(",")));
                    }
                    allInstances.add(instanceDetails);
                }
            }

        } catch (Exception e) {
            log.warn("get allInstances list fail or current tenant not instances reason:{}",e.getMessage());
        }
        return allInstances;
    }

    /**
     * @Description: 获取主要的ip 信息
     */
    public static Vnic getVnicPrimary(SimpleAuthenticationDetailsProvider provider, Instance instance, String compartmentId) {
        Vnic vnic = null;
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             VirtualNetworkClient vcnClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取实例的所有VNIC附件
            ListVnicAttachmentsRequest listVnicRequest = ListVnicAttachmentsRequest.builder()
                    .compartmentId(compartmentId)
                    .instanceId(instance.getId())
                    .build();

            ListVnicAttachmentsResponse vnicAttachmentsResponse = computeClient.listVnicAttachments(listVnicRequest);
            List<VnicAttachment> vnicAttachments = vnicAttachmentsResponse.getItems();

            if (vnicAttachments.isEmpty()) {
                log.warn("未找到任何VNIC附件");
                return null;
            }

            VnicAttachment primaryVnicAttachment = null;
            for (VnicAttachment attachment : vnicAttachments) {
                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                        .vnicId(attachment.getVnicId())
                        .build();
                try {
                    GetVnicResponse vnicResponse = vcnClient.getVnic(getVnicRequest);
                    vnic = vnicResponse.getVnic();
                } catch (Exception e) {
                    log.debug("vnic 获取失败");
                    continue;
                }

                if (vnic.getIsPrimary()) {
                    primaryVnicAttachment = attachment;
                    log.debug("找到主VNIC: " + vnic.getId());

                    // 输出主VNIC的IP信息
                    log.debug("主要VNIC ID: " + vnic.getId());
                    log.debug("私有IP: " + vnic.getPrivateIp());
                    log.debug("公网IPv4: " + (vnic.getPublicIp() != null ? vnic.getPublicIp() : "未分配"));
                    log.debug("IPv6地址: " + (vnic.getIpv6Addresses() != null ? vnic.getIpv6Addresses() : "未配置"));
                    break;
                }

                // 如果没有找到明确标记为主要的VNIC，则使用第一个
                if (primaryVnicAttachment == null && !vnicAttachments.isEmpty()) {
                    primaryVnicAttachment = vnicAttachments.get(0);
                    GetVnicRequest getVnicRequestFirst = GetVnicRequest.builder()
                            .vnicId(primaryVnicAttachment.getVnicId())
                            .build();
                    GetVnicResponse vnicResponseFirst = vcnClient.getVnic(getVnicRequestFirst);
                    vnic = vnicResponseFirst.getVnic();

                    log.debug("未找到明确标记为主VNIC的附件，使用第一个VNIC:");
                    log.debug("VNIC ID: " + vnic.getId());
                    log.debug("私有IP: " + vnic.getPrivateIp());
                    log.debug("公网IPv4: " + (vnic.getPublicIp() != null ? vnic.getPublicIp() : "未分配"));
                    log.debug("IPv6地址: " + (vnic.getIpv6Addresses() != null ? vnic.getIpv6Addresses() : "未配置"));
                }

            }
        } catch (Exception e) {
            log.error("出现异常,原因为:{}", e.getMessage(), e);
        }
        return vnic;
    }

    public static BootVolume getBootVolume(BlockstorageClient blockstorageClient, ComputeClient computeClient, Instance instance, String compartmentId) {
        // 3. 获取引导卷信息
        ListBootVolumeAttachmentsRequest bootVolumeRequest = ListBootVolumeAttachmentsRequest.builder()
                .availabilityDomain(instance.getAvailabilityDomain())
                .compartmentId(compartmentId)
                .instanceId(instance.getId())
                .build();
        List<BootVolumeAttachment> bootVolumeAttachments = computeClient
                .listBootVolumeAttachments(bootVolumeRequest)
                .getItems();

        // 获取引导卷大小
        if (!bootVolumeAttachments.isEmpty()) {
            GetBootVolumeRequest getBootVolumeRequest = GetBootVolumeRequest.builder()
                    .bootVolumeId(bootVolumeAttachments.get(0).getBootVolumeId())
                    .build();
            return blockstorageClient.getBootVolume(getBootVolumeRequest)
                    .getBootVolume();
        }
        return null;
    }

    /**
     * 停止实例
     */
    public static void stopInstance(SimpleAuthenticationDetailsProvider provider, String instanceId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取实例详情
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();

            Instance.LifecycleState lifecycleState = instance.getLifecycleState();

            // 如果实例已经是停止状态，直接返回
            if (lifecycleState.getValue().equals(Stopped.getValue())) {
                return;
            }

            // 如果实例不是运行状态，抛出异常
            if (!lifecycleState.getValue().equals(Running.getValue())) {
                throw new RuntimeException("实例当前状态为: " + lifecycleState.getValue() + "，无法执行停止操作");
            }

            // 发送停止请求
            computeClient.instanceAction(InstanceActionRequest.builder()
                    .instanceId(instanceId)
                    .action("STOP")
                    .build());

            // 等待实例完全停止
            final int MAX_WAIT_ATTEMPTS = 20; // 最大等待次数
            final int WAIT_INTERVAL_SECONDS = 5; // 每次等待间隔
            int attempts = 0;

            while (attempts < MAX_WAIT_ATTEMPTS) {
                Instance currentState = computeClient.getInstance(
                                GetInstanceRequest.builder()
                                        .instanceId(instanceId)
                                        .build())
                        .getInstance();

                Instance.LifecycleState currentLifecycleState = currentState.getLifecycleState();

                if (currentLifecycleState.getValue().equalsIgnoreCase(Stopped.getValue())) {
                    return;  // 停止成功，正常返回
                } else if (currentLifecycleState.getValue().equalsIgnoreCase(Failed.getValue())) {
                    throw new RuntimeException("实例停止失败");
                }

                log.info("等待实例停止中... 当前状态: {}, 尝试次数: {}/{}",
                        currentLifecycleState.getValue(), attempts + 1, MAX_WAIT_ATTEMPTS);

                try {
                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("等待实例停止过程被中断", e);
                }

                attempts++;
            }

            // 超时抛出异常
            throw new RuntimeException("等待实例停止超时，请手动检查实例状态");

        } catch (Exception e) {
            log.error("停止实例出现异常", e);
            throw new RuntimeException("停止实例失败: " + e.getMessage(), e);
        }
    }

    public static void startInstance(SimpleAuthenticationDetailsProvider provider, String instanceId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取实例详情
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();

            Instance.LifecycleState lifecycleState = instance.getLifecycleState();

            // 如果实例已经是运行状态，直接返回
            if (lifecycleState.getValue().equals(Running.getValue())) {
                return;
            }

            // 如果实例不是停止状态，抛出异常
            if (!lifecycleState.getValue().equals(Stopped.getValue())) {
                throw new RuntimeException("实例当前状态为: " + lifecycleState.getValue() + "，无法执行启动操作");
            }

            // 发送启动请求
            computeClient.instanceAction(InstanceActionRequest.builder()
                    .instanceId(instanceId)
                    .action("START")
                    .build());

            // 等待实例完全启动
            final int MAX_WAIT_ATTEMPTS = 30; // 最大等待次数
            final int WAIT_INTERVAL_SECONDS = 5; // 每次等待间隔
            int attempts = 0;

            while (attempts < MAX_WAIT_ATTEMPTS) {
                Instance currentState = computeClient.getInstance(
                                GetInstanceRequest.builder()
                                        .instanceId(instanceId)
                                        .build())
                        .getInstance();

                Instance.LifecycleState currentLifecycleState = currentState.getLifecycleState();

                if (currentLifecycleState.getValue().equalsIgnoreCase(Running.getValue())) {
                    return;  // 启动成功，正常返回
                } else if (currentLifecycleState.getValue().equalsIgnoreCase(Failed.getValue())) {
                    throw new RuntimeException("实例启动失败");
                }

                log.info("等待实例启动中... 当前状态: {}, 尝试次数: {}/{}",
                        currentLifecycleState.getValue(), attempts + 1, MAX_WAIT_ATTEMPTS);

                try {
                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("等待实例启动过程被中断", e);
                }

                attempts++;
            }

            // 超时抛出异常
            throw new RuntimeException("等待实例启动超时，请手动检查实例状态");

        } catch (Exception e) {
            log.error("启动实例出现异常", e);
            throw new RuntimeException("启动实例失败: " + e.getMessage(), e);
        }
    }


    /**
     * @Description: 分离引导卷
     */
    public static String detachBootVolume(SimpleAuthenticationDetailsProvider provider, String instanceId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 1. 获取实例信息
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();

            // 2. 获取引导卷附件列表
            ListBootVolumeAttachmentsRequest listRequest = ListBootVolumeAttachmentsRequest.builder()
                    .availabilityDomain(instance.getAvailabilityDomain())
                    .compartmentId(instance.getCompartmentId())
                    .instanceId(instance.getId())
                    .build();

            List<BootVolumeAttachment> attachments = computeClient.listBootVolumeAttachments(listRequest).getItems();

            String bootVolumeId = "";
            String attachmentId = "";

            // 3. 查找需要分离的引导卷
            boolean foundAttachedVolume = false;
            for (BootVolumeAttachment attachment : attachments) {
                //引导卷已经分离,直接返回
                if (attachment.getLifecycleState() == BootVolumeAttachment.LifecycleState.Detached) {
                    bootVolumeId = attachment.getBootVolumeId();
                    return bootVolumeId;
                }
                if (attachment.getLifecycleState() == BootVolumeAttachment.LifecycleState.Attached) {
                    bootVolumeId = attachment.getBootVolumeId();
                    attachmentId = attachment.getId();
                    foundAttachedVolume = true;
                    break;
                }
            }

            if (!foundAttachedVolume) {
                throw new RuntimeException("No attached boot volume found for instance: " + instanceId);
            }

            // 4. 执行分离操作
            computeClient.detachBootVolume(
                    DetachBootVolumeRequest.builder()
                            .bootVolumeAttachmentId(attachmentId)
                            .build()
            );

            // 5. 等待分离完成
            final int MAX_ATTEMPTS = 10;
            final int WAIT_SECONDS = 5;

            for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
                ListBootVolumeAttachmentsRequest checkRequest = ListBootVolumeAttachmentsRequest.builder()
                        .availabilityDomain(instance.getAvailabilityDomain())
                        .compartmentId(instance.getCompartmentId())
                        .instanceId(instance.getId())
                        .build();

                List<BootVolumeAttachment> currentAttachments = computeClient.listBootVolumeAttachments(checkRequest).getItems();

                boolean stillAttached = false;
                for (BootVolumeAttachment attachment : currentAttachments) {
                    if (attachment.getId().equals(attachmentId)) {
                        BootVolumeAttachment.LifecycleState state = attachment.getLifecycleState();

                        // 如果已经分离，跳出循环
                        if (state == BootVolumeAttachment.LifecycleState.Detached) {
                            return bootVolumeId;
                        }
                        // 如果还在分离中，继续等待
                        else if (state == BootVolumeAttachment.LifecycleState.Detaching) {
                            stillAttached = true;
                            break;
                        }
                    }
                }

                // 如果已经找不到这个attachment，说明已经完全分离
                if (!stillAttached) {
                    return bootVolumeId;
                }

                // 等待后继续检查
                try {
                    Thread.sleep(WAIT_SECONDS * 1000L);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("Boot volume detachment interrupted", e);
                }
            }

            // 如果超时，抛出异常
            throw new RuntimeException("Boot volume detachment timed out after " +
                    (MAX_ATTEMPTS * WAIT_SECONDS) + " seconds for volume: " + bootVolumeId);
        } catch (Exception e) {
            throw new RuntimeException("Failed to detach boot volume", e);
        }
    }

    /**
     * @Description: //第四步,之前分离的引导卷执行附加,挂载方式选择半虚拟化
     * 返回设备路径
     */
    public static String tachVolume(SimpleAuthenticationDetailsProvider provider, TemInstance temInstance, String bootVolumeId) {
        log.info("开始处理引导卷, 实例ID: {}, 引导卷ID: {}", temInstance.getInstanceId(), bootVolumeId);

        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取实例信息
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder()
                    .instanceId(temInstance.getInstanceId())
                    .build()).getInstance();

            // 首先检查卷是否已经附加
            ListVolumeAttachmentsRequest checkRequest = ListVolumeAttachmentsRequest.builder()
                    .availabilityDomain(instance.getAvailabilityDomain())
                    .compartmentId(instance.getCompartmentId())
                    .volumeId(bootVolumeId)
                    .instanceId(instance.getId())
                    .build();

            List<VolumeAttachment> existingAttachments = computeClient.listVolumeAttachments(checkRequest)
                    .getItems();

            // 检查卷是否已经附加
            for (VolumeAttachment attachment : existingAttachments) {
                if (attachment.getVolumeId().equals(bootVolumeId)) {
                    if (attachment.getLifecycleState() == VolumeAttachment.LifecycleState.Attached) {
                        log.info("引导卷已经附加到实例, 无需重新附加");
                        return attachment.getDevice();
                    } else if (attachment.getLifecycleState() == VolumeAttachment.LifecycleState.Attaching) {
                        log.info("引导卷正在附加中, 等待完成...");
                        // 继续到等待循环
                        break;
                    }
                }
            }

            // 如果卷未附加，创建附加请求
            boolean needAttach = existingAttachments.stream()
                    .noneMatch(a -> a.getVolumeId().equals(bootVolumeId) &&
                            (a.getLifecycleState() == VolumeAttachment.LifecycleState.Attached ||
                                    a.getLifecycleState() == VolumeAttachment.LifecycleState.Attaching));

            if (needAttach) {
                log.info("引导卷未附加, 开始附加操作");
                // 创建半虚拟化卷附加请求
                AttachParavirtualizedVolumeDetails attachDetails = AttachParavirtualizedVolumeDetails.builder()
                        .instanceId(temInstance.getInstanceId())
                        .volumeId(bootVolumeId)
                        .isPvEncryptionInTransitEnabled(false)
                        .displayName("add-attach-volume-" + temInstance.getInstanceId())
                        .build();

                AttachVolumeRequest attachRequest = AttachVolumeRequest.builder()
                        .attachVolumeDetails(attachDetails)
                        .build();

                // 发送附加请求
                computeClient.attachVolume(attachRequest);
                log.info("已发送引导卷附加请求");
            }

            // 等待附加完成
            final int MAX_ATTEMPTS = 20;
            final int WAIT_SECONDS = 5;

            for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
                // 获取当前附加状态
                ListVolumeAttachmentsRequest listRequest = ListVolumeAttachmentsRequest.builder()
                        .availabilityDomain(instance.getAvailabilityDomain())
                        .compartmentId(instance.getCompartmentId())
                        .instanceId(instance.getId())
                        .build();

                List<VolumeAttachment> attachments = computeClient.listVolumeAttachments(listRequest)
                        .getItems();

                // 检查附加状态
                for (VolumeAttachment attachment : attachments) {
                    if (attachment.getVolumeId().equals(bootVolumeId)) {
                        VolumeAttachment.LifecycleState state = attachment.getLifecycleState();

                        switch (state) {
                            case Attached:
                                log.info("引导卷附加成功");
                                return attachment.getDevice();
                            case Attaching:
                                log.info("引导卷正在附加中... 当前尝试次数: {}/{}", attempt + 1, MAX_ATTEMPTS);
                                break;
                            default:
                                log.info("引导卷当前状态: {}, 尝试次数: {}/{}", state, attempt + 1, MAX_ATTEMPTS);
                        }
                    }
                }

                // 等待后继续检查
                try {
                    Thread.sleep(WAIT_SECONDS * 1000L);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("Boot volume attachment interrupted", e);
                }
            }

            // 如果超时，抛出异常
            throw new RuntimeException("Boot volume attachment timed out after " +
                    (MAX_ATTEMPTS * WAIT_SECONDS) + " seconds for volume: " + bootVolumeId);

        } catch (Exception e) {
            log.error("引导卷附加失败: {}", e.getMessage());
            throw new RuntimeException("Failed to attach boot volume: " + bootVolumeId, e);
        }
    }

    /**
     * 检查引导卷是否已终止
     *
     * @param provider     认证信息提供者
     * @param bootVolumeId 引导卷ID
     * @return 如果引导卷已终止，返回true；否则返回false
     */
    public static boolean isBootVolumeTerminated(SimpleAuthenticationDetailsProvider provider, String bootVolumeId) {
        log.debug("检查引导卷是否已终止, 引导卷ID: {}", bootVolumeId);
        boolean isTerminated = false;
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取引导卷信息
            GetBootVolumeRequest request = GetBootVolumeRequest.builder()
                    .bootVolumeId(bootVolumeId)
                    .build();

            GetBootVolumeResponse response = blockstorageClient.getBootVolume(request);
            BootVolume bootVolume = response.getBootVolume();

            // 检查引导卷是否已终止
            isTerminated = (bootVolume.getLifecycleState() == BootVolume.LifecycleState.Terminated);
            log.info("引导卷状态: {}, 是否已终止: {}", bootVolume.getLifecycleState(), isTerminated);
        } catch (Exception e) {
            log.warn("检查引导卷状态失败: {}", e.getMessage());
            //throw new RuntimeException("Failed to check if boot volume is terminated: " + bootVolumeId, e);
            if (e instanceof BmcException){
                BmcException error = (BmcException) e;
                if (error.getStatusCode() == 401 && error.getMessage().contains(NOT_AUTH.getErrorType())){
                    isTerminated = true;
                }else if (error.getStatusCode() == 404 && error.getMessage().contains(NOT_AUTH_NOT_FUND.getErrorType())){
                    isTerminated = true;
                }
            }
        }
        return isTerminated;
    }

    /**
     * @Description: 卸载附加的存储卷
     */
    /*public static void detachVolumeAttachment(SimpleAuthenticationDetailsProvider provider, String instanceId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();

            // 1. 获取快存储卷附件列表
            ListVolumeAttachmentsRequest listRequest = ListVolumeAttachmentsRequest.builder()
                    .instanceId(instance.getId())
                    .compartmentId(instance.getCompartmentId())
                    .build();

            List<VolumeAttachment> attachments = computeClient.listVolumeAttachments(listRequest).getItems();

            for (VolumeAttachment attachment : attachments) {
                // 2. 检查附件状态，只处理已附加的卷
                if (attachment.getLifecycleState() == VolumeAttachment.LifecycleState.Attached) {
                    // 3. 发送分离请求
                    DetachVolumeRequest detachRequest = DetachVolumeRequest.builder()
                            .volumeAttachmentId(attachment.getId())
                            .build();

                    computeClient.detachVolume(detachRequest);
                    log.info("开始分离存储卷: {}", attachment.getVolumeId());

                    // 4. 等待分离完成
                    int attempts = 0;
                    final int MAX_ATTEMPTS = 10;  // 最多等待30次
                    final int WAIT_SECONDS = 5;  // 每次等待10秒

                    while (attempts < MAX_ATTEMPTS) {
                        GetVolumeAttachmentRequest getRequest = GetVolumeAttachmentRequest.builder()
                                .volumeAttachmentId(attachment.getId())
                                .build();

                        try {
                            VolumeAttachment currentAttachment = computeClient.getVolumeAttachment(getRequest)
                                    .getVolumeAttachment();

                            VolumeAttachment.LifecycleState state = currentAttachment.getLifecycleState();
                            log.info("存储卷 {} 当前状态: {}", attachment.getVolumeId(), state);

                            if (state == VolumeAttachment.LifecycleState.Detached) {
                                log.info("存储卷 {} 已成功分离", attachment.getVolumeId());
                                break;
                            }

                            // 继续等待
                            Thread.sleep(WAIT_SECONDS * 1000);
                            attempts++;

                        } catch (BmcException e) {
                            // 如果获取不到附件信息，可能已经分离成功
                            if (e.getStatusCode() == 404) {
                                log.info("存储卷 {} 已分离（附件不存在）", attachment.getVolumeId());
                                break;
                            }
                            throw e;
                        }
                    }

                    if (attempts >= MAX_ATTEMPTS) {
                        throw new RuntimeException("存储卷分离超时: " + attachment.getVolumeId());
                    }
                }
            }

        } catch (Exception e) {
            log.error("分离存储卷时出错", e);
            throw new RuntimeException("分离存储卷失败: " + e.getMessage(), e);
        }
    }*/

    public static void detachVolumeAttachment(SimpleAuthenticationDetailsProvider provider, String instanceId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             BlockstorageClient blockClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            Instance instance = computeClient.getInstance(
                    GetInstanceRequest.builder().instanceId(instanceId).build()
            ).getInstance();

            // 1. 获取快存储卷附件列表（仅数据卷）
            ListVolumeAttachmentsRequest listRequest = ListVolumeAttachmentsRequest.builder()
                    .instanceId(instance.getId())
                    .compartmentId(instance.getCompartmentId())
                    .build();

            List<VolumeAttachment> attachments = computeClient.listVolumeAttachments(listRequest).getItems();

            for (VolumeAttachment attachment : attachments) {
                // 2. 只处理已附加的卷
                if (attachment.getLifecycleState() == VolumeAttachment.LifecycleState.Attached) {
                    // 3. 发送分离请求
                    DetachVolumeRequest detachRequest = DetachVolumeRequest.builder()
                            .volumeAttachmentId(attachment.getId())
                            .build();

                    computeClient.detachVolume(detachRequest);
                    log.info("开始分离存储卷: {}", attachment.getVolumeId());

                    // 4. 等待“附件”分离完成
                    int attempts = 0;
                    final int MAX_ATTEMPTS = 10;
                    final int WAIT_SECONDS = 5;

                    while (attempts < MAX_ATTEMPTS) {
                        GetVolumeAttachmentRequest getRequest = GetVolumeAttachmentRequest.builder()
                                .volumeAttachmentId(attachment.getId())
                                .build();

                        try {
                            VolumeAttachment currentAttachment = computeClient.getVolumeAttachment(getRequest)
                                    .getVolumeAttachment();

                            VolumeAttachment.LifecycleState state = currentAttachment.getLifecycleState();
                            log.info("存储卷 {} 附件当前状态: {}", attachment.getVolumeId(), state);

                            if (state == VolumeAttachment.LifecycleState.Detached) {
                                log.info("存储卷 {} 附件已成功分离", attachment.getVolumeId());
                                break;
                            }

                            Thread.sleep(WAIT_SECONDS * 1000);
                            attempts++;

                        } catch (BmcException e) {
                            // 获取不到附件（404）通常表示附件对象已消失，视为分离完成
                            if (e.getStatusCode() == 404) {
                                log.info("存储卷 {} 附件不存在，已分离", attachment.getVolumeId());
                                break;
                            }
                            throw e;
                        }
                    }

                    if (attempts >= MAX_ATTEMPTS) {
                        throw new RuntimeException("存储卷分离超时(附件未释放): " + attachment.getVolumeId());
                    }

                    log.info("存储卷 {} 已回到 AVAILABLE，可安全用于后续 Attach", attachment.getVolumeId());
                }
            }

        } catch (Exception e) {
            log.error("分离存储卷时出错", e);
            throw new RuntimeException("分离存储卷失败: " + e.getMessage(), e);
        }
    }

    /**
     * @Description: 挂载引导卷
     */
    public static void attachBootVolume(SimpleAuthenticationDetailsProvider provider, String instanceId, String bootVolumeId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();

            AttachBootVolumeDetails attachDetails = AttachBootVolumeDetails.builder()
                    .bootVolumeId(bootVolumeId)
                    .instanceId(instanceId)
                    .displayName("New-Boot-Volume-Attachment")
                    .build();

            AttachBootVolumeRequest request = AttachBootVolumeRequest.builder()
                    .attachBootVolumeDetails(attachDetails)
                    .build();

            log.info("正在挂载新引导卷...");
            AttachBootVolumeResponse response = computeClient.attachBootVolume(request);
            response.getBootVolumeAttachment().getId();

            // 3. 等待附加完成
            final int MAX_ATTEMPTS = 30;
            final int WAIT_SECONDS = 10;
            int attempts = 0;

            while (attempts < MAX_ATTEMPTS) {
                ListBootVolumeAttachmentsRequest listRequest = ListBootVolumeAttachmentsRequest.builder()
                        .availabilityDomain(instance.getAvailabilityDomain())
                        .compartmentId(instance.getCompartmentId())
                        .instanceId(instance.getId())
                        .build();

                List<BootVolumeAttachment> attachments = computeClient.listBootVolumeAttachments(listRequest)
                        .getItems();

                // 检查附加状态
                for (BootVolumeAttachment currentAttachment : attachments) {
                    if (currentAttachment.getBootVolumeId().equals(bootVolumeId)) {
                        BootVolumeAttachment.LifecycleState state = currentAttachment.getLifecycleState();

                        log.info("引导卷 {} 当前状态: {}", bootVolumeId, state);

                        if (state == BootVolumeAttachment.LifecycleState.Attached) {
                            log.info("引导卷已成功附加");
                            return;
                        }
                    }
                }

                // 继续等待
                Thread.sleep(WAIT_SECONDS * 1000);
                attempts++;
            }

            throw new RuntimeException("引导卷附加操作超时");

        } catch (Exception e) {
            log.error("附加引导卷时出错", e);
            throw new RuntimeException("附加引导卷失败: " + e.getMessage(), e);
        }
    }

    /**
     * 替换实例的引导卷 (Replace Boot Volume)
     * 用于系统救援/重置后，将新做好的引导卷挂载给原实例，绕开 409 Conflict 原配校验
     *
     * @param provider         认证提供者
     * @param instanceId       需要更换引导卷的原实例 OCID
     * @param newBootVolumeId  新做好的引导卷 OCID
     */
    public static void replaceBootVolume(SimpleAuthenticationDetailsProvider provider, String instanceId, String newBootVolumeId) {
        log.info("开始为实例 {} 替换全新的引导卷: {}", instanceId, newBootVolumeId);
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 1. 构建新的数据源信息
            UpdateInstanceSourceViaBootVolumeDetails sourceDetails = UpdateInstanceSourceViaBootVolumeDetails.builder()
                    .bootVolumeId(newBootVolumeId)
                    .build();

            // 2. 将新的数据源包装进实例更新配置中
            UpdateInstanceDetails updateDetails = UpdateInstanceDetails.builder()
                    .sourceDetails(sourceDetails)
                    .build();

            // 3. 发起 UpdateInstance 请求
            UpdateInstanceRequest request = UpdateInstanceRequest.builder()
                    .instanceId(instanceId)
                    .updateInstanceDetails(updateDetails)
                    .build();

            // 执行替换操作
            computeClient.updateInstance(request);
            log.info("实例引导卷替换指令已成功发送！");

            // 4. 轮询等待替换完成 (实例状态通常会经历 STOPPING -> STOPPED -> STARTING -> RUNNING)
            final int MAX_ATTEMPTS = 40;
            final int WAIT_SECONDS = 10;

            for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
                Instance currentInstance = computeClient.getInstance(
                        GetInstanceRequest.builder().instanceId(instanceId).build()
                ).getInstance();

                Instance.LifecycleState state = currentInstance.getLifecycleState();
                log.info("实例 {} 引导卷替换中，当前状态: {}，尝试次数: {}/{}", instanceId, state, attempt + 1, MAX_ATTEMPTS);

                // 只要状态回到 RUNNING 或 STOPPED，且关联的数据源确认为新盘，即代表替换成功
                if (state == Instance.LifecycleState.Running || state == Instance.LifecycleState.Stopped) {
                    log.info("实例引导卷替换已彻底完成！");
                    return;
                }
                Thread.sleep(WAIT_SECONDS * 1000L);
            }
            log.warn("等待实例引导卷替换超时，但替换指令已下发，请稍后检查状态。");

        } catch (Exception e) {
            log.error("替换实例引导卷失败", e);
            throw new RuntimeException("替换实例引导卷失败: " + e.getMessage(), e);
        }
    }

    /**
     * 终止实例
     *
     * @param provider           身份验证提供程序
     * @param instanceId         实例ID
     * @param preserveBootVolume 设置为false表示同时删除引导卷
     */
    public static void terminateInstance(SimpleAuthenticationDetailsProvider provider, String instanceId, boolean preserveBootVolume) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取实例详情
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();
            Instance.LifecycleState lifecycleState = instance.getLifecycleState();

            // 如果实例已经是终止状态，直接返回
            if (lifecycleState == Instance.LifecycleState.Terminated) {
                log.info("实例已经是终止状态，无需操作");
                return;
            }

            // 创建终止实例的请求
            TerminateInstanceRequest terminateInstanceRequest = TerminateInstanceRequest.builder()
                    .instanceId(instanceId)
                    .preserveBootVolume(preserveBootVolume)
                    .build();

            // 发送终止请求
            log.info("发送终止实例请求，preserveBootVolume={}", preserveBootVolume);
            computeClient.terminateInstance(terminateInstanceRequest);

            // 等待实例完全终止
            final int MAX_WAIT_ATTEMPTS = 20; // 最大等待次数
            final int WAIT_INTERVAL_SECONDS = 10; // 每次等待间隔
            int attempts = 0;

            while (attempts < MAX_WAIT_ATTEMPTS) {
                try {
                    Instance currentState = computeClient.getInstance(
                                    GetInstanceRequest.builder()
                                            .instanceId(instanceId)
                                            .build())
                            .getInstance();

                    Instance.LifecycleState currentLifecycleState = currentState.getLifecycleState();

                    if (currentLifecycleState == Instance.LifecycleState.Terminated) {
                        log.info("实例已成功终止");
                        return;  // 终止成功，正常返回
                    }
                    log.info("等待实例终止中... 当前状态: {}, 尝试次数: {}/{}",
                            currentLifecycleState.getValue(), attempts + 1, MAX_WAIT_ATTEMPTS);
                } catch (BmcException e) {
                    // 如果实例已经被删除，API会返回404
                    if (e.getStatusCode() == 404) {
                        log.info("实例已不存在，终止成功");
                        return;
                    } else {
                        throw e;
                    }
                }

                try {
                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("等待实例终止过程被中断", e);
                }

                attempts++;
            }

            // 超时抛出异常
            throw new RuntimeException("等待实例终止超时，请手动检查实例状态");

        } catch (Exception e) {
            log.error("终止实例出现异常", e);
            throw new RuntimeException("终止实例失败: " + e.getMessage(), e);
        }
    }


    /**
     * 创建并配置IPv6互联网网关，更新路由表以支持IPv6连接
     * 如果互联网网关已存在，则使用现有网关
     *
     * @param compartmentId        区间ID
     * @param vcnId                VCN ID
     * @param virtualNetworkClient 虚拟网络客户端
     * @return 返回互联网网关对象
     */
    public static InternetGateway createIpv6Gateway(String compartmentId, String vcnId, VirtualNetworkClient virtualNetworkClient) {
        try {
            // 首先检查VCN是否已有互联网网关
            InternetGateway internetGateway = findExistingInternetGateway(compartmentId, vcnId, virtualNetworkClient);

            // 如果没有找到现有网关，则创建新网关
            if (internetGateway == null) {
                CreateInternetGatewayDetails internetGatewayDetails = CreateInternetGatewayDetails.builder()
                        .compartmentId(compartmentId)
                        .vcnId(vcnId)
                        .isEnabled(true)
                        .displayName("IPv6-Internet-Gateway")
                        .build();

                CreateInternetGatewayRequest createInternetGatewayRequest = CreateInternetGatewayRequest.builder()
                        .createInternetGatewayDetails(internetGatewayDetails)
                        .build();

                CreateInternetGatewayResponse internetGatewayResponse = virtualNetworkClient.createInternetGateway(createInternetGatewayRequest);
                internetGateway = internetGatewayResponse.getInternetGateway();
                log.info("互联网网关创建成功，ID: {}", internetGateway.getId());
            } else {
                log.info("使用现有互联网网关，ID: {}", internetGateway.getId());

                // 如果网关被禁用，则启用它
                if (!internetGateway.getIsEnabled()) {
                    UpdateInternetGatewayDetails updateDetails = UpdateInternetGatewayDetails.builder()
                            .isEnabled(true)
                            .build();

                    UpdateInternetGatewayRequest updateRequest = UpdateInternetGatewayRequest.builder()
                            .igId(internetGateway.getId())
                            .updateInternetGatewayDetails(updateDetails)
                            .build();

                    internetGateway = virtualNetworkClient.updateInternetGateway(updateRequest).getInternetGateway();
                    log.info("已启用现有互联网网关");
                }
            }

            // 获取默认路由表
            GetRouteTableRequest getRouteTableRequest = GetRouteTableRequest.builder()
                    .rtId(getDefaultRouteTableId(virtualNetworkClient, vcnId))
                    .build();

            RouteTable defaultRouteTable = virtualNetworkClient.getRouteTable(getRouteTableRequest).getRouteTable();

            // 创建IPv6路由规则
            List<RouteRule> routeRules = new ArrayList<>(defaultRouteTable.getRouteRules());

            // 检查是否已存在IPv6默认路由
            final String internetGatewayId = internetGateway.getId();
            boolean ipv6RouteExists = routeRules.stream()
                    .anyMatch(rule -> "::/0".equals(rule.getDestination()) &&
                            internetGatewayId.equals(rule.getNetworkEntityId()));

            if (!ipv6RouteExists) {
                // 添加IPv6默认路由 - 通过互联网网关
                RouteRule ipv6RouteRule = RouteRule.builder()
                        .destination("::/0")  // IPv6默认路由
                        .destinationType(RouteRule.DestinationType.CidrBlock)
                        .networkEntityId(internetGateway.getId())
                        .description("IPv6 default route")
                        .build();

                routeRules.add(ipv6RouteRule);

                // 更新路由表
                UpdateRouteTableDetails updateRouteTableDetails = UpdateRouteTableDetails.builder()
                        .routeRules(routeRules)
                        .build();

                UpdateRouteTableRequest updateRouteTableRequest = UpdateRouteTableRequest.builder()
                        .rtId(defaultRouteTable.getId())
                        .updateRouteTableDetails(updateRouteTableDetails)
                        .build();

                virtualNetworkClient.updateRouteTable(updateRouteTableRequest);
                log.info("路由表已更新，添加了IPv6默认路由");
            } else {
                log.info("IPv6默认路由已存在，无需更新路由表");
            }

            // 配置安全列表规则允许IPv6流量
            configureIpv6SecurityRules(virtualNetworkClient, vcnId);

            return internetGateway;
        } catch (Exception e) {
            log.error("创建或配置IPv6互联网网关失败: {}", e.getMessage(), e);
            throw new RuntimeException("创建或配置IPv6互联网网关失败", e);
        }
    }

    /**
     * 查找VCN的现有互联网网关
     *
     * @param compartmentId        区间ID
     * @param vcnId                VCN ID
     * @param virtualNetworkClient 虚拟网络客户端
     * @return 如果找到则返回互联网网关，否则返回null
     */
    private static InternetGateway findExistingInternetGateway(String compartmentId, String vcnId, VirtualNetworkClient virtualNetworkClient) {
        try {
            ListInternetGatewaysRequest listRequest = ListInternetGatewaysRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcnId)
                    .lifecycleState(InternetGateway.LifecycleState.Available)
                    .build();

            List<InternetGateway> gateways = virtualNetworkClient.listInternetGateways(listRequest).getItems();

            if (!gateways.isEmpty()) {
                return gateways.get(0);  // 返回第一个找到的网关
            }

            return null;
        } catch (Exception e) {
            log.warn("查找现有互联网网关时出错: {}", e.getMessage());
            return null;  // 出错时返回null，将创建新网关
        }
    }

    /**
     * 获取VCN的默认路由表ID
     *
     * @param virtualNetworkClient 虚拟网络客户端
     * @param vcnId                VCN ID
     * @return 默认路由表ID
     */
    private static String getDefaultRouteTableId(VirtualNetworkClient virtualNetworkClient, String vcnId) {
        try {
            GetVcnRequest getVcnRequest = GetVcnRequest.builder()
                    .vcnId(vcnId)
                    .build();

            Vcn vcn = virtualNetworkClient.getVcn(getVcnRequest).getVcn();
            return vcn.getDefaultRouteTableId();
        } catch (Exception e) {
            log.error("获取默认路由表失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取默认路由表失败", e);
        }
    }

    /**
     * 配置安全列表规则以允许IPv6流量
     *
     * @param virtualNetworkClient 虚拟网络客户端
     * @param vcnId                VCN ID
     */
    private static void configureIpv6SecurityRules(VirtualNetworkClient virtualNetworkClient, String vcnId) {
        try {
            // 获取默认安全列表
            GetVcnRequest getVcnRequest = GetVcnRequest.builder()
                    .vcnId(vcnId)
                    .build();

            Vcn vcn = virtualNetworkClient.getVcn(getVcnRequest).getVcn();
            String defaultSecurityListId = vcn.getDefaultSecurityListId();

            GetSecurityListRequest getSecurityListRequest = GetSecurityListRequest.builder()
                    .securityListId(defaultSecurityListId)
                    .build();

            SecurityList securityList = virtualNetworkClient.getSecurityList(getSecurityListRequest)
                    .getSecurityList();

            // 定义IPv6所需的ICMPv6消息类型
            int[] requiredIcmpTypes = {128, 129, 133, 134, 135, 136, 137};
            Set<Integer> requiredTypesSet = Arrays.stream(requiredIcmpTypes).boxed().collect(Collectors.toSet());

            // 检查是否已存在所有必需的ICMPv6规则
            Set<Integer> existingIcmpv6Types = securityList.getIngressSecurityRules().stream()
                    .filter(rule -> "58".equals(rule.getProtocol()) && "::/0".equals(rule.getSource()))
                    .map(rule -> rule.getIcmpOptions() != null ? rule.getIcmpOptions().getType() : -1)
                    .collect(Collectors.toSet());

            boolean hasAllRequiredIcmpv6Rules = existingIcmpv6Types.containsAll(requiredTypesSet);

            // 检查是否已存在IPv6 TCP入站规则(SSH)
            boolean hasIpv6TcpIngressRule = securityList.getIngressSecurityRules().stream()
                    .anyMatch(rule -> "6".equals(rule.getProtocol()) && "::/0".equals(rule.getSource()) &&
                            rule.getTcpOptions() != null &&
                            rule.getTcpOptions().getDestinationPortRange() != null &&
                            rule.getTcpOptions().getDestinationPortRange().getMin() == 22 &&
                            rule.getTcpOptions().getDestinationPortRange().getMax() == 22);

            // 检查是否已存在IPv6出站规则
            boolean hasIpv6EgressRule = securityList.getEgressSecurityRules().stream()
                    .anyMatch(rule -> rule.getDestination() != null && rule.getDestination().equals("::/0") &&
                            "all".equals(rule.getProtocol()));

            // 如果缺少任何必需的规则，则更新安全列表
            if (!hasAllRequiredIcmpv6Rules || !hasIpv6TcpIngressRule || !hasIpv6EgressRule) {
                List<IngressSecurityRule> ingressRules = new ArrayList<>(securityList.getIngressSecurityRules());
                List<EgressSecurityRule> egressRules = new ArrayList<>(securityList.getEgressSecurityRules());

                // 添加IPv6 TCP入站规则(SSH)
                if (!hasIpv6TcpIngressRule) {
                    IngressSecurityRule ipv6SshRule = IngressSecurityRule.builder()
                            .source("::/0")
                            .protocol("6") // TCP协议
                            .tcpOptions(TcpOptions.builder()
                                    .destinationPortRange(PortRange.builder()
                                            .min(22)
                                            .max(22)
                                            .build())
                                    .build())
                            .description("Allow IPv6 SSH traffic")
                            .build();

                    ingressRules.add(ipv6SshRule);
                    log.info("添加IPv6 SSH入站规则");
                }

                // 添加缺少的ICMPv6规则
                if (!hasAllRequiredIcmpv6Rules) {
                    Map<Integer, String> icmpTypeDescriptions = new HashMap<>();
                    icmpTypeDescriptions.put(128, "Echo Request (ping)");
                    icmpTypeDescriptions.put(129, "Echo Reply");
                    icmpTypeDescriptions.put(133, "Router Solicitation");
                    icmpTypeDescriptions.put(134, "Router Advertisement");
                    icmpTypeDescriptions.put(135, "Neighbor Solicitation");
                    icmpTypeDescriptions.put(136, "Neighbor Advertisement");
                    icmpTypeDescriptions.put(137, "Redirect Message");

                    // 添加所有缺少的ICMPv6类型
                    for (int type : requiredTypesSet) {
                        if (!existingIcmpv6Types.contains(type)) {
                            IngressSecurityRule icmpv6Rule = IngressSecurityRule.builder()
                                    .source("::/0")
                                    .protocol("58") // ICMPv6协议
                                    .icmpOptions(IcmpOptions.builder()
                                            .type(type)
                                            .code(0)
                                            .build())
                                    .description("Allow ICMPv6 " + icmpTypeDescriptions.getOrDefault(type, "Type " + type))
                                    .build();

                            ingressRules.add(icmpv6Rule);
                            log.info("添加ICMPv6类型{}入站规则", type);
                        }
                    }

                    // 也可以添加一个通用ICMPv6规则来允许所有ICMPv6流量
                    if (existingIcmpv6Types.isEmpty()) {
                        IngressSecurityRule allIcmpv6Rule = IngressSecurityRule.builder()
                                .source("::/0")
                                .protocol("58") // ICMPv6协议
                                .description("Allow all ICMPv6 traffic required for IPv6 connectivity")
                                .build();

                        ingressRules.add(allIcmpv6Rule);
                        log.info("添加通用ICMPv6入站规则");
                    }
                }

                // 添加IPv6出站规则
                if (!hasIpv6EgressRule) {
                    EgressSecurityRule ipv6EgressRule = EgressSecurityRule.builder()
                            .destination("::/0")
                            .protocol("all")
                            .description("Allow all IPv6 egress traffic")
                            .build();

                    egressRules.add(ipv6EgressRule);
                    log.info("添加IPv6出站规则");
                }

                // 更新安全列表
                UpdateSecurityListDetails updateSecurityListDetails = UpdateSecurityListDetails.builder()
                        .ingressSecurityRules(ingressRules)
                        .egressSecurityRules(egressRules)
                        .build();

                UpdateSecurityListRequest updateSecurityListRequest = UpdateSecurityListRequest.builder()
                        .securityListId(defaultSecurityListId)
                        .updateSecurityListDetails(updateSecurityListDetails)
                        .build();

                virtualNetworkClient.updateSecurityList(updateSecurityListRequest);
                log.info("安全列表已更新，添加了IPv6访问规则");
            } else {
                log.info("所有必需的IPv6安全列表规则已存在，无需更新");
            }
        } catch (Exception e) {
            log.error("配置IPv6安全列表规则失败: {}", e.getMessage(), e);
            throw new RuntimeException("配置IPv6安全列表规则失败", e);
        }
    }

    /**
     * Terminates (deletes) a specified boot volume
     *
     * @param tenant
     * @param bootVolumeId ID of the boot volume to be terminated
     * @return boolean indicating success (true) or failure (false)
     */
    public static boolean terminateBootVolume(Tenant tenant, String bootVolumeId) {
        final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            try {
                GetBootVolumeRequest getRequest = GetBootVolumeRequest.builder()
                        .bootVolumeId(bootVolumeId)
                        .build();

                BootVolume bootVolume = blockstorageClient.getBootVolume(getRequest).getBootVolume();
                BootVolume.LifecycleState lifecycleState = bootVolume.getLifecycleState();

                // If the boot volume is already terminated/deleted, return success
                if (lifecycleState == BootVolume.LifecycleState.Terminated) {
                    log.info("Boot volume {} is already terminated", bootVolumeId);
                    return true;
                }

                // Check if the boot volume is in a state that allows deletion
                if (lifecycleState != BootVolume.LifecycleState.Available) {
                    log.warn("Boot volume {} is in state {}, which may not allow deletion",
                            bootVolumeId, lifecycleState.getValue());
                }

            } catch (BmcException e) {
                // If the volume doesn't exist (404), consider the operation successful
                if (e.getStatusCode() == 404) {
                    log.info("Boot volume {} not found, considering it already deleted", bootVolumeId);
                    return true;
                }
                log.error("Error checking boot volume status: {}", e.getMessage());
                return false;
            }

            // 2. Send delete request
            try {
                DeleteBootVolumeRequest deleteRequest = DeleteBootVolumeRequest.builder()
                        .bootVolumeId(bootVolumeId)
                        .build();

                blockstorageClient.deleteBootVolume(deleteRequest);
                log.info("Delete request sent for boot volume {}", bootVolumeId);
            } catch (Exception e) {
                log.error("Failed to send delete request for boot volume {}: {}", bootVolumeId, e.getMessage());
                return false;
            }

            // 3. Wait for deletion to complete
            final int MAX_ATTEMPTS = 15;
            final int WAIT_SECONDS = 10;

            for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
                try {
                    GetBootVolumeRequest getRequest = GetBootVolumeRequest.builder()
                            .bootVolumeId(bootVolumeId)
                            .build();

                    BootVolume.LifecycleState currentState = blockstorageClient
                            .getBootVolume(getRequest)
                            .getBootVolume()
                            .getLifecycleState();

                    log.info("Boot volume {} current state: {}, attempt {}/{}",
                            bootVolumeId, currentState.getValue(), attempt + 1, MAX_ATTEMPTS);

                    if (currentState == BootVolume.LifecycleState.Terminated) {
                        log.info("Boot volume {} has been successfully terminated", bootVolumeId);
                        return true;
                    }

                } catch (BmcException e) {
                    // 404 means the boot volume has been deleted
                    if (e.getStatusCode() == 404) {
                        log.info("Boot volume {} has been successfully terminated (not found)", bootVolumeId);
                        return true;
                    }
                    log.error("Error checking boot volume status during deletion: {}", e.getMessage());
                    return false;
                }

                // Wait before checking again
                try {
                    Thread.sleep(WAIT_SECONDS * 1000L);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.error("Boot volume termination process interrupted");
                    return false;
                }
            }

            // If we get here, the deletion is taking too long
            log.warn("Boot volume {} termination timed out after {} seconds",
                    bootVolumeId, MAX_ATTEMPTS * WAIT_SECONDS);
            return false;

        } catch (Exception e) {
            log.error("Failed to terminate boot volume {}: {}", bootVolumeId, e.getMessage());
            return false;
        }
    }

    /**
     * 根据实例ID查询可用性域（Availability Domain）
     *
     * @param tenant     身份验证提供程序
     * @param instanceId 实例ID
     * @return 可用性域名称，如果查询失败则返回null
     */
    public static String getAvailabilityDomainByInstanceId(Tenant tenant, String instanceId) {
        final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 通过实例ID直接获取实例详情
            GetInstanceRequest getInstanceRequest = GetInstanceRequest.builder()
                    .instanceId(instanceId)
                    .build();

            // 获取实例对象
            Instance instance = computeClient.getInstance(getInstanceRequest).getInstance();

            // 直接从实例对象获取可用性域
            String availabilityDomain = instance.getAvailabilityDomain();

            log.info("实例 {} 的可用性域为: {}", instanceId, availabilityDomain);
            return availabilityDomain;

        } catch (BmcException e) {
            // 处理特定的OCI API异常
            log.error("查询实例可用性域失败, 状态码: {}, 错误信息: {}", e.getStatusCode(), e.getMessage(), e);
            return null;
        } catch (Exception e) {
            // 处理其他可能的异常
            log.error("查询实例可用性域时出现异常: {}", e.getMessage(), e);
            return null;
        }
    }


    public static String getArchitectureByInstanceId(Tenant tenant, String instanceId) {
        String architecture = "NONE";
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(getProvider(tenant))) {
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();
            String processorDescription = instance.getShapeConfig().getProcessorDescription();
            if (processorDescription.contains("Ampere") || processorDescription.contains("Altra")) {
                architecture = "ARM";
            } else if (processorDescription.contains("AMD") ||
                    processorDescription.contains("Intel") ||
                    processorDescription.contains("Xeon")) {
                architecture = "AMD";
            }
        }
        return architecture;
    }

    public static Subnet createOrUpdateSubnet(String compartmentId, String vcnId,
                                              VirtualNetworkClient vcnClient, String subnetIpv6CidrBlock) throws Exception {

        // 先查找现有子网
        ListSubnetsRequest request = ListSubnetsRequest.builder()
                .compartmentId(compartmentId)
                .vcnId(vcnId).build();

        ListSubnetsResponse listSubnetsResponse = vcnClient.listSubnets(request);

        if (null != listSubnetsResponse && null != listSubnetsResponse.getItems() &&
                !listSubnetsResponse.getItems().isEmpty()) {

            Subnet existingSubnet = listSubnetsResponse.getItems().get(0);

            // 检查现有子网是否已启用IPv6
            if (existingSubnet.getIpv6CidrBlock() != null && !existingSubnet.getIpv6CidrBlock().isEmpty()) {
                log.info("Using existing subnet with IPv6 enabled: " + existingSubnet.getId());
                return existingSubnet;
            }

            // 现有子网未启用IPv6，尝试为其添加IPv6 CIDR
            try {
                AddSubnetIpv6CidrDetails addSubnetIpv6CidrDetails = AddSubnetIpv6CidrDetails.builder()
                        .ipv6CidrBlock(subnetIpv6CidrBlock)
                        .build();

                AddIpv6SubnetCidrRequest addSubnetIpv6CidrRequest = AddIpv6SubnetCidrRequest.builder()
                        .subnetId(existingSubnet.getId())
                        .addSubnetIpv6CidrDetails(addSubnetIpv6CidrDetails)
                        .build();

                vcnClient.addIpv6SubnetCidr(addSubnetIpv6CidrRequest);
                log.info("Added IPv6 CIDR to existing subnet: " + existingSubnet.getId());

                // 获取更新后的子网信息
                GetSubnetResponse updatedSubnetResponse = vcnClient.getSubnet(
                        GetSubnetRequest.builder().subnetId(existingSubnet.getId()).build());
                return updatedSubnetResponse.getSubnet();
            } catch (Exception e) {
                log.info("Could not add IPv6 to existing subnet, will create new one: " + e.getMessage());
                // 如果无法为现有子网添加IPv6，继续创建新子网
            }
        }

        // 没有合适的现有子网，创建新的
        CreateSubnetDetails subnetDetails = CreateSubnetDetails.builder()
                .compartmentId(compartmentId)
                .vcnId(vcnId)
                .ipv6CidrBlock(subnetIpv6CidrBlock)
                .build();

        CreateSubnetResponse createSubnetResponse =
                vcnClient.createSubnet(
                        CreateSubnetRequest.builder()
                                .createSubnetDetails(subnetDetails)
                                .build());

        GetSubnetResponse getSubnetResponse =
                vcnClient
                        .getWaiters()
                        .forSubnet(
                                GetSubnetRequest.builder()
                                        .subnetId(createSubnetResponse.getSubnet().getId())
                                        .build(),
                                Subnet.LifecycleState.Available)
                        .execute();

        Subnet subnet = getSubnetResponse.getSubnet();
        log.info("Created new subnet with IPv6: " + subnet.getId());
        return subnet;
    }

    /**
     * 根据实例ID查询实例信息
     *
     * @param tenant     租户信息
     * @param instanceId 实例ID
     * @return 返回实例对象，如果查询失败则返回null
     */
    public static Instance getInstanceById(Tenant tenant, String instanceId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 创建请求对象
            GetInstanceRequest getInstanceRequest = GetInstanceRequest.builder()
                    .instanceId(instanceId)
                    .build();

            // 发送请求获取实例信息
            Instance instance = computeClient.getInstance(getInstanceRequest).getInstance();
            log.info("成功获取实例 {} 的信息", instanceId);
            return instance;
        } catch (BmcException e) {
            // 处理OCI特定异常
            log.error("查询实例失败, 状态码: {}, 错误信息: {}", e.getStatusCode(), e.getMessage(), e);
            return null;
        } catch (Exception e) {
            // 处理其他可能的异常
            log.error("查询实例时出现异常: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 从现有引导卷克隆创建新的引导卷
     *
     * @param tenant             租户信息
     * @param sourceBootVolumeId 源引导卷ID
     * @param displayName        新引导卷的显示名称（可选，可为null）
     * @param sizeInGBs          新引导卷的大小（可选，如果为null则使用源大小）
     * @return 新创建的引导卷ID，如果操作失败则返回null
     */
    public static String cloneBootVolumeFromBootVolume(Tenant tenant, String sourceBootVolumeId,
                                                       String displayName, Long sizeInGBs) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 1. 获取源引导卷详情
            GetBootVolumeRequest getSourceRequest = GetBootVolumeRequest.builder()
                    .bootVolumeId(sourceBootVolumeId)
                    .build();

            BootVolume sourceBootVolume;
            try {
                sourceBootVolume = blockstorageClient.getBootVolume(getSourceRequest).getBootVolume();
            } catch (BmcException e) {
                if (e.getStatusCode() == 404) {
                    log.error("源引导卷不存在: {}", sourceBootVolumeId);
                    return null;
                }
                throw e;
            }

            // 2. 检查源引导卷状态
            if (sourceBootVolume.getLifecycleState() != BootVolume.LifecycleState.Available) {
                log.error("源引导卷状态为 {}，必须为 Available 状态才能克隆",
                        sourceBootVolume.getLifecycleState());
                return null;
            }

            String compartmentId = sourceBootVolume.getCompartmentId();
            String availabilityDomain = sourceBootVolume.getAvailabilityDomain();

            // 3. 确定引导卷大小
            Long volumeSize = sizeInGBs != null ? sizeInGBs : sourceBootVolume.getSizeInGBs();

            // 4. 如果未提供显示名称，则生成一个
            String newVolumeDisplayName = displayName != null ? displayName :
                    "克隆-" + sourceBootVolume.getDisplayName() + "-" + System.currentTimeMillis();

            log.info("从引导卷 {} 克隆新卷，大小: {} GB, 名称: {}",
                    sourceBootVolumeId, volumeSize, newVolumeDisplayName);

            // 5. 创建引导卷源详情
            BootVolumeSourceFromBootVolumeDetails sourceDetails = BootVolumeSourceFromBootVolumeDetails.builder()
                    .id(sourceBootVolumeId)
                    .build();

            // 6. 创建新引导卷
            CreateBootVolumeDetails createVolumeDetails = CreateBootVolumeDetails.builder()
                    .availabilityDomain(availabilityDomain)
                    .compartmentId(compartmentId)
                    .displayName(newVolumeDisplayName)
                    .sizeInGBs(volumeSize)
                    .sourceDetails(sourceDetails)
                    .build();

            CreateBootVolumeRequest createVolumeRequest = CreateBootVolumeRequest.builder()
                    .createBootVolumeDetails(createVolumeDetails)
                    .build();

            BootVolume newBootVolume = blockstorageClient.createBootVolume(createVolumeRequest)
                    .getBootVolume();

            String newBootVolumeId = newBootVolume.getId();
            log.info("开始创建新引导卷，ID: {}", newBootVolumeId);

            // 7. 等待新引导卷变为可用状态
            final int MAX_VOLUME_ATTEMPTS = 30;
            final int VOLUME_WAIT_SECONDS = 10;

            BootVolume.LifecycleState volumeState = newBootVolume.getLifecycleState();
            int volumeAttempts = 0;

            while (volumeState != BootVolume.LifecycleState.Available && volumeAttempts < MAX_VOLUME_ATTEMPTS) {
                try {
                    Thread.sleep(VOLUME_WAIT_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.error("引导卷创建等待被中断", e);
                    return newBootVolumeId; // 即使被中断也返回ID，因为卷正在创建中
                }

                GetBootVolumeRequest getVolumeRequest = GetBootVolumeRequest.builder()
                        .bootVolumeId(newBootVolumeId)
                        .build();

                try {
                    newBootVolume = blockstorageClient.getBootVolume(getVolumeRequest).getBootVolume();
                    volumeState = newBootVolume.getLifecycleState();

                    log.info("新引导卷状态: {}, 尝试次数: {}/{}",
                            volumeState, ++volumeAttempts, MAX_VOLUME_ATTEMPTS);

                    if (volumeState == BootVolume.LifecycleState.Faulty) {
                        log.error("引导卷创建失败");
                        return null;
                    }
                } catch (BmcException e) {
                    log.error("检查引导卷状态时出错: {}", e.getMessage());
                    if (e.getStatusCode() == 404) {
                        log.error("找不到引导卷，创建可能已失败");
                        return null;
                    }
                    throw e;
                }
            }

            if (volumeState != BootVolume.LifecycleState.Available) {
                log.error("引导卷创建未在预期时间内完成");
                return newBootVolumeId; // 仍返回ID，因为卷可能最终会变为可用
            }

            log.info("成功克隆引导卷，新卷ID: {}", newBootVolumeId);
            return newBootVolumeId;

        } catch (Exception e) {
            log.error("从引导卷 {} 克隆引导卷失败: {}", sourceBootVolumeId, e.getMessage(), e);
            return null;
        }
    }

    public static BootVolume getBootVolume(Instance instance, Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);) {
            return getBootVolume(blockstorageClient, computeClient, instance, compartmentId);
        } catch (Exception e) {
            return null;
        }
    }


    /**
     * @Description: 测活需求, 校验软封 true:有shape,false 软封
     * @Param: [com.doubledimple.ociserver.domain.Tenant]
     * @return: boolean
     * @Author doubleDimple
     * @Date: 4/25/25 11:05 PM
     */
    public static boolean checkAllDomainsIsShapeEnabled(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            ListAvailabilityDomainsResponse listAvailabilityDomainsResponse =
                    identityClient.listAvailabilityDomains(ListAvailabilityDomainsRequest.builder()
                            .compartmentId(compartmentId)
                            .build());

            List<AvailabilityDomain> items = listAvailabilityDomainsResponse.getItems();
            int sourceDomains = items.size();
            int noShapes = 0;
            for (AvailabilityDomain availabilityDomain : items) {
                ListShapesRequest listShapesRequest =
                        ListShapesRequest.builder()
                                .availabilityDomain(availabilityDomain.getName())
                                .compartmentId(compartmentId)
                                .build();
                ListShapesResponse listShapesResponse = computeClient.listShapes(listShapesRequest);
                List<Shape> shapes = listShapesResponse.getItems();
                if (shapes.isEmpty()) {
                    noShapes++;
                }
            }

            if (noShapes == sourceDomains) {
                return false;
            } else {
                return true;
            }
        }
    }


    /**
     * @Description: 测活需求, 校验软封 true:有shape,false 软封
     * @Param: [com.oracle.bmc.core.ComputeClient, com.oracle.bmc.auth.AuthenticationDetailsProvider, java.util.List<com.oracle.bmc.identity.model.AvailabilityDomain>]
     * @return: boolean
     * @Author doubleDimple
     * @Date: 4/25/25 11:17 PM
     */
    public static boolean checkShapes(ComputeClient computeClient, AuthenticationDetailsProvider provider, List<AvailabilityDomain> items) {
        String compartmentId = provider.getTenantId();
        int sourceDomains = items.size();
        int noShapes = 0;
        for (AvailabilityDomain availabilityDomain : items) {
            ListShapesRequest listShapesRequest =
                    ListShapesRequest.builder()
                            .availabilityDomain(availabilityDomain.getName())
                            .compartmentId(compartmentId)
                            .build();
            ListShapesResponse listShapesResponse = computeClient.listShapes(listShapesRequest);
            List<Shape> shapes = listShapesResponse.getItems();
            if (shapes.isEmpty()) {
                noShapes++;
            }
        }

        if (noShapes == sourceDomains) {
            return false;
        } else {
            return true;
        }
    }


    /**
     * 使用软重启(SOFTRESET)重新引导实例
     * 向操作系统发送关机信号，等待最多15分钟后再启动
     *
     * @param tenant     认证提供者
     * @param instanceId 实例ID
     * @throws Exception 如果重启过程中发生错误
     */
    public static void softResetInstance(Tenant tenant, String instanceId) {
        rebootInstance(tenant, instanceId, true);
    }

    /**
     * 使用硬重启(RESET)重新引导实例
     * 立即强制关闭后再启动，可能导致数据丢失
     *
     * @param tenant     认证提供者
     * @param instanceId 实例ID
     * @throws Exception 如果重启过程中发生错误
     */
    public static void resetInstance(Tenant tenant, String instanceId) {
        rebootInstance(tenant, instanceId, false);
    }

    /**
     * 重新引导实例(重启)
     *
     * @param tenant       认证提供者
     * @param instanceId   实例ID
     * @param useSoftReset 是否使用软重启(true: SOFTRESET, false: RESET)
     * @throws Exception 如果重启过程中发生错误
     */
    public static void rebootInstance(Tenant tenant, String instanceId, boolean useSoftReset) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 获取实例详情
            Instance instance = computeClient.getInstance(GetInstanceRequest.builder().instanceId(instanceId).build()).getInstance();

            Instance.LifecycleState lifecycleState = instance.getLifecycleState();

            // 检查实例是否处于可重启的状态(RUNNING)
            /*if (!lifecycleState.getValue().equals(Instance.LifecycleState.Running.getValue())) {
                throw new RuntimeException("实例当前状态为: " + lifecycleState.getValue() + "，无法执行重启操作，必须为运行状态");
            }*/

            // 确定重启动作
            String action = useSoftReset ? "SOFTRESET" : "RESET";
            String actionDescription = useSoftReset ? "软重启" : "硬重启";

            log.info("开始对实例 {} 执行{}操作", instanceId, actionDescription);

            // 发送重启请求
            computeClient.instanceAction(InstanceActionRequest.builder()
                    .instanceId(instanceId)
                    .action(action)
                    .build());

            // 等待实例完成重启
            final int MAX_WAIT_ATTEMPTS = 30; // 最大等待次数
            final int WAIT_INTERVAL_SECONDS = 10; // 每次等待间隔
            int attempts = 0;

            while (attempts < MAX_WAIT_ATTEMPTS) {
                Instance currentState = computeClient.getInstance(
                                GetInstanceRequest.builder()
                                        .instanceId(instanceId)
                                        .build())
                        .getInstance();

                Instance.LifecycleState currentLifecycleState = currentState.getLifecycleState();

                // 检查实例是否已经重启完成并恢复运行状态
                if (currentLifecycleState == Instance.LifecycleState.Running) {
                    log.info("实例 {} {}完成，已恢复运行状态", instanceId, actionDescription);
                    return;  // 重启成功，正常返回
                } else if (currentLifecycleState == Instance.LifecycleState.Stopped ||
                        currentLifecycleState == Instance.LifecycleState.Terminated) {
                    throw new RuntimeException("实例重启失败，当前状态为: " + currentLifecycleState.getValue());
                }

                log.info("等待实例重启中... 当前状态: {}, 尝试次数: {}/{}",
                        currentLifecycleState.getValue(), attempts + 1, MAX_WAIT_ATTEMPTS);

                try {
                    Thread.sleep(WAIT_INTERVAL_SECONDS * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("等待实例重启过程被中断", e);
                }

                attempts++;
            }

            // 超时抛出异常
            throw new RuntimeException("等待实例重启超时，请手动检查实例状态");

        } catch (Exception e) {
            log.error("重启实例出现异常", e);
            throw new RuntimeException("重启实例失败: " + e.getMessage(), e);
        }
    }

    /**
     * @Description: 获取所有compartmentId
     * @Param: [com.doubledimple.ociserver.domain.Tenant]
     * @return: java.util.List<java.lang.String>
     * @Author: [your name]
     * @Date: 5/03/25
     */
    public static List<String> getAllCompartmentIds(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        List<String> compartmentIds = new ArrayList<>();

        try (IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // Add the tenant's root compartment ID
            compartmentIds.add(provider.getTenantId());

            // Get all compartments in the tenancy, including nested ones
            ListCompartmentsRequest listCompartmentsRequest = ListCompartmentsRequest.builder()
                    .compartmentId(provider.getTenantId())
                    .accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                    .compartmentIdInSubtree(true)
                    .lifecycleState(Compartment.LifecycleState.Active)
                    .build();

            ListCompartmentsResponse compartmentsResponse = identityClient.listCompartments(listCompartmentsRequest);

            List<Compartment> items = compartmentsResponse.getItems();
            for (Compartment item : items) {
                log.info("Compartment Name: {}", item.getName());
                compartmentIds.add(item.getId());
            }

            log.info("Retrieved {} compartment IDs for tenant {}", compartmentIds.size(), tenant.getId());

        } catch (Exception e) {
            log.warn("Failed to get compartment IDs fail reason: {}", e.getMessage());
        }

        return compartmentIds;
    }

    /**
     * 验证引导卷列表并提示超过配额的引导卷
     *
     * @param bootVolumeList 引导卷列表
     * @return 验证结果，如果有超限的引导卷则返回错误信息，否则返回null
     */
    public static String validateBootVolumes(List<BootVolumeRes> bootVolumeList) {
        if (bootVolumeList == null || bootVolumeList.isEmpty()) {
            return null;
        }

        // 定义引导卷最大大小（GB）
        final long MAX_BOOT_VOLUME_SIZE = 150;

        // 找出所有超过配额的引导卷
        List<BootVolumeRes> oversizedVolumes = bootVolumeList.stream()
                .filter(vol -> vol.getSizeInGBs() != null)
                .collect(Collectors.toList());

        // 计算所有引导卷的总大小
        long totalBootVolumeSize = oversizedVolumes.stream()
                .filter(vol -> vol.getSizeInGBs() != null)
                .mapToLong(vol -> vol.getSizeInGBs())
                .sum();

        if (totalBootVolumeSize < MAX_BOOT_VOLUME_SIZE) {
            oversizedVolumes = new ArrayList<>();
        }

        // 如果有超过配额的引导卷，构建错误消息
        if (!oversizedVolumes.isEmpty()) {
            StringBuilder errorMsg = new StringBuilder("以下引导卷已超过配额(150GB)，无法执行救援操作：\n");

            for (BootVolumeRes volume : oversizedVolumes) {
                errorMsg.append("- 引导卷：").append(volume.getDisplayName())
                        .append("，大小：").append(volume.getSizeInGBs()).append("GB")
                        .append(volume.getInstanceName() != null ? "，关联实例：" + volume.getInstanceName() : "")
                        .append("\n");
            }

            return errorMsg.toString();
        }

        return null;
    }

    /**
     * 删除引导卷
     * 此方法用于删除未关联实例的引导卷
     *
     * @param tenant       租户信息
     * @param bootVolumeId 需要删除的引导卷ID
     * @return 返回包含操作结果的响应对象
     */
    public static Map<String, Object> deleteBootVolume(Tenant tenant, String bootVolumeId) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (BlockstorageClient blockstorageClient = BlockstorageClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 1. 检查引导卷是否存在及其状态
            BootVolume bootVolume;
            try {
                GetBootVolumeRequest getRequest = GetBootVolumeRequest.builder()
                        .bootVolumeId(bootVolumeId)
                        .build();

                bootVolume = blockstorageClient.getBootVolume(getRequest).getBootVolume();

                // 如果引导卷已经被删除，返回成功
                if (bootVolume.getLifecycleState() == BootVolume.LifecycleState.Terminated) {
                    log.info("引导卷 {} 已经被删除", bootVolumeId);
                    response.put("success", true);
                    response.put("message", "引导卷已经被删除");
                    return response;
                }

                // 检查引导卷是否处于可删除状态
                if (bootVolume.getLifecycleState() != BootVolume.LifecycleState.Available) {
                    log.warn("引导卷 {} 当前状态为 {}，不能被删除",
                            bootVolumeId, bootVolume.getLifecycleState().getValue());
                    response.put("message", "引导卷当前状态不允许删除，请等待其变为可用状态后再试");
                    return response;
                }
            } catch (BmcException e) {
                // 如果引导卷不存在 (404)，认为操作成功
                if (e.getStatusCode() == 404) {
                    log.info("引导卷 {} 不存在，无需删除", bootVolumeId);
                    response.put("success", true);
                    response.put("message", "引导卷不存在，无需删除");
                    return response;
                }

                // 其他错误
                log.error("检查引导卷状态失败: {}", e.getMessage(), e);
                response.put("message", "检查引导卷状态失败: " + e.getMessage());
                return response;
            }

            // 2. 检查引导卷是否被附加到实例
            String availabilityDomain = bootVolume.getAvailabilityDomain();
            String compartmentId = bootVolume.getCompartmentId();

            ListBootVolumeAttachmentsRequest listAttachmentsRequest = ListBootVolumeAttachmentsRequest.builder()
                    .availabilityDomain(availabilityDomain)
                    .compartmentId(compartmentId)
                    .bootVolumeId(bootVolumeId)
                    .build();

            List<BootVolumeAttachment> attachments = computeClient.listBootVolumeAttachments(listAttachmentsRequest).getItems();

            // 过滤出处于附加状态的附件
            List<BootVolumeAttachment> activeAttachments = attachments.stream()
                    .filter(attachment -> attachment.getLifecycleState() == BootVolumeAttachment.LifecycleState.Attached)
                    .collect(Collectors.toList());

            if (!activeAttachments.isEmpty()) {
                // 获取实例名称以提供更有用的错误信息
                List<String> attachedInstanceNames = new ArrayList<>();
                for (BootVolumeAttachment attachment : activeAttachments) {
                    try {
                        Instance instance = computeClient.getInstance(
                                        GetInstanceRequest.builder()
                                                .instanceId(attachment.getInstanceId())
                                                .build())
                                .getInstance();
                        attachedInstanceNames.add(instance.getDisplayName());
                    } catch (Exception e) {
                        // 如果无法获取实例名称，使用实例ID
                        attachedInstanceNames.add(attachment.getInstanceId());
                    }
                }

                String errorMessage = String.format(
                        "引导卷被以下实例使用，无法删除: %s。请先分离引导卷再进行删除操作。",
                        String.join(", ", attachedInstanceNames));

                log.warn(errorMessage);
                response.put("message", errorMessage);
                return response;
            }

            // 3. 发送删除请求
            try {
                DeleteBootVolumeRequest deleteRequest = DeleteBootVolumeRequest.builder()
                        .bootVolumeId(bootVolumeId)
                        .build();

                blockstorageClient.deleteBootVolume(deleteRequest);
                log.debug("已发送删除引导卷请求，ID: {}", bootVolumeId);

                // 4. 等待删除完成
                final int MAX_WAIT_ATTEMPTS = 15;
                final int WAIT_INTERVAL_SECONDS = 10;

                for (int attempt = 0; attempt < MAX_WAIT_ATTEMPTS; attempt++) {
                    try {
                        GetBootVolumeRequest checkRequest = GetBootVolumeRequest.builder()
                                .bootVolumeId(bootVolumeId)
                                .build();

                        BootVolume.LifecycleState currentState = blockstorageClient
                                .getBootVolume(checkRequest)
                                .getBootVolume()
                                .getLifecycleState();

                        log.info("引导卷 {} 当前状态: {}, 尝试次数: {}/{}",
                                bootVolumeId, currentState.getValue(), attempt + 1, MAX_WAIT_ATTEMPTS);

                        if (currentState == BootVolume.LifecycleState.Terminated) {
                            log.debug("引导卷 {} 已成功删除", bootVolumeId);
                            response.put("success", true);
                            response.put("message", "引导卷已成功删除");
                            return response;
                        }

                    } catch (BmcException e) {
                        // 404错误表示引导卷已被删除
                        if (e.getStatusCode() == 404) {
                            log.debug("引导卷 {} 已成功删除（不存在）", bootVolumeId);
                            response.put("success", true);
                            response.put("message", "引导卷已成功删除");
                            return response;
                        }

                        log.error("检查引导卷删除状态时出错: {}", e.getMessage());
                        // 继续等待，可能是临时错误
                    }

                    // 等待后再次检查
                    try {
                        Thread.sleep(WAIT_INTERVAL_SECONDS * 1000L);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        log.debug("等待删除引导卷过程被中断");
                        response.put("message", "等待删除引导卷过程被中断，但删除请求已发送");
                        return response;
                    }
                }

                // 达到最大等待次数但未确认删除成功
                log.warn("引导卷 {} 删除操作超时，请稍后检查状态", bootVolumeId);
                response.put("message", "删除操作已发送但未能在预期时间内完成，请稍后检查引导卷状态");
                return response;

            } catch (Exception e) {
                log.error("删除引导卷 {} 时出错: {}", bootVolumeId, e.getMessage(), e);
                response.put("message", "删除引导卷失败: " + e.getMessage());
                return response;
            }
        } catch (Exception e) {
            log.error("创建OCI客户端时出错: {}", e.getMessage(), e);
            response.put("message", "创建OCI客户端失败: " + e.getMessage());
            return response;
        }
    }


    public static Region fromRegionId(String regionId) {
        try {
            return Region.fromRegionId(regionId);
        } catch (Exception e) {
            if (regionId.equals("ap-batam-1")) {
                return register("ap-batam-1", Realm.OC35, "bno");
            }
        }
        return null;
    }


    /**
     * 检查vcn和子网是否存在
     */
    public static boolean checkVcnAndSubnet(User user, String vcnId, String subnetId) {
        boolean flag = Boolean.FALSE;
        SimpleAuthenticationDetailsProvider provider = getProvider(user);
        String compartmentId = provider.getTenantId();
        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider);) {
            ListVcnsRequest listRequest = ListVcnsRequest.builder()
                    .compartmentId(compartmentId)
                    .build();
            ListVcnsResponse listVcnsResponse = virtualNetworkClient.listVcns(listRequest);
            if (!CollectionUtils.isEmpty(listVcnsResponse.getItems())) {
                for (Vcn item : listVcnsResponse.getItems()) {
                    if (item.getId().equals(vcnId)) {
                        List<Subnet> subnets = getVcnSubnets(virtualNetworkClient, compartmentId, vcnId);
                        if (!CollectionUtils.isEmpty(subnets)) {
                            flag = Boolean.TRUE;
                            break;
                        } else {
                            log.warn("checkVcnAndSubnet 子网不存在");
                        }
                    }
                }
            } else {
                log.warn("checkVcnAndSubnet vnc 不存在");
            }
        }
        return flag;
    }


    /**
     * 关闭三个月强制修改密码功能
     * 通过Identity Domains API设置密码策略来禁用密码过期
     *
     * @param tenant 租户信息
     * @return 操作结果，true表示成功，false表示失败
     */
    public static boolean disablePasswordExpirationWithAutoDomain(Tenant tenant) {
        log.debug("开始自动获取Domain URL并禁用密码过期功能");
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             IdentityDomainsClient identityDomainsClient = IdentityDomainsClient.builder()
                     .clientConfigurator(ProxyContext.get()).build(provider)) {
            String domainUrl = getDomain(identityClient, compartmentId);
            if (StringUtils.isEmpty(domainUrl)){
                log.warn("自动获取Domain URL失败");
                return false;
            }
            identityDomainsClient.setEndpoint(domainUrl);

            // 获取现有密码策略
            ListPasswordPoliciesRequest listRequest =
                    ListPasswordPoliciesRequest.builder()
                            .build();

            ListPasswordPoliciesResponse listResponse =
                    identityDomainsClient.listPasswordPolicies(listRequest);

            List<com.oracle.bmc.identitydomains.model.PasswordPolicy> passwordPolicies =
                    listResponse.getPasswordPolicies().getResources();

            if (passwordPolicies == null || passwordPolicies.isEmpty()) {
                log.warn("未找到任何密码策略");
                return false;
            }

            // 更新第一个密码策略
            for (PasswordPolicy currentPolicy : passwordPolicies) {
                log.debug("当前密码策略: {}", JSON.toJSONString(currentPolicy));
                Integer passwordExpiresAfter = currentPolicy.getPasswordExpiresAfter();
                PasswordPolicy.PasswordStrength passwordStrength = currentPolicy.getPasswordStrength();
                if (passwordExpiresAfter == null || passwordExpiresAfter == 0 || !passwordStrength.equals(PasswordPolicy.PasswordStrength.Custom)){
                    log.debug("{}当前策略不支持修改",currentPolicy.getName());
                    continue;
                }
                String policyId = currentPolicy.getId();

                log.info("更新密码策略: {}, 当前过期设置: {} 天",
                        currentPolicy.getName(), currentPolicy.getPasswordExpiresAfter());

                // 创建更新的密码策略 - 禁用过期
                com.oracle.bmc.identitydomains.model.PasswordPolicy.Builder policyBuilder =
                        com.oracle.bmc.identitydomains.model.PasswordPolicy.builder();
                policyBuilder.copy(currentPolicy)
                        .passwordExpiresAfter(0)  // 永不过期
                        .forcePasswordReset(false)  // 关闭强制重置
                        .passwordExpireWarning(7)  // 关闭过期警告
                        .build();


                // 执行更新
                com.oracle.bmc.identitydomains.requests.PutPasswordPolicyRequest updateRequest =
                        com.oracle.bmc.identitydomains.requests.PutPasswordPolicyRequest.builder()
                                .passwordPolicyId(policyId)
                                .passwordPolicy(policyBuilder.build())
                                .build();

                com.oracle.bmc.identitydomains.responses.PutPasswordPolicyResponse updateResponse =
                        identityDomainsClient.putPasswordPolicy(updateRequest);

                if (updateResponse.getPasswordPolicy() != null) {
                    log.info("{} 成功关闭三个月强制修改密码功能",currentPolicy.getName());
                }
            }
            return true;
        } catch (Exception e) {
            log.error("自动禁用密码过期功能时发生异常: {}", e.getMessage(), e);
        }
        return false;
    }


    /**
     * 自动启用密码过期功能
     * 这是一个完全自动化的方法，无需手动提供Domain Endpoint
     *
     * @param tenant 租户信息
     * @param expirationDays 密码过期天数，默认120天
     * @return 操作结果
     */
    public static boolean enablePasswordExpirationWithAutoDomain(Tenant tenant, Integer expirationDays) {
        log.info("开始自动获取Domain URL并启用密码过期功能");
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        int expireDays = expirationDays != null ? expirationDays : 120;

        try (IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             IdentityDomainsClient identityDomainsClient = IdentityDomainsClient.builder()
                     .clientConfigurator(ProxyContext.get()).build(provider)) {

            String domainUrl = getDomain(identityClient, compartmentId);

            if (domainUrl == null) {
                log.error("未找到活跃状态的Domain");
                return false;
            }

            identityDomainsClient.setEndpoint(domainUrl);

            // 获取现有密码策略
            com.oracle.bmc.identitydomains.requests.ListPasswordPoliciesRequest listRequest =
                        com.oracle.bmc.identitydomains.requests.ListPasswordPoliciesRequest.builder()
                                .build();

            com.oracle.bmc.identitydomains.responses.ListPasswordPoliciesResponse listResponse =
                        identityDomainsClient.listPasswordPolicies(listRequest);

            List<com.oracle.bmc.identitydomains.model.PasswordPolicy> passwordPolicies =
                        listResponse.getPasswordPolicies().getResources();

            if (passwordPolicies == null || passwordPolicies.isEmpty()) {
                log.warn("未找到任何密码策略");
                return false;
            }
            // 更新第一个密码策略
            for (PasswordPolicy currentPolicy : passwordPolicies) {
                log.info("正在处理密码策略: {}", JSON.toJSONString(currentPolicy));
                String policyId = currentPolicy.getId();
                PasswordPolicy.PasswordStrength passwordStrength = currentPolicy.getPasswordStrength();
                if (!passwordStrength.equals(PasswordPolicy.PasswordStrength.Custom)){
                    log.debug("{}当前策略不支持修改",currentPolicy.getName());
                    continue;
                }
                log.info("更新密码策略: {}, 设置过期天数: {} 天",
                        currentPolicy.getName(), expireDays);

                // 创建更新的密码策略 - 启用过期
                com.oracle.bmc.identitydomains.model.PasswordPolicy.Builder policyBuilder =
                        com.oracle.bmc.identitydomains.model.PasswordPolicy.builder();
                policyBuilder.copy(currentPolicy)
                        .passwordExpiresAfter(expireDays)  // 设置过期天数
                        .forcePasswordReset(false)  // 通常不强制立即重置
                        .passwordExpireWarning(7);  // 提前7天警告

                // 执行更新
                com.oracle.bmc.identitydomains.requests.PutPasswordPolicyRequest updateRequest =
                        com.oracle.bmc.identitydomains.requests.PutPasswordPolicyRequest.builder()
                                .passwordPolicyId(policyId)
                                .passwordPolicy(policyBuilder.build())
                                .build();

                com.oracle.bmc.identitydomains.responses.PutPasswordPolicyResponse updateResponse =
                        identityDomainsClient.putPasswordPolicy(updateRequest);

                if (updateResponse.getPasswordPolicy() != null) {
                    log.info("{}成功启用密码过期功能，过期天数: {} 天", currentPolicy.getName(),expireDays);
                }
            }
            return true;
        } catch (Exception e) {
            log.error("自动启用密码过期功能时发生异常: {}", e.getMessage(), e);
        }

        return false;
    }

    /**
     * 启用默认的90天密码过期策略
     *
     * @param tenant 租户信息
     * @return 操作结果
     */
    public static boolean enablePasswordExpirationWithAutoDomain(Tenant tenant) {
        return enablePasswordExpirationWithAutoDomain(tenant, 90);
    }

    //获取当前密码策略
    public static List<com.oracle.bmc.identitydomains.model.PasswordPolicy> getCurrentPasswordPolicy(Tenant tenant) {
        List<com.oracle.bmc.identitydomains.model.PasswordPolicy> passwordPolicies = new ArrayList<>();
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             IdentityDomainsClient identityDomainsClient = IdentityDomainsClient.builder()
                     .clientConfigurator(ProxyContext.get()).build(provider)){

            String domainUrl = getDomain(identityClient, compartmentId);
            if (StringUtils.isEmpty(domainUrl)){
                return new ArrayList<>();
            }
            identityDomainsClient.setEndpoint(domainUrl);

            // 获取现有密码策略
            ListPasswordPoliciesRequest listRequest =
                    ListPasswordPoliciesRequest.builder()
                            .build();
            ListPasswordPoliciesResponse listResponse =
                    identityDomainsClient.listPasswordPolicies(listRequest);
            passwordPolicies = listResponse.getPasswordPolicies().getResources();
        } catch (Exception e) {
            log.error("获取密码策略时发生异常: {}", e.getMessage(), e);
        }
        return passwordPolicies;
    }


    public static String getDomain(IdentityClient identityClient,String compartmentId){
        // 1. 自动获取Domain信息
        try {
            String domainUrl = StringUtils.EMPTY;
            com.oracle.bmc.identity.requests.ListDomainsRequest listDomainsRequest =
                    com.oracle.bmc.identity.requests.ListDomainsRequest.builder()
                            .compartmentId(compartmentId)
                            .build();

            com.oracle.bmc.identity.responses.ListDomainsResponse listDomainsResponse =
                    identityClient.listDomains(listDomainsRequest);

            List<com.oracle.bmc.identity.model.DomainSummary> domains = listDomainsResponse.getItems();

            if (domains == null || domains.isEmpty()) {
                log.error("未找到任何Identity Domain");
                return domainUrl;
            }

            for (com.oracle.bmc.identity.model.DomainSummary domain : domains) {
                if (domain.getLifecycleState() == com.oracle.bmc.identity.model.DomainSummary.LifecycleState.Active) {
                    domainUrl = domain.getUrl();
                    log.debug("找到活跃Domain: {} - URL: {}", domain.getDisplayName(), domainUrl);
                    break;
                }
            }

            return domainUrl;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }finally {
            if (identityClient != null){
                identityClient.close();
            }
        }
    }


    private static LaunchInstanceDetails createLaunchInstanceDetailsFromBootVolume(
            LaunchInstanceDetails launchInstanceDetails, BootVolume bootVolume) throws Exception {

        InstanceSourceViaBootVolumeDetails instanceSourceViaBootVolumeDetails =
                InstanceSourceViaBootVolumeDetails.builder()
                        .bootVolumeId(bootVolume.getId())
                        .build();
        LaunchInstanceAgentConfigDetails launchInstanceAgentConfigDetails =
                LaunchInstanceAgentConfigDetails.builder().isMonitoringDisabled(true).build();
        return LaunchInstanceDetails.builder()
                .copy(launchInstanceDetails)
                .sourceDetails(instanceSourceViaBootVolumeDetails)
                .agentConfig(launchInstanceAgentConfigDetails)
                .build();
    }


    public static List<String> findCompartmentList(IdentityClient identityClient, String tenantId) {
        ListCompartmentsRequest request = ListCompartmentsRequest.builder()
                .compartmentId(tenantId)
                .compartmentIdInSubtree(true)
                .accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                .build();

        ListCompartmentsResponse response = identityClient.listCompartments(request);
        List<Compartment> compartments = response.getItems();

        List<String> result = new ArrayList<>();

        if (compartments != null && !compartments.isEmpty()) {
            // 过滤 Active 状态并提取 ID
            List<String> activeList = compartments.stream()
                    .filter(c -> c.getLifecycleState().equals(Compartment.LifecycleState.Active))
                    .map(Compartment::getId)
                    .collect(Collectors.toList());

            result.addAll(activeList);
        }

        // 始终追加 tenantId
        result.add(tenantId);

        return result;
    }

    /**
     * @Description: 为指定用户生成一个新的 Auth Token
     * @Param: [provider, userId, description]
     * @return: String 生成的明文 Token（请务必保存，后续无法再次获取）
     */
    public static String generateAuthToken(SimpleAuthenticationDetailsProvider provider, String userId, String description) {
        try (IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 1. 构建 Token 描述信息
            CreateAuthTokenDetails tokenDetails = CreateAuthTokenDetails.builder()
                    .description(description)
                    .build();

            // 2. 构建创建请求
            CreateAuthTokenRequest request = CreateAuthTokenRequest.builder()
                    .userId(userId)
                    .createAuthTokenDetails(tokenDetails)
                    .build();

            // 3. 发送请求并获取响应
            CreateAuthTokenResponse response = identityClient.createAuthToken(request);

            // 4. 提取明文 Token
            // 唯一一次能通过 API 拿到这段明文密码的机会！
            String rawToken = response.getAuthToken().getToken();

            log.info("成功为用户 {} 生成了 Auth Token (描述: {})", userId, description);

            return rawToken;

        } catch (Exception e) {
            log.error("生成 Auth Token 失败, 用户 ID: {}, 错误信息: {}", userId, e.getMessage(), e);
            throw new RuntimeException("生成 Auth Token 失败", e);
        }
    }
}
