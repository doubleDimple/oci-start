package com.doubledimple.ociserver.utils.oracle.vnic;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.AttachVnicDetails;
import com.oracle.bmc.core.model.CreateSubnetDetails;
import com.oracle.bmc.core.model.CreateVnicDetails;
import com.oracle.bmc.core.model.CreateIpv6Details;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.Ipv6;
import com.oracle.bmc.core.model.Subnet;
import com.oracle.bmc.core.model.Vcn;
import com.oracle.bmc.core.model.Vnic;
import com.oracle.bmc.core.model.VnicAttachment;
import com.oracle.bmc.core.requests.AttachVnicRequest;
import com.oracle.bmc.core.requests.CreateIpv6Request;
import com.oracle.bmc.core.requests.CreateSubnetRequest;
import com.oracle.bmc.core.requests.DetachVnicRequest;
import com.oracle.bmc.core.requests.GetInstanceRequest;
import com.oracle.bmc.core.requests.GetSubnetRequest;
import com.oracle.bmc.core.requests.GetVnicRequest;
import com.oracle.bmc.core.requests.GetVnicAttachmentRequest;
import com.oracle.bmc.core.requests.ListInstancesRequest;
import com.oracle.bmc.core.requests.ListIpv6sRequest;
import com.oracle.bmc.core.requests.ListSubnetsRequest;
import com.oracle.bmc.core.requests.ListVcnsRequest;
import com.oracle.bmc.core.requests.ListVnicAttachmentsRequest;
import com.oracle.bmc.core.requests.DeleteIpv6Request;
import com.oracle.bmc.core.responses.AttachVnicResponse;
import com.oracle.bmc.core.responses.CreateIpv6Response;
import com.oracle.bmc.core.responses.CreateSubnetResponse;
import com.oracle.bmc.core.responses.DetachVnicResponse;
import com.oracle.bmc.core.responses.GetInstanceResponse;
import com.oracle.bmc.core.responses.GetSubnetResponse;
import com.oracle.bmc.core.responses.GetVnicResponse;
import com.oracle.bmc.core.responses.GetVnicAttachmentResponse;
import com.oracle.bmc.core.responses.ListInstancesResponse;
import com.oracle.bmc.core.responses.ListIpv6sResponse;
import com.oracle.bmc.core.responses.ListSubnetsResponse;
import com.oracle.bmc.core.responses.ListVcnsResponse;
import com.oracle.bmc.core.responses.ListVnicAttachmentsResponse;
import com.oracle.bmc.core.responses.DeleteIpv6Response;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.Compartment;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.apache.http.conn.ConnectTimeoutException;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.TimeUnit;

import static com.doubledimple.ociserver.config.constant.SystemScriptShell.subnetName;
import static com.doubledimple.ociserver.service.oracle.OracleCloudService.findRootCompartment;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.createOrUpdateSubnet;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.findCompartmentList;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @version 1.0.0
 * @ClassName VnicManagementUtils
 * @Description VNIC管理工具类，用于创建、管理VNIC及其IPv6地址
 * @Author doubleDimple
 * @Date 2025-01-16 10:00
 */
@Slf4j
public class VnicManagementUtils {

    private static final int DEFAULT_TIMEOUT_SECONDS = 300; // 5分钟超时
    private static final int MAX_IPV6_PER_VNIC = 32; // 每个VNIC最多32个IPv6地址
    private static final int MAX_VNIC_PER_INSTANCE = 32; // 每个实例最多32个VNIC（包括主VNIC）
    private static final int POLL_INTERVAL_SECONDS = 3; // 轮询间隔


    /**
     * 为实例创建多个VNIC，每个VNIC可以创建多个IPv6地址
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @param vnicCount 要创建的VNIC数量
     * @param ipv6CountPerVnic 每个VNIC创建的IPv6地址数量（最多32个）
     * @return 批量创建结果
     */
    public static BatchVnicCreationResult createMultipleVnicsWithIpv6(Tenant tenant, String instanceId,
                                                                      int vnicCount, int ipv6CountPerVnic, InstanceDetails instanceDetails,
                                                                      String subnetId,
                                                                      Boolean isCreateSubnet) {
        long startTime = System.currentTimeMillis();
        BatchVnicCreationResult batchResult = new BatchVnicCreationResult();
        String availabilityDomain = instanceDetails.getAvailabilityDomain();
        try {
            log.debug("开始为实例 {} 创建 {} 个VNIC，每个VNIC创建 {} 个IPv6地址",
                    instanceId, vnicCount, ipv6CountPerVnic);

            //创建新的子网,
            if (isCreateSubnet){
                Subnet subnet = doCreateSubnet(tenant, instanceId, availabilityDomain);
                if (null == subnet){
                    throw new IllegalArgumentException("创建子网失败");
                }
                subnetId = subnet.getId();
            }


            // 参数验证
            if (vnicCount <= 0 || vnicCount > MAX_VNIC_PER_INSTANCE) {
                throw new IllegalArgumentException("VNIC数量必须在1到" + MAX_VNIC_PER_INSTANCE + "之间");
            }

            if (ipv6CountPerVnic < 0 || ipv6CountPerVnic > MAX_IPV6_PER_VNIC) {
                throw new IllegalArgumentException("每个VNIC的IPv6地址数量必须在0到" + MAX_IPV6_PER_VNIC + "之间");
            }

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            // 获取实例信息
            Instance instance = getInstance(provider, tenant, instanceId);
            if (instance == null) {
                throw new RuntimeException("找不到指定的实例: " + instanceId);
            }

            // 验证子网是否支持IPv6
            boolean subnetSupportsIpv6 = false;
            if (ipv6CountPerVnic > 0) {
                subnetSupportsIpv6 = checkSubnetIpv6Support(provider, tenant, subnetId);
                if (!subnetSupportsIpv6) {
                    log.warn("子网 {} 不支持IPv6，将跳过IPv6地址创建", subnetId);
                    ipv6CountPerVnic = 0;
                }
            }

            // 设置批量结果基本信息
            batchResult.setInstanceId(instanceId);
            batchResult.setInstanceDisplayName(instance.getDisplayName());
            batchResult.setRequestedVnicCount(vnicCount);
            batchResult.setRequestedIpv6CountPerVnic(ipv6CountPerVnic);

            // 批量创建VNIC
            for (int i = 0; i < vnicCount; i++) {
                try {
                    String vnicDisplayName = String.format("vnic-%s-%d",
                            instance.getDisplayName(), i + 1);

                    VnicCreationResult vnicResult = createSingleVnicWithIpv6(
                            provider, tenant, instanceId, subnetId,
                            vnicDisplayName, ipv6CountPerVnic, subnetSupportsIpv6);
                    if (!vnicResult.isSuccess()){
                        log.error("创建VNIC失败: {}", vnicResult.getErrorMessage());
                        batchResult.setAllSuccessful(false);
                        batchResult.setSummary("批量创建VNIC失败");
                        batchResult.setTotalExecutionTimeMs(System.currentTimeMillis() - startTime);
                        return batchResult;
                    }
                    batchResult.getVnicResults().add(vnicResult);

                    if (vnicResult.isSuccess()) {
                        batchResult.setSuccessfulVnicCount(batchResult.getSuccessfulVnicCount() + 1);
                        batchResult.setTotalIpv6Count(batchResult.getTotalIpv6Count() +
                                vnicResult.getIpv6Addresses().size());
                    } else {
                        batchResult.setAllSuccessful(false);
                        log.error("创建VNIC {} 失败: {}", vnicDisplayName, vnicResult.getErrorMessage());
                    }

                    log.debug("VNIC创建进度: {}/{}", i + 1, vnicCount);

                } catch (Exception e) {
                    log.error("创建第 {} 个VNIC时发生异常: {}", i + 1, e.getMessage(), e);

                    VnicCreationResult errorResult = new VnicCreationResult();
                    errorResult.setVnicDisplayName(String.format("vnic-%s-%d",
                            instance.getDisplayName(), i + 1));
                    errorResult.setSuccess(false);
                    errorResult.setErrorMessage(e.getMessage());
                    batchResult.getVnicResults().add(errorResult);
                    batchResult.setAllSuccessful(false);
                }
            }

            // 生成总结
            long executionTime = System.currentTimeMillis() - startTime;
            batchResult.setTotalExecutionTimeMs(executionTime);

            String summary = String.format(
                    "实例 %s 的VNIC创建完成 - 成功: %d/%d, IPv6地址: %d个, 耗时: %dms",
                    instanceId, batchResult.getSuccessfulVnicCount(), vnicCount,
                    batchResult.getTotalIpv6Count(), executionTime);

            batchResult.setSummary(summary);

            log.debug(summary);
            return batchResult;

        } catch (Exception e) {
            log.error("批量创建VNIC失败: " + e.getMessage(), e);

            batchResult.setAllSuccessful(false);
            batchResult.setSummary("批量创建VNIC失败: " + e.getMessage());
            batchResult.setTotalExecutionTimeMs(System.currentTimeMillis() - startTime);

            return batchResult;
        }
    }

    private static Subnet doCreateSubnet(Tenant tenant,String instanceId,String availabilityDomain) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        final String compartmentId = provider.getTenantId();
        Subnet subnet = null;
        try(VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)){
            //获取vcn
            ListVcnsRequest build = ListVcnsRequest.builder().compartmentId(compartmentId)
                    .build();

            ListVcnsResponse listVcnsResponse = virtualNetworkClient.listVcns(build);
            if (listVcnsResponse.getItems().size() > 0) {
                List<Vcn> items = listVcnsResponse.getItems();
                Vcn vcnDetail = Optional.ofNullable(items)
                        .orElse(Collections.emptyList())
                        .stream()
                        .filter(vcn -> vcn.getIpv6CidrBlocks() != null)
                        .filter(vcn -> !vcn.getIpv6CidrBlocks().isEmpty())
                        .findFirst().orElse(null);

                if (null != vcnDetail){

                    ListSubnetsRequest listRequest = ListSubnetsRequest.builder()
                            .compartmentId(compartmentId)
                            .vcnId(vcnDetail.getId())
                            .build();
                    ListSubnetsResponse listResponse = virtualNetworkClient.listSubnets(listRequest);
                    List<String> subnetIpv6CidrBlocks = new ArrayList<>();
                    List<String> subnetCidrBlocks = new ArrayList<>();
                    Optional.ofNullable(listResponse.getItems())
                            .orElse(Collections.emptyList())
                            .stream()
                            .filter(subnetAlready -> subnetAlready.getIpv6CidrBlock() != null)
                            .forEach(subnetAlready -> {
                                subnetIpv6CidrBlocks.add(subnetAlready.getIpv6CidrBlock());
                            });

                    Optional.ofNullable(listResponse.getItems())
                            .orElse(Collections.emptyList())
                            .stream()
                            .filter(subnetAlready -> subnetAlready.getCidrBlock() != null)
                            .forEach(subnetAlready -> {
                                subnetCidrBlocks.add(subnetAlready.getCidrBlock());
                            });


                    String nextAvailableCidr = getNextAvailableCidr(subnetCidrBlocks);
                    List<String> ipv6CidrBlocks = vcnDetail.getIpv6CidrBlocks();


                    String nextAvailableIpv6Cidr = getNextAvailableIpv6Cidr(ipv6CidrBlocks, subnetIpv6CidrBlocks);
                    //创建子网
                    long timestamp = System.currentTimeMillis() % 100000;
                    String dnsLabel = "subnet" + timestamp;  // subnet12345
                    CreateSubnetDetails createSubnetDetails =
                            CreateSubnetDetails.builder()
                                    //.availabilityDomain(availabilityDomain)
                                    .compartmentId(compartmentId)
                                    .displayName(subnetName)
                                    .cidrBlock(nextAvailableCidr)
                                    .vcnId(vcnDetail.getId())
                                    .ipv6CidrBlock(nextAvailableIpv6Cidr)
                                    .routeTableId(vcnDetail.getDefaultRouteTableId())
                                    .dnsLabel(dnsLabel)  // 关键：启用DNS
                                    .build();
                    CreateSubnetRequest createSubnetRequest =
                            CreateSubnetRequest.builder().createSubnetDetails(createSubnetDetails).build();
                    CreateSubnetResponse createSubnetResponse =
                            virtualNetworkClient.createSubnet(createSubnetRequest);

                    GetSubnetRequest getSubnetRequest =
                            GetSubnetRequest.builder()
                                    .subnetId(createSubnetResponse.getSubnet().getId())
                                    .build();
                    GetSubnetResponse getSubnetResponse =
                            virtualNetworkClient
                                    .getWaiters()
                                    .forSubnet(getSubnetRequest, Subnet.LifecycleState.Available)
                                    .execute();
                    subnet = getSubnetResponse.getSubnet();

                    if (log.isDebugEnabled()){
                        log.debug("Created Subnet: " + subnet.getId());
                        log.debug("subnet: [{}]", subnet);
                        log.debug("");
                    }
                }
            }
        }catch (Exception e){
            log.error("createSubnet error: ", e);
            return null;
        }
        return subnet;
    }

    /**
     * 为单个VNIC创建IPv6地址
     *
     * @param tenant 租户信息
     * @param vnicId VNIC ID
     * @param ipv6Count 要创建的IPv6地址数量
     * @return IPv6创建结果列表
     */
    public static List<Ipv6CreationResult> createIpv6ForVnic(Tenant tenant, String vnicId, int ipv6Count) {
        List<Ipv6CreationResult> results = new ArrayList<>();

        try {
            log.info("开始为VNIC {} 创建 {} 个IPv6地址", vnicId, ipv6Count);

            if (ipv6Count <= 0 || ipv6Count > MAX_IPV6_PER_VNIC) {
                throw new IllegalArgumentException("IPv6地址数量必须在1到" + MAX_IPV6_PER_VNIC + "之间");
            }

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                for (int i = 0; i < ipv6Count; i++) {
                    Ipv6CreationResult result = createSingleIpv6(networkClient, vnicId, i + 1);
                    results.add(result);

                    if (result.isSuccess()) {
                        log.info("IPv6地址创建成功: {} ({})", result.getIpv6Address(), result.getIpv6Id());
                    } else {
                        log.error("IPv6地址创建失败: {}", result.getErrorMessage());
                    }
                }
            }

            long successCount = results.stream().mapToLong(r -> r.isSuccess() ? 1 : 0).sum();
            log.info("VNIC {} 的IPv6地址创建完成 - 成功: {}/{}", vnicId, successCount, ipv6Count);

        } catch (Exception e) {
            log.error("为VNIC创建IPv6地址失败: " + e.getMessage(), e);

            // 如果出现异常且结果列表为空，添加一个错误结果
            if (results.isEmpty()) {
                Ipv6CreationResult errorResult = new Ipv6CreationResult();
                errorResult.setVnicId(vnicId);
                errorResult.setSuccess(false);
                errorResult.setErrorMessage(e.getMessage());
                results.add(errorResult);
            }
        }

        return results;
    }

    /**
     * 删除实例的指定VNIC及其所有IPv6地址
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @param vnicId VNIC ID
     * @return 是否删除成功
     */
    public static boolean deleteVnicWithIpv6(Tenant tenant, String instanceId, String vnicId) {
        try {
            log.info("开始删除实例 {} 的VNIC {} 及其IPv6地址", instanceId, vnicId);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            // 1. 删除VNIC上的所有IPv6地址
            boolean ipv6DeleteSuccess = deleteAllIpv6FromVnic(provider, tenant, vnicId);

            // 2. 删除VNIC附件
            boolean vnicDeleteSuccess = detachVnicFromInstance(provider, tenant, instanceId, vnicId);

            boolean overallSuccess = ipv6DeleteSuccess && vnicDeleteSuccess;

            if (overallSuccess) {
                log.info("VNIC {} 及其IPv6地址删除成功", vnicId);
            } else {
                log.warn("VNIC {} 删除过程中遇到问题 - IPv6删除: {}, VNIC删除: {}",
                        vnicId, ipv6DeleteSuccess, vnicDeleteSuccess);
            }

            return overallSuccess;

        } catch (Exception e) {
            log.error("删除VNIC失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 获取实例的所有VNIC信息
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return VNIC信息列表
     */
    public static List<VnicCreationResult> getInstanceVnics(Tenant tenant, String instanceId,String compartmentId) {
        List<VnicCreationResult> vnicInfos = new ArrayList<>();

        try {
            log.debug("获取实例 {} 的所有VNIC信息", instanceId);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            if (StringUtils.isBlank(compartmentId)){
                compartmentId = provider.getTenantId();
            }
            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
                 VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                    // 获取实例的所有VNIC附件
                    ListVnicAttachmentsRequest request = ListVnicAttachmentsRequest.builder()
                            .compartmentId(compartmentId)
                            .instanceId(instanceId)
                            .build();

                    ListVnicAttachmentsResponse response = computeClient.listVnicAttachments(request);
                    for (VnicAttachment attachment : response.getItems()) {
                        try {
                            VnicCreationResult vnicInfo = new VnicCreationResult();
                            vnicInfo.setAttachmentId(attachment.getId());
                            vnicInfo.setVnicId(attachment.getVnicId());
                            vnicInfo.setLifecycleState(attachment.getLifecycleState());
                            vnicInfo.setSuccess(attachment.getLifecycleState() == VnicAttachment.LifecycleState.Attached);

                            // 获取VNIC详情
                            if (attachment.getVnicId() != null) {
                                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                                        .vnicId(attachment.getVnicId())
                                        .build();

                                GetVnicResponse getVnicResponse = null;
                                try {
                                    getVnicResponse = networkClient.getVnic(getVnicRequest);
                                } catch (Exception e) {
                                    log.debug("获取实例VNIC信息失败: vnic可能被删除");
                                    continue;
                                }
                                Vnic vnic = getVnicResponse.getVnic();
                                Boolean isPrimary = vnic.getIsPrimary();
                                vnicInfo.setVnicDisplayName(vnic.getDisplayName());
                                vnicInfo.setPrivateIp(vnic.getPrivateIp());
                                vnicInfo.setPublicIp(vnic.getPublicIp());
                                vnicInfo.setSubnetId(vnic.getSubnetId());
                                vnicInfo.setIsPrimary(isPrimary);

                                // 获取IPv6地址
                                List<String> ipv6Addresses = getVnicIpv6Addresses(networkClient, attachment.getVnicId());
                                vnicInfo.setIpv6Addresses(ipv6Addresses);
                            }

                            vnicInfos.add(vnicInfo);

                        } catch (Exception e) {
                            log.error("获取VNIC {} 详情失败: {}", attachment.getVnicId(), e.getMessage());

                            VnicCreationResult errorInfo = new VnicCreationResult();
                            errorInfo.setAttachmentId(attachment.getId());
                            errorInfo.setVnicId(attachment.getVnicId());
                            errorInfo.setSuccess(false);
                            errorInfo.setErrorMessage(e.getMessage());
                            vnicInfos.add(errorInfo);
                        }
                    }
            }

            log.debug("实例 {} 共有 {} 个VNIC", instanceId, vnicInfos.size());

        } catch (Exception e) {
            if (e instanceof ConnectTimeoutException){
                log.warn("获取实例VNIC信息失败: fail:{}","conn timeout");
            }else {
                log.error("获取实例VNIC信息失败: " + e.getMessage(), e);
            }
        }

        return vnicInfos;
    }


    /**
     * 创建单个VNIC并为其创建IPv6地址
     */
    private static VnicCreationResult createSingleVnicWithIpv6(SimpleAuthenticationDetailsProvider provider,
                                                               Tenant tenant, String instanceId, String subnetId,
                                                               String vnicDisplayName, int ipv6Count,
                                                               boolean subnetSupportsIpv6) {
        VnicCreationResult result = new VnicCreationResult();
        result.setVnicDisplayName(vnicDisplayName);
        result.setSubnetId(subnetId);

        try {
            log.info("开始创建VNIC: {}", vnicDisplayName);

            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
                 VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
                networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 1. 创建VNIC详情
                CreateVnicDetails createVnicDetails = CreateVnicDetails.builder()
                        .subnetId(subnetId)
                        .displayName(vnicDisplayName)
                        .assignPrivateDnsRecord(true)
                        .hostnameLabel(genHostName())
                        .skipSourceDestCheck(false)
                        .assignPublicIp(true)
                        .build();

                AttachVnicDetails attachVnicDetails = AttachVnicDetails.builder()
                        .instanceId(instanceId)
                        .createVnicDetails(createVnicDetails)
                        .build();

                // 2. 附加VNIC到实例
                AttachVnicRequest attachRequest = AttachVnicRequest.builder()
                        .attachVnicDetails(attachVnicDetails)
                        .build();

                AttachVnicResponse attachResponse = computeClient.attachVnic(attachRequest);
                VnicAttachment attachment = attachResponse.getVnicAttachment();

                result.setAttachmentId(attachment.getId());
                result.setVnicId(attachment.getVnicId());

                // 3. 等待VNIC附加完成
                VnicAttachment attachedVnic = waitForVnicAttachment(computeClient, attachment.getId());
                if (attachedVnic == null || attachedVnic.getLifecycleState() != VnicAttachment.LifecycleState.Attached) {
                    throw new RuntimeException("VNIC附加超时或失败");
                }

                result.setLifecycleState(attachedVnic.getLifecycleState());

                // 4. 获取VNIC详情
                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                        .vnicId(attachedVnic.getVnicId())
                        .build();

                GetVnicResponse getVnicResponse = networkClient.getVnic(getVnicRequest);
                Vnic vnic = getVnicResponse.getVnic();

                result.setPrivateIp(vnic.getPrivateIp());
                result.setPublicIp(vnic.getPublicIp());

                // 5. 为VNIC创建IPv6地址
                if (ipv6Count > 0 && subnetSupportsIpv6) {
                    List<Ipv6CreationResult> ipv6Results = createIpv6ForVnic(tenant, attachedVnic.getVnicId(), ipv6Count);

                    for (Ipv6CreationResult ipv6Result : ipv6Results) {
                        if (ipv6Result.isSuccess()) {
                            result.getIpv6Addresses().add(ipv6Result.getIpv6Address());
                            result.getIpv6Ids().add(ipv6Result.getIpv6Id());
                        }
                    }
                }

                result.setSuccess(true);
                log.info("VNIC创建成功: {} (ID: {}, 私有IP: {}, 公网IP: {}, IPv6数: {})",
                        vnicDisplayName, result.getVnicId(), result.getPrivateIp(),
                        result.getPublicIp(), result.getIpv6Addresses().size());

            }

        } catch (Exception e) {
            log.error("创建VNIC失败: " + e.getMessage(), e);
            result.setSuccess(false);
            result.setErrorMessage(e.getMessage());
        }

        return result;
    }

    private static String genHostName() {
        String baseHostname = "oci-start-hn";
        Random random = new Random();
        StringBuilder sb = new StringBuilder(baseHostname);
        // 添加6个随机字母
        for (int i = 0; i < 6; i++) {
            char randomLetter = (char) ('a' + random.nextInt(26)); // 生成a-z的随机字母
            sb.append(randomLetter);
        }
        return sb.toString();
    }

    /**
     * 创建单个IPv6地址
     */
    private static Ipv6CreationResult createSingleIpv6(VirtualNetworkClient networkClient, String vnicId, int index) {
        Ipv6CreationResult result = new Ipv6CreationResult();
        result.setVnicId(vnicId);

        try {
            CreateIpv6Details createIpv6Details = CreateIpv6Details.builder()
                    .vnicId(vnicId)
                    .displayName(String.format("ipv6-%d", index))
                    .build();

            CreateIpv6Request createIpv6Request = CreateIpv6Request.builder()
                    .createIpv6Details(createIpv6Details)
                    .build();

            CreateIpv6Response createIpv6Response = networkClient.createIpv6(createIpv6Request);
            Ipv6 ipv6 = createIpv6Response.getIpv6();

            result.setIpv6Id(ipv6.getId());
            result.setIpv6Address(ipv6.getIpAddress());
            result.setSuccess(true);

        } catch (Exception e) {
            log.error("创建IPv6地址失败: " + e.getMessage(), e);
            result.setSuccess(false);
            result.setErrorMessage(e.getMessage());
        }

        return result;
    }

    /**
     * 等待VNIC附加完成
     */
    private static VnicAttachment waitForVnicAttachment(ComputeClient computeClient, String attachmentId) {
        try {
            int maxAttempts = DEFAULT_TIMEOUT_SECONDS / POLL_INTERVAL_SECONDS;

            for (int attempt = 0; attempt < maxAttempts; attempt++) {
                try {
                    // 使用GetVnicAttachmentRequest获取特定的VNIC附件
                    GetVnicAttachmentRequest request = GetVnicAttachmentRequest.builder()
                            .vnicAttachmentId(attachmentId)
                            .build();

                    GetVnicAttachmentResponse response = computeClient.getVnicAttachment(request);
                    VnicAttachment attachment = response.getVnicAttachment();

                    if (attachment.getLifecycleState() == VnicAttachment.LifecycleState.Attached) {
                        return attachment;
                    } else if (attachment.getLifecycleState() == VnicAttachment.LifecycleState.Detached) {
                        throw new RuntimeException("VNIC附加失败，状态为: " + attachment.getLifecycleState());
                    }

                    log.debug("VNIC附加中，状态: {}, 尝试: {}/{}",
                            attachment.getLifecycleState(), attempt + 1, maxAttempts);

                } catch (Exception e) {
                    if (e.getMessage() != null && e.getMessage().contains("NotFound")) {
                        log.debug("VNIC附件尚未创建完成，继续等待...");
                    } else {
                        throw e;
                    }
                }

                try {
                    TimeUnit.SECONDS.sleep(POLL_INTERVAL_SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("等待VNIC附加被中断", e);
                }
            }

            throw new RuntimeException("等待VNIC附加超时");

        } catch (Exception e) {
            log.error("等待VNIC附加失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 获取实例信息
     */
    private static Instance getInstance(SimpleAuthenticationDetailsProvider provider, Tenant tenant,
                                        String instanceId) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            GetInstanceRequest request = GetInstanceRequest.builder()
                    .instanceId(instanceId)
                    .build();

            GetInstanceResponse response = computeClient.getInstance(request);
            return response.getInstance();

        } catch (Exception e) {
            log.error("获取实例信息失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 检查子网是否支持IPv6
     */
    private static boolean checkSubnetIpv6Support(SimpleAuthenticationDetailsProvider provider, Tenant tenant, String subnetId) {
        try (VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            GetSubnetRequest request = GetSubnetRequest.builder()
                    .subnetId(subnetId)
                    .build();

            GetSubnetResponse response = networkClient.getSubnet(request);
            Subnet subnet = response.getSubnet();

            // 检查子网的IPv6CIDR块
            boolean hasIpv6Cidr = subnet.getIpv6CidrBlocks() != null && !subnet.getIpv6CidrBlocks().isEmpty();

            log.info("子网 {} IPv6支持状态: {}", subnetId, hasIpv6Cidr);
            return hasIpv6Cidr;

        } catch (Exception e) {
            log.error("检查子网IPv6支持失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 获取VNIC的IPv6地址列表
     */
    private static List<String> getVnicIpv6Addresses(VirtualNetworkClient networkClient, String vnicId) {
        List<String> ipv6Addresses = new ArrayList<>();

        try {
            ListIpv6sRequest request = ListIpv6sRequest.builder()
                    .vnicId(vnicId)
                    .build();

            ListIpv6sResponse response = networkClient.listIpv6s(request);

            for (Ipv6 ipv6 : response.getItems()) {
                ipv6Addresses.add(ipv6.getIpAddress());
            }

        } catch (Exception e) {
            log.error("获取VNIC IPv6地址失败: " + e.getMessage(), e);
        }

        return ipv6Addresses;
    }

    /**
     * 获取实例的主VNIC信息
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return 主VNIC信息，如果找不到则返回null
     */
    public static VnicCreationResult getPrimaryVnic(Tenant tenant, String instanceId) {
        try {
            log.info("获取实例 {} 的主VNIC信息", instanceId);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            String compartmentId = provider.getTenantId();
            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
                 VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
                networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 获取实例的所有VNIC附件
                ListVnicAttachmentsRequest request = ListVnicAttachmentsRequest.builder()
                        .compartmentId(compartmentId)
                        .instanceId(instanceId)
                        .build();

                ListVnicAttachmentsResponse response = computeClient.listVnicAttachments(request);

                for (VnicAttachment attachment : response.getItems()) {
                    if (isPrimaryVnic(compartmentId,computeClient, instanceId, attachment.getVnicId())) {
                        VnicCreationResult primaryVnicInfo = new VnicCreationResult();
                        primaryVnicInfo.setAttachmentId(attachment.getId());
                        primaryVnicInfo.setVnicId(attachment.getVnicId());
                        primaryVnicInfo.setLifecycleState(attachment.getLifecycleState());
                        primaryVnicInfo.setSuccess(attachment.getLifecycleState() == VnicAttachment.LifecycleState.Attached);

                        // 获取VNIC详情
                        if (attachment.getVnicId() != null) {
                            GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                                    .vnicId(attachment.getVnicId())
                                    .build();

                            GetVnicResponse getVnicResponse = networkClient.getVnic(getVnicRequest);
                            Vnic vnic = getVnicResponse.getVnic();

                            primaryVnicInfo.setVnicDisplayName(vnic.getDisplayName());
                            primaryVnicInfo.setPrivateIp(vnic.getPrivateIp());
                            primaryVnicInfo.setPublicIp(vnic.getPublicIp());
                            primaryVnicInfo.setSubnetId(vnic.getSubnetId());

                            // 获取IPv6地址
                            List<String> ipv6Addresses = getVnicIpv6Addresses(networkClient, attachment.getVnicId());
                            primaryVnicInfo.setIpv6Addresses(ipv6Addresses);
                        }

                        log.debug("找到主VNIC: {} ({})", primaryVnicInfo.getVnicDisplayName(), primaryVnicInfo.getVnicId());
                        return primaryVnicInfo;
                    }
                }
            }

            log.warn("未找到实例 {} 的主VNIC", instanceId);
            return null;

        } catch (Exception e) {
            log.error("获取主VNIC信息失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 获取实例的所有辅助VNIC信息（排除主VNIC）
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return 辅助VNIC信息列表
     */
    public static List<VnicCreationResult> getSecondaryVnics(Tenant tenant, String instanceId) {
        List<VnicCreationResult> secondaryVnics = new ArrayList<>();

        try {
            log.info("获取实例 {} 的所有辅助VNIC信息", instanceId);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            final String compartmentId = provider.getTenantId();
            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
                 VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
                networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 获取实例的所有VNIC附件
                ListVnicAttachmentsRequest request = ListVnicAttachmentsRequest.builder()
                        .compartmentId(compartmentId)
                        .instanceId(instanceId)
                        .build();

                ListVnicAttachmentsResponse response = computeClient.listVnicAttachments(request);

                for (VnicAttachment attachment : response.getItems()) {
                    // 跳过主VNIC
                    if (isPrimaryVnic(compartmentId,computeClient, instanceId, attachment.getVnicId())) {
                        continue;
                    }

                    try {
                        VnicCreationResult vnicInfo = new VnicCreationResult();
                        vnicInfo.setAttachmentId(attachment.getId());
                        vnicInfo.setVnicId(attachment.getVnicId());
                        vnicInfo.setLifecycleState(attachment.getLifecycleState());
                        vnicInfo.setSuccess(attachment.getLifecycleState() == VnicAttachment.LifecycleState.Attached);

                        // 获取VNIC详情
                        if (attachment.getVnicId() != null) {
                            GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                                    .vnicId(attachment.getVnicId())
                                    .build();

                            GetVnicResponse getVnicResponse = networkClient.getVnic(getVnicRequest);
                            Vnic vnic = getVnicResponse.getVnic();

                            vnicInfo.setVnicDisplayName(vnic.getDisplayName());
                            vnicInfo.setPrivateIp(vnic.getPrivateIp());
                            vnicInfo.setPublicIp(vnic.getPublicIp());
                            vnicInfo.setSubnetId(vnic.getSubnetId());

                            // 获取IPv6地址
                            List<String> ipv6Addresses = getVnicIpv6Addresses(networkClient, attachment.getVnicId());
                            vnicInfo.setIpv6Addresses(ipv6Addresses);
                        }

                        secondaryVnics.add(vnicInfo);

                    } catch (Exception e) {
                        log.error("获取辅助VNIC {} 详情失败: {}", attachment.getVnicId(), e.getMessage());

                        VnicCreationResult errorInfo = new VnicCreationResult();
                        errorInfo.setAttachmentId(attachment.getId());
                        errorInfo.setVnicId(attachment.getVnicId());
                        errorInfo.setSuccess(false);
                        errorInfo.setErrorMessage(e.getMessage());
                        secondaryVnics.add(errorInfo);
                    }
                }
            }

            log.info("实例 {} 共有 {} 个辅助VNIC", instanceId, secondaryVnics.size());

        } catch (Exception e) {
            log.error("获取辅助VNIC信息失败: " + e.getMessage(), e);
        }

        return secondaryVnics;
    }

    /**
     * 判断VNIC是否为主VNIC
     *
     * @param computeClient 计算客户端
     * @param instanceId 实例ID
     * @param vnicId VNIC ID
     * @return 是否为主VNIC
     */
    private static boolean isPrimaryVnic(String compartmentId, ComputeClient computeClient, String instanceId, String vnicId) {
        try {
            // 获取实例的所有VNIC attachments
            ListVnicAttachmentsRequest allAttachmentsRequest = ListVnicAttachmentsRequest.builder()
                    .instanceId(instanceId)
                    .compartmentId(compartmentId)
                    .build();

            ListVnicAttachmentsResponse allAttachmentsResponse = computeClient.listVnicAttachments(allAttachmentsRequest);

            if (allAttachmentsResponse.getItems().isEmpty()) {
                return false;
            }

            // 找到最早创建的VNIC attachment
            VnicAttachment primaryAttachment = allAttachmentsResponse.getItems().stream()
                    .filter(att -> att.getTimeCreated() != null)
                    .min(Comparator.comparing(VnicAttachment::getTimeCreated))
                    .orElse(null);

            // 判断传入的vnicId是否是主VNIC
            return primaryAttachment != null && vnicId.equals(primaryAttachment.getVnicId());

        } catch (Exception e) {
            log.debug("判断主VNIC失败: {}", e.getMessage());
            return false;
        }
    }

    /**
     * 删除VNIC上的所有IPv6地址
     */
    private static boolean deleteAllIpv6FromVnic(SimpleAuthenticationDetailsProvider provider, Tenant tenant, String vnicId) {
        try (VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 获取VNIC的所有IPv6地址
            ListIpv6sRequest listRequest = ListIpv6sRequest.builder()
                    .vnicId(vnicId)
                    .build();

            ListIpv6sResponse listResponse = networkClient.listIpv6s(listRequest);

            boolean allDeleted = true;
            int deleteCount = 0;

            for (Ipv6 ipv6 : listResponse.getItems()) {
                try {
                    DeleteIpv6Request deleteRequest = DeleteIpv6Request.builder()
                            .ipv6Id(ipv6.getId())
                            .build();

                    DeleteIpv6Response deleteResponse = networkClient.deleteIpv6(deleteRequest);
                    deleteCount++;

                    log.info("IPv6地址删除成功: {} ({})", ipv6.getIpAddress(), ipv6.getId());

                } catch (Exception e) {
                    log.error("删除IPv6地址失败: {} - {}", ipv6.getIpAddress(), e.getMessage());
                    allDeleted = false;
                }
            }

            log.info("VNIC {} 的IPv6地址删除完成 - 共删除: {} 个", vnicId, deleteCount);
            return allDeleted;

        } catch (Exception e) {
            log.error("删除VNIC IPv6地址失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 从实例分离VNIC
     */
    private static boolean detachVnicFromInstance(SimpleAuthenticationDetailsProvider provider, Tenant tenant,
                                                  String instanceId, String vnicId) {
        final String providerTenantId = provider.getTenantId();
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 查找VNIC附件
            ListVnicAttachmentsRequest listRequest = ListVnicAttachmentsRequest.builder()
                    .instanceId(instanceId)
                    .vnicId(vnicId)
                    .compartmentId(providerTenantId)
                    .build();

            ListVnicAttachmentsResponse listResponse = computeClient.listVnicAttachments(listRequest);

            if (listResponse.getItems().isEmpty()) {
                log.warn("未找到VNIC {} 的附件", vnicId);
                return false;
            }

            VnicAttachment attachment = listResponse.getItems().get(0);

            // 检查是否为主VNIC
            if (isPrimaryVnic(providerTenantId,computeClient, instanceId, vnicId)) {
                log.warn("不能删除主VNIC: {}", vnicId);
                return false;
            }

            // 分离VNIC
            DetachVnicRequest detachRequest = DetachVnicRequest.builder()
                    .vnicAttachmentId(attachment.getId())
                    .build();

            DetachVnicResponse detachResponse = computeClient.detachVnic(detachRequest);

            // 等待分离完成
            boolean detached = waitForVnicDetachment(computeClient, attachment.getId());

            if (detached) {
                log.info("VNIC {} 分离成功", vnicId);
            } else {
                log.error("VNIC {} 分离失败或超时", vnicId);
            }

            return detached;

        } catch (Exception e) {
            log.error("分离VNIC失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 等待VNIC分离完成
     */
    private static boolean waitForVnicDetachment(ComputeClient computeClient, String attachmentId) {
        try {
            int maxAttempts = DEFAULT_TIMEOUT_SECONDS / POLL_INTERVAL_SECONDS;

            for (int attempt = 0; attempt < maxAttempts; attempt++) {
                try {
                    // 使用GetVnicAttachmentRequest获取特定的VNIC附件
                    GetVnicAttachmentRequest request = GetVnicAttachmentRequest.builder()
                            .vnicAttachmentId(attachmentId)
                            .build();

                    GetVnicAttachmentResponse response = computeClient.getVnicAttachment(request);
                    VnicAttachment attachment = response.getVnicAttachment();

                    if (attachment.getLifecycleState() == VnicAttachment.LifecycleState.Detached) {
                        return true;
                    } else if (attachment.getLifecycleState() == VnicAttachment.LifecycleState.Detaching) {
                        // 继续等待
                        log.debug("VNIC正在分离中，继续等待... (尝试 {}/{})", attempt + 1, maxAttempts);
                    } else {
                        log.warn("VNIC分离状态异常: {}", attachment.getLifecycleState());
                    }

                } catch (Exception e) {
                    if (e.getMessage() != null && e.getMessage().contains("NotFound")) {
                        // 附件不存在，说明分离成功
                        log.debug("VNIC附件已不存在，分离成功");
                        return true;
                    } else {
                        throw e;
                    }
                }

                try {
                    TimeUnit.SECONDS.sleep(POLL_INTERVAL_SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("等待VNIC分离被中断", e);
                }
            }

            log.error("等待VNIC分离超时");
            return false;

        } catch (Exception e) {
            log.error("等待VNIC分离失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 删除指定IPv6地址
     *
     * @param tenant 租户信息
     * @return 是否删除成功
     */
    public static boolean deleteIpv6Address(Tenant tenant, String vnicId, String ipv6Address) {
        try {
            log.info("开始删除IPv6地址: {} (VNIC: {})", ipv6Address, vnicId);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 首先获取该VNIC的所有IPv6地址，找到对应的IPv6资源ID
                ListIpv6sRequest listRequest = ListIpv6sRequest.builder()
                        .vnicId(vnicId)
                        .build();

                ListIpv6sResponse listResponse = networkClient.listIpv6s(listRequest);

                String ipv6Id = null;
                for (Ipv6 ipv6 : listResponse.getItems()) {
                    if (ipv6Address.equals(ipv6.getIpAddress())) {
                        ipv6Id = ipv6.getId();
                        break;
                    }
                }

                if (ipv6Id == null) {
                    log.error("未找到IPv6地址对应的资源ID: {}", ipv6Address);
                    return false;
                }

                log.info("找到IPv6资源ID: {} -> {}", ipv6Address, ipv6Id);

                // 删除IPv6地址
                DeleteIpv6Request deleteRequest = DeleteIpv6Request.builder()
                        .ipv6Id(ipv6Id)
                        .build();

                DeleteIpv6Response deleteResponse = networkClient.deleteIpv6(deleteRequest);

                log.info("IPv6地址删除成功: {} (ID: {})", ipv6Address, ipv6Id);
                return true;
            }

        } catch (Exception e) {
            log.error("删除IPv6地址失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 批量删除实例的所有非主VNIC
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return 删除结果映射（VNIC ID -> 删除是否成功）
     */
    public static Map<String, Boolean> deleteAllSecondaryVnics(Tenant tenant, String instanceId,String compartmentId) {
        Map<String, Boolean> deleteResults = new HashMap<>();

        try {
            log.info("开始删除实例 {} 的所有非主VNIC", instanceId);

            // 获取实例的所有VNIC
            List<VnicCreationResult> vnicInfos = getInstanceVnics(tenant, instanceId,compartmentId);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            final String providerTenantId = provider.getTenantId();
            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                for (VnicCreationResult vnicInfo : vnicInfos) {
                    if (vnicInfo.getVnicId() == null) {
                        continue;
                    }

                    try {
                        // 检查是否为主VNIC
                        ListVnicAttachmentsRequest request = ListVnicAttachmentsRequest.builder()
                                .instanceId(instanceId)
                                .vnicId(vnicInfo.getVnicId())
                                .build();

                        ListVnicAttachmentsResponse response = computeClient.listVnicAttachments(request);

                        if (response.getItems().isEmpty()) {
                            continue;
                        }

                        VnicAttachment attachment = response.getItems().get(0);

                        // 跳过主VNIC
                        if (isPrimaryVnic(providerTenantId,computeClient, instanceId, vnicInfo.getVnicId())) {
                            log.info("跳过主VNIC: {}", vnicInfo.getVnicId());
                            deleteResults.put(vnicInfo.getVnicId(), true); // 主VNIC算作成功（跳过）
                            continue;
                        }

                        // 删除非主VNIC
                        boolean deleteSuccess = deleteVnicWithIpv6(tenant, instanceId, vnicInfo.getVnicId());
                        deleteResults.put(vnicInfo.getVnicId(), deleteSuccess);

                        if (deleteSuccess) {
                            log.info("非主VNIC删除成功: {}", vnicInfo.getVnicId());
                        } else {
                            log.error("非主VNIC删除失败: {}", vnicInfo.getVnicId());
                        }

                    } catch (Exception e) {
                        log.error("删除VNIC {} 时发生异常: {}", vnicInfo.getVnicId(), e.getMessage());
                        deleteResults.put(vnicInfo.getVnicId(), false);
                    }
                }
            }

            long successCount = deleteResults.values().stream().mapToLong(result -> result ? 1 : 0).sum();
            log.info("实例 {} 的VNIC删除完成 - 成功: {}/{}", instanceId, successCount, deleteResults.size());

        } catch (Exception e) {
            log.error("批量删除VNIC失败: " + e.getMessage(), e);
        }

        return deleteResults;
    }

    /**
     * 获取实例的VNIC统计信息
     *
     * @param tenant 租户信息
     * @param instanceId 实例ID
     * @return 统计信息字符串
     */
    public static String getInstanceVnicStatistics(Tenant tenant, String instanceId) {
        try {
            List<VnicCreationResult> vnicInfos = getInstanceVnics(tenant, instanceId,null);

            int totalVnics = vnicInfos.size();
            int activeVnics = 0;
            int primaryVnics = 0;
            int secondaryVnics = 0;
            int totalIpv6s = 0;

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            final String providerTenantId = provider.getTenantId();
            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                for (VnicCreationResult vnicInfo : vnicInfos) {
                    if (vnicInfo.getVnicId() == null) {
                        continue;
                    }

                    if (vnicInfo.getLifecycleState() == VnicAttachment.LifecycleState.Attached) {
                        activeVnics++;
                    }

                    totalIpv6s += vnicInfo.getIpv6Addresses().size();

                    // 检查是否为主VNIC
                    try {
                        if (isPrimaryVnic(providerTenantId,computeClient, instanceId, vnicInfo.getVnicId())) {
                            primaryVnics++;
                        } else {
                            secondaryVnics++;
                        }
                    } catch (Exception e) {
                        log.debug("检查VNIC类型失败: {}", e.getMessage());
                    }
                }
            }

            return String.format(
                    "实例 %s VNIC统计 - 总数: %d, 活跃: %d, 主VNIC: %d, 辅助VNIC: %d, IPv6地址: %d",
                    instanceId, totalVnics, activeVnics, primaryVnics, secondaryVnics, totalIpv6s
            );

        } catch (Exception e) {
            log.error("获取VNIC统计信息失败: " + e.getMessage(), e);
            return String.format("实例 %s VNIC统计获取失败: %s", instanceId, e.getMessage());
        }
    }

    /**
     * 验证VNIC创建参数
     *
     * @param vnicCount VNIC数量
     * @param ipv6CountPerVnic 每个VNIC的IPv6数量
     * @throws IllegalArgumentException 参数无效时抛出
     */
    public static void validateVnicCreationParameters(int vnicCount, int ipv6CountPerVnic) {
        if (vnicCount <= 0) {
            throw new IllegalArgumentException("VNIC数量必须大于0");
        }

        if (vnicCount > MAX_VNIC_PER_INSTANCE) {
            throw new IllegalArgumentException("VNIC数量不能超过" + MAX_VNIC_PER_INSTANCE);
        }

        if (ipv6CountPerVnic < 0) {
            throw new IllegalArgumentException("IPv6地址数量不能为负数");
        }

        if (ipv6CountPerVnic > MAX_IPV6_PER_VNIC) {
            throw new IllegalArgumentException("每个VNIC的IPv6地址数量不能超过" + MAX_IPV6_PER_VNIC);
        }
    }

    /**
     * 格式化VNIC创建结果为易读的字符串
     *
     * @param result 批量创建结果
     * @return 格式化的字符串
     */
    public static String formatBatchCreationResult(BatchVnicCreationResult result) {
        StringBuilder sb = new StringBuilder();
        sb.append("=== VNIC批量创建结果 ===\n");
        sb.append(String.format("实例: %s (%s)\n", result.getInstanceId(), result.getInstanceDisplayName()));
        sb.append(String.format("请求创建: %d个VNIC, 每个%d个IPv6地址\n",
                result.getRequestedVnicCount(), result.getRequestedIpv6CountPerVnic()));
        sb.append(String.format("实际创建: %d个VNIC, %d个IPv6地址\n",
                result.getSuccessfulVnicCount(), result.getTotalIpv6Count()));
        sb.append(String.format("创建状态: %s\n", result.isAllSuccessful() ? "全部成功" : "部分失败"));
        sb.append(String.format("执行时间: %dms\n", result.getTotalExecutionTimeMs()));

        if (!result.getVnicResults().isEmpty()) {
            sb.append("\n=== VNIC详情 ===\n");
            for (int i = 0; i < result.getVnicResults().size(); i++) {
                VnicCreationResult vnicResult = result.getVnicResults().get(i);
                sb.append(String.format("%d. %s: %s\n", i + 1, vnicResult.getVnicDisplayName(),
                        vnicResult.isSuccess() ? "成功" : "失败"));

                if (vnicResult.isSuccess()) {
                    sb.append(String.format("   私有IP: %s, 公网IP: %s\n",
                            vnicResult.getPrivateIp(), vnicResult.getPublicIp()));
                    sb.append(String.format("   IPv6地址: %d个\n", vnicResult.getIpv6Addresses().size()));
                } else {
                    sb.append(String.format("   错误: %s\n", vnicResult.getErrorMessage()));
                }
            }
        }

        return sb.toString();
    }

    /**
     * 从VCN的现有CIDR块中获取一个可用的子网CIDR
     * 假设VCN是 10.0.0.0/16，会生成 10.0.x.0/24 格式的子网
     */
    public static String getNextAvailableCidr(List<String> existingCidrBlocks) {
        if (existingCidrBlocks == null || existingCidrBlocks.isEmpty()) {
            // 如果没有现有子网，返回第一个
            return "10.0.1.0/24";
        }

        // 提取所有已使用的第三段数字
        Set<Integer> usedNumbers = new HashSet<>();

        for (String cidr : existingCidrBlocks) {
            try {
                // 解析CIDR，例如 "10.0.5.0/24" -> 提取数字 5
                String[] parts = cidr.split("/")[0].split("\\.");
                if (parts.length >= 3 && parts[0].equals("10") && parts[1].equals("0")) {
                    int thirdOctet = Integer.parseInt(parts[2]);
                    usedNumbers.add(thirdOctet);
                }
            } catch (Exception e) {
                // 忽略解析错误的CIDR
                continue;
            }
        }

        // 找到第一个未使用的数字（从1开始，0通常给主子网）
        for (int i = 1; i < 256; i++) {
            if (!usedNumbers.contains(i)) {
                return String.format("10.0.%d.0/24", i);
            }
        }

        // 如果所有都被占用，返回null或抛出异常
        return null;
    }

    /**
     * 获取下一个可用的IPv6 CIDR
     *
     * @param vcnIpv6CidrBlocks VCN的IPv6 CIDR块列表，从 vcn.getIpv6CidrBlocks() 获取
     * @param existingIpv6CidrBlocks 现有子网的IPv6 CIDR列表
     * @return 下一个可用的IPv6 CIDR，例如 "2001:db8:2::/64"
     */
    public static String getNextAvailableIpv6Cidr(List<String> vcnIpv6CidrBlocks, List<String> existingIpv6CidrBlocks) {
        if (vcnIpv6CidrBlocks == null || vcnIpv6CidrBlocks.isEmpty()) {
            return null;
        }

        // 使用第一个IPv6 CIDR块
        String vcnIpv6CidrBlock = vcnIpv6CidrBlocks.get(0);

        // 解析VCN IPv6 CIDR，例如 "2603:c021:4007:6d00::/56"
        String[] vcnParts = vcnIpv6CidrBlock.split("/");
        if (vcnParts.length != 2) {
            System.err.println("无效的VCN IPv6 CIDR格式: " + vcnIpv6CidrBlock);
            return null;
        }

        String vcnIpv6Address = vcnParts[0];
        int vcnPrefixLength = Integer.parseInt(vcnParts[1]);

        // 如果没有现有子网，返回第一个子网
        if (existingIpv6CidrBlocks == null || existingIpv6CidrBlocks.isEmpty()) {
            return formatFirstSubnet(vcnIpv6Address, vcnPrefixLength);
        }

        // 提取所有已使用的子网编号
        Set<Integer> usedSubnetNumbers = extractUsedSubnetNumbers(vcnIpv6Address, existingIpv6CidrBlocks, vcnPrefixLength);

        // 找到第一个未使用的子网编号
        for (int subnetNumber = 0; subnetNumber < 65536; subnetNumber++) {
            if (!usedSubnetNumbers.contains(subnetNumber)) {
                return formatSubnet(vcnIpv6Address, subnetNumber, vcnPrefixLength);
            }
        }

        return null; // 没有可用的子网空间
    }

    private static String formatFirstSubnet(String vcnIpv6Address, int vcnPrefixLength) {
        if (vcnPrefixLength == 56) {
            // 对于 /56 VCN，第一个 /64 子网就是基地址本身
            // 例如: 2603:c021:4007:6d00:: -> 2603:c021:4007:6d00::/64
            String baseAddress = normalizeIPv6Address(vcnIpv6Address);
            return baseAddress + "/64";
        } else if (vcnPrefixLength == 48) {
            // 对于 /48 VCN
            String baseAddress = normalizeIPv6Address(vcnIpv6Address);
            return baseAddress + "0::/64";
        } else {
            // 通用处理
            String baseAddress = normalizeIPv6Address(vcnIpv6Address);
            return baseAddress + "/64";
        }
    }

    private static String formatSubnet(String vcnIpv6Address, int subnetNumber, int vcnPrefixLength) {
        if (vcnPrefixLength == 56) {
            // 对于 /56 VCN，在第4段（最后一段）修改子网编号
            // 例如: 2603:c021:4007:6d00:: + 1 -> 2603:c021:4007:6d01::/64
            return formatSubnetFor56(vcnIpv6Address, subnetNumber);
        } else if (vcnPrefixLength == 48) {
            // 对于 /48 VCN
            return formatSubnetFor48(vcnIpv6Address, subnetNumber);
        } else {
            // 通用处理
            return formatSubnetGeneric(vcnIpv6Address, subnetNumber);
        }
    }

    private static String formatSubnetFor56(String vcnIpv6Address, int subnetNumber) {
        // 解析地址段
        String[] segments = vcnIpv6Address.split(":");

        // 确保有4段
        List<String> segmentList = new ArrayList<>(Arrays.asList(segments));
        while (segmentList.size() < 4) {
            segmentList.add("0");
        }

        // 修改第4段（索引3）的值
        if (segmentList.size() >= 4) {
            // 解析当前第4段的值
            String currentSegment = segmentList.get(3);
            int currentValue = 0;
            if (!currentSegment.isEmpty()) {
                try {
                    currentValue = Integer.parseInt(currentSegment, 16);
                } catch (NumberFormatException e) {
                    // 如果解析失败，使用0
                }
            }

            // 计算新的值
            int newValue = (currentValue & 0xFF00) | (subnetNumber & 0xFF);
            segmentList.set(3, Integer.toHexString(newValue));
        }

        // 重新组装地址
        return String.join(":", segmentList) + "::/64";
    }

    private static String formatSubnetFor48(String vcnIpv6Address, int subnetNumber) {
        String baseAddress = normalizeIPv6Address(vcnIpv6Address);
        String subnetHex = Integer.toHexString(subnetNumber);
        return baseAddress + subnetHex + "::/64";
    }
    private static String formatSubnetGeneric(String vcnIpv6Address, int subnetNumber) {
        String baseAddress = normalizeIPv6Address(vcnIpv6Address);
        String subnetHex = Integer.toHexString(subnetNumber);
        return baseAddress + subnetHex + "::/64";
    }

    private static Set<Integer> extractUsedSubnetNumbers(String vcnIpv6Address, List<String> existingIpv6CidrBlocks, int vcnPrefixLength) {
        Set<Integer> usedNumbers = new HashSet<>();

        for (String cidr : existingIpv6CidrBlocks) {
            try {
                String[] parts = cidr.split("/");
                if (parts.length == 2) {
                    String ipv6Address = parts[0];
                    int prefixLength = Integer.parseInt(parts[1]);

                    // 只处理/64子网且属于当前VCN的
                    if (prefixLength == 64 && isInSameVcn(ipv6Address, vcnIpv6Address, vcnPrefixLength)) {
                        int subnetNumber = extractSubnetNumber(ipv6Address, vcnIpv6Address, vcnPrefixLength);
                        if (subnetNumber >= 0) {
                            usedNumbers.add(subnetNumber);
                        }
                    }
                }
            } catch (Exception e) {
                System.err.println("解析IPv6 CIDR失败: " + cidr + ", 错误: " + e.getMessage());
                continue;
            }
        }

        return usedNumbers;
    }

    private static int extractSubnetNumber(String subnetIpv6, String vcnIpv6, int vcnPrefixLength) {
        try {
            if (vcnPrefixLength == 56) {
                // 对于 /56，比较第4段的值
                String[] subnetSegments = subnetIpv6.split(":");
                String[] vcnSegments = vcnIpv6.split(":");

                if (subnetSegments.length >= 4 && vcnSegments.length >= 4) {
                    int subnetValue = Integer.parseInt(subnetSegments[3], 16);
                    int vcnValue = 0;
                    if (!vcnSegments[3].isEmpty()) {
                        vcnValue = Integer.parseInt(vcnSegments[3], 16);
                    }

                    // 子网编号是差值
                    return subnetValue - vcnValue;
                }
            }

            return 0;
        } catch (Exception e) {
            return -1;
        }
    }

    private static boolean isInSameVcn(String subnetIpv6, String vcnIpv6, int vcnPrefixLength) {
        try {
            String[] subnetSegments = subnetIpv6.split(":");
            String[] vcnSegments = vcnIpv6.split(":");

            // 根据前缀长度确定需要比较的段数
            int segmentsToCompare = vcnPrefixLength / 16;

            for (int i = 0; i < segmentsToCompare && i < Math.min(subnetSegments.length, vcnSegments.length); i++) {
                String subnetSegment = subnetSegments[i].isEmpty() ? "0" : subnetSegments[i];
                String vcnSegment = vcnSegments[i].isEmpty() ? "0" : vcnSegments[i];

                if (!subnetSegment.equals(vcnSegment)) {
                    return false;
                }
            }

            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static String normalizeIPv6Address(String ipv6Address) {
        // 移除末尾的双冒号
        String normalized = ipv6Address.replaceAll(":+$", "");

        // 确保以冒号结尾（如果需要的话）
        if (!normalized.endsWith(":") && !normalized.contains("::")) {
            normalized += ":";
        }

        return normalized;
    }

    private static String generateFirstIpv6Subnet(String vcnIpv6Address, int vcnPrefixLength) {
        // 移除地址末尾的零段
        String baseAddress = normalizeIpv6Address(vcnIpv6Address);

        if (vcnPrefixLength == 56) {
            // 对于/56 VCN，创建/64子网，在第4段添加子网编号
            return baseAddress + "0::/64";
        } else if (vcnPrefixLength == 48) {
            // 对于/48 VCN，创建/64子网
            return baseAddress + "0:0::/64";
        } else {
            // 通用处理
            return baseAddress + "0::/64";
        }
    }

    private static boolean isInSameVcnRange(String subnetIpv6, String vcnIpv6, int vcnPrefixLength) {
        try {
            // 简化检查：比较前缀部分
            String[] subnetParts = subnetIpv6.split(":");
            String[] vcnParts = vcnIpv6.split(":");

            // 根据前缀长度确定需要比较的段数
            int segmentsToCompare = vcnPrefixLength / 16;

            for (int i = 0; i < segmentsToCompare && i < Math.min(subnetParts.length, vcnParts.length); i++) {
                String subnetSegment = subnetParts[i].isEmpty() ? "0" : subnetParts[i];
                String vcnSegment = vcnParts[i].isEmpty() ? "0" : vcnParts[i];

                if (!subnetSegment.equals(vcnSegment)) {
                    return false;
                }
            }

            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static String extractSubnetIdentifier(String subnetIpv6, String vcnIpv6, int vcnPrefixLength) {
        try {
            String[] subnetParts = subnetIpv6.split(":");
            String[] vcnParts = vcnIpv6.split(":");

            // 找到第一个不同的段作为子网标识符
            int vcnSegments = vcnPrefixLength / 16;

            if (subnetParts.length > vcnSegments) {
                String subnetId = subnetParts[vcnSegments];
                return subnetId.isEmpty() ? "0" : subnetId;
            }

            return "0";
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizeIpv6Address(String ipv6Address) {
        // 移除末尾的双冒号
        String normalized = ipv6Address.replaceAll(":+$", "");

        // 确保以冒号结尾（用于后续添加子网段）
        if (!normalized.endsWith(":")) {
            normalized += ":";
        }

        return normalized;
    }


    /**
     * 从IPv6地址中提取子网编号
     * 例如从 "2001:db8:5::" 中提取 5
     */
    private static int extractIpv6SubnetNumber(String ipv6Address, String vcnPrefix) {
        try {
            // 移除VCN前缀
            String remaining = ipv6Address.substring(vcnPrefix.length());

            // 移除开头的冒号
            if (remaining.startsWith(":")) {
                remaining = remaining.substring(1);
            }

            // 获取第一个段（子网编号）
            String[] segments = remaining.split(":");
            if (segments.length > 0 && !segments[0].isEmpty()) {
                // 将十六进制转为十进制
                return Integer.parseInt(segments[0], 16);
            }
        } catch (Exception e) {
            // 解析失败
        }
        return -1;
    }

    private static String generateNextAvailableIpv6Subnet(String vcnIpv6Address, int vcnPrefixLength, Set<String> usedSubnetIds) {
        String baseAddress = normalizeIpv6Address(vcnIpv6Address);

        // 尝试从0开始找可用的子网编号
        for (int i = 0; i < 65536; i++) {
            String subnetHex = Integer.toHexString(i);

            if (!usedSubnetIds.contains(subnetHex) && !usedSubnetIds.contains(String.valueOf(i))) {
                if (vcnPrefixLength == 56) {
                    return baseAddress + subnetHex + "::/64";
                } else if (vcnPrefixLength == 48) {
                    return baseAddress + subnetHex + ":0::/64";
                } else {
                    // 通用处理
                    return baseAddress + subnetHex + "::/64";
                }
            }
        }

        return null;
    }

    /**
    * @Description: 查询所有的vnic
    * @Param: [com.doubledimple.dao.entity.Tenant]
    * @return: java.util.List<com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult>
    * @Author: doubleDimple
    * @Date: 10/27/25 4:34 PM
    */
    public static List<VnicCreationResult> listAllVnicsForTenant(Tenant tenant) {
        List<VnicCreationResult> result = new ArrayList<>();

        try {
            // 1. 初始化认证
            SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
            String compartmentId = provider.getTenantId();

            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
                 VirtualNetworkClient vcnClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

                // 2. 设置区域
                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
                vcnClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 3. 查询该租户下所有实例
                ListInstancesRequest instanceReq = ListInstancesRequest.builder()
                        .compartmentId(compartmentId)
                        .build();

                ListInstancesResponse instanceResp = computeClient.listInstances(instanceReq);
                List<Instance> instances = instanceResp.getItems();

                log.debug("租户 [{}] 共查询到 {} 个实例", tenant.getTenancy(), instances.size());

                // 4. 遍历每个实例，查 VNIC Attachments
                for (Instance instance : instances) {
                    String instanceId = instance.getId();

                    ListVnicAttachmentsRequest vnicReq = ListVnicAttachmentsRequest.builder()
                            .instanceId(instanceId)
                            .compartmentId(compartmentId)
                            .build();

                    ListVnicAttachmentsResponse vnicResp = computeClient.listVnicAttachments(vnicReq);
                    List<VnicAttachment> attachments = vnicResp.getItems();

                    for (VnicAttachment attachment : attachments) {
                        String vnicId = attachment.getVnicId();
                        if (vnicId == null) continue;

                        GetVnicRequest getReq = GetVnicRequest.builder().vnicId(vnicId).build();
                        GetVnicResponse getResp = vcnClient.getVnic(getReq);
                        Vnic vnic = getResp.getVnic();

                        if (vnic == null) continue;

                        VnicCreationResult info = new VnicCreationResult();
                        info.setVnicId(vnic.getId());
                        info.setVnicDisplayName(vnic.getDisplayName());
                        info.setPrivateIp(vnic.getPrivateIp());
                        info.setPublicIp(vnic.getPublicIp());
                        info.setSubnetId(vnic.getSubnetId());
                        info.setIsPrimary(vnic.getIsPrimary());
                        info.setSuccess(true);
                        info.setInstanceId(instanceId);
                        info.setInstanceName(instance.getDisplayName());

                        result.add(info);

                        log.debug("租户 [{}] 实例 [{}] VNIC [{}]：PrivateIP={}, PublicIP={}",
                                tenant.getTenancy(), instance.getDisplayName(),
                                vnic.getId(), vnic.getPrivateIp(), vnic.getPublicIp());
                    }
                }
            }
        } catch (Exception e) {
            log.error("查询租户 [{}] 所有 VNIC 失败：{}", tenant.getTenancy(), e.getMessage(), e);
        }

        return result;
    }

}