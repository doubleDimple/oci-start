package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.CreateNatGatewayDetails;
import com.oracle.bmc.core.model.CreateRouteTableDetails;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.NatGateway;
import com.oracle.bmc.core.model.RouteRule;
import com.oracle.bmc.core.model.RouteTable;
import com.oracle.bmc.core.model.UpdateNatGatewayDetails;
import com.oracle.bmc.core.model.UpdateRouteTableDetails;
import com.oracle.bmc.core.model.UpdateVnicDetails;
import com.oracle.bmc.core.model.Vnic;
import com.oracle.bmc.core.requests.CreateNatGatewayRequest;
import com.oracle.bmc.core.requests.CreateRouteTableRequest;
import com.oracle.bmc.core.requests.DeleteNatGatewayRequest;
import com.oracle.bmc.core.requests.DeleteRouteTableRequest;
import com.oracle.bmc.core.requests.GetNatGatewayRequest;
import com.oracle.bmc.core.requests.GetRouteTableRequest;
import com.oracle.bmc.core.requests.GetVnicRequest;
import com.oracle.bmc.core.requests.ListNatGatewaysRequest;
import com.oracle.bmc.core.requests.ListRouteTablesRequest;
import com.oracle.bmc.core.requests.UpdateNatGatewayRequest;
import com.oracle.bmc.core.requests.UpdateRouteTableRequest;
import com.oracle.bmc.core.requests.UpdateVnicRequest;
import com.oracle.bmc.core.responses.CreateNatGatewayResponse;
import com.oracle.bmc.core.responses.CreateRouteTableResponse;
import com.oracle.bmc.core.responses.ListNatGatewaysResponse;
import com.oracle.bmc.core.responses.ListRouteTablesResponse;
import com.oracle.bmc.core.responses.UpdateNatGatewayResponse;
import com.oracle.bmc.core.responses.UpdateRouteTableResponse;
import com.oracle.bmc.core.responses.UpdateVnicResponse;
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import com.oracle.bmc.networkloadbalancer.model.Backend;
import com.oracle.bmc.networkloadbalancer.model.BackendSetDetails;
import com.oracle.bmc.networkloadbalancer.model.CreateNetworkLoadBalancerDetails;
import com.oracle.bmc.networkloadbalancer.model.HealthCheckProtocols;
import com.oracle.bmc.networkloadbalancer.model.HealthChecker;
import com.oracle.bmc.networkloadbalancer.model.IpAddress;
import com.oracle.bmc.networkloadbalancer.model.LifecycleState;
import com.oracle.bmc.networkloadbalancer.model.ListenerDetails;
import com.oracle.bmc.networkloadbalancer.model.ListenerProtocols;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancer;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancerSummary;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancingPolicy;
import com.oracle.bmc.networkloadbalancer.requests.CreateNetworkLoadBalancerRequest;
import com.oracle.bmc.networkloadbalancer.requests.DeleteNetworkLoadBalancerRequest;
import com.oracle.bmc.networkloadbalancer.requests.GetNetworkLoadBalancerRequest;
import com.oracle.bmc.networkloadbalancer.requests.ListNetworkLoadBalancersRequest;
import com.oracle.bmc.networkloadbalancer.responses.CreateNetworkLoadBalancerResponse;
import com.oracle.bmc.networkloadbalancer.responses.DeleteNetworkLoadBalancerResponse;
import com.oracle.bmc.networkloadbalancer.responses.ListNetworkLoadBalancersResponse;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.util.CollectionUtils;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @version 1.0.0
 * @ClassName OciNetworkUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-22 13:35
 */
@Slf4j
public class OciNetworkUtils {

    public static final String DEFAULT_NAME = "amd";


    /**
     * 一键为实例配置完整的NAT网络和负载均衡器设置
     *
     * @param tenant           租户信息
     * @param instanceId       目标实例ID
     * @param vcnId           VCN ID
     * @param subnetId        子网ID
     * @param createLoadBalancer 是否创建负载均衡器
     * @return 返回配置结果信息
     */
    public static NetworkConfigResult configureInstanceNetwork(Tenant tenant, String instanceId,
                                                               String vcnId, String subnetId, boolean createLoadBalancer) {

        NetworkConfigResult result = new NetworkConfigResult();
        log.debug("开始为实例 {} 配置完整网络环境", instanceId);

        try {
            // 第一步：创建或获取NAT网关
            log.debug("步骤1: 创建或获取NAT网关");
            String natGatewayName = "amd";
            NatGateway natGateway = createOrGetNatGateway(tenant, vcnId, natGatewayName, true);

            if (natGateway == null) {
                result.setSuccess(false);
                result.setErrorMessage("创建或获取NAT网关失败");
                return result;
            }

            result.setNatGatewayId(natGateway.getId());
            result.setNatGatewayName(natGateway.getDisplayName());
            log.debug("NAT网关准备就绪: {}", natGateway.getDisplayName());

            // 第二步：创建或获取NAT路由表
            log.debug("步骤2: 创建或获取NAT路由表");
            RouteTable routeTable = createOrGetNatRouteTable(tenant, vcnId, natGateway.getId(),DEFAULT_NAME);

            if (routeTable == null) {
                result.setSuccess(false);
                result.setErrorMessage("创建或获取路由表失败");
                return result;
            }

            result.setRouteTableId(routeTable.getId());
            result.setRouteTableName(routeTable.getDisplayName());
            log.debug("路由表准备就绪: {}", routeTable.getDisplayName());

            // 第三步：更新实例的VNIC路由表
            log.debug("步骤3: 更新实例VNIC路由表");
            boolean routeUpdateSuccess = updateInstanceVnicRouteTable(tenant, instanceId, routeTable.getId());

            if (!routeUpdateSuccess) {
                result.setSuccess(false);
                result.setErrorMessage("更新实例路由表失败");
                return result;
            }

            result.setRouteTableUpdated(true);
            log.debug("实例路由表更新成功");

            // 第四步：创建网络负载均衡器
            if (createLoadBalancer && subnetId != null) {
                log.debug("步骤4: 创建或获取网络负载均衡器");

                // 获取实例的私有IP作为后端服务器
                Instance instance = OciUtils.getInstanceById(tenant, instanceId);
                if (instance == null) {
                    result.setSuccess(false);
                    result.setErrorMessage("获取实例信息失败");
                    return result;
                }
                SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
                Vnic vnic = OciUtils.getVnicPrimary(provider, instance, provider.getTenantId());
                if (vnic == null || vnic.getPrivateIp() == null) {
                    result.setSuccess(false);
                    result.setErrorMessage("获取实例私有IP失败");
                    return result;
                }

                // 创建后端服务器信息
                List<BackendServerInfo> backendServers = Arrays.asList(
                        new BackendServerInfo(vnic.getPrivateIp(), 22, 1, false)
                );

                String nlbName = "amd";
                NetworkLoadBalancer nlb = createOrGetNetworkLoadBalancer(
                        instanceId,tenant, subnetId, nlbName, false, backendServers);

                if (nlb != null) {
                    result.setNetworkLoadBalancerId(nlb.getId());
                    result.setNetworkLoadBalancerName(nlb.getDisplayName());
                    result.setLoadBalancerCreated(true);
                    result.setIpAddress(nlb.getIpAddresses());
                    log.debug("网络负载均衡器准备就绪: {}", nlb.getDisplayName());
                } else {
                    log.warn("网络负载均衡器创建失败，但其他配置已完成");
                }
            }

            result.setSuccess(true);
            result.setMessage("实例网络配置完成");
            log.debug("实例 {} 的完整网络配置已成功完成", instanceId);

            return result;

        } catch (Exception e) {
            log.error("配置实例网络时发生错误: {}", e.getMessage(), e);
            result.setSuccess(false);
            result.setErrorMessage("配置过程中发生错误: " + e.getMessage());
            return result;
        }
    }

    /**
     * 快速配置实例网络（只包含NAT网关和路由表）
     */
    public static NetworkConfigResult quickConfigureInstanceNetwork(Tenant tenant, String instanceId, String vcnId) {
        return configureInstanceNetwork(tenant, instanceId, vcnId, null, false);
    }

    /**
     * 完整配置实例网络（包含NAT网关、路由表和负载均衡器）
     */
    public static NetworkConfigResult fullConfigureInstanceNetwork(Tenant tenant, String instanceId,
                                                                   String vcnId, String subnetId) {
        return configureInstanceNetwork(tenant, instanceId, vcnId, subnetId, true);
    }

    // ==================== NAT网关相关方法 ====================

    /**
     * 创建或获取NAT网关（如果已存在则直接使用）
     */
    public static NatGateway createOrGetNatGateway(Tenant tenant, String vcnId, String displayName, boolean isEnabled) {
        try {
            // 先检查是否已存在NAT网关
            log.debug("检查VCN {} 是否已存在NAT网关", vcnId);
            List<NatGateway> existingGateways = listNatGateways(tenant, vcnId);

            // 查找可用的NAT网关
            for (NatGateway gateway : existingGateways) {
                if (gateway.getLifecycleState() == NatGateway.LifecycleState.Available) {
                    log.debug("找到现有可用的NAT网关: {} ({})", gateway.getDisplayName(), gateway.getId());

                    // 如果网关被禁用但我们需要启用它，则更新状态
                    if (gateway.getBlockTraffic() && isEnabled) {
                        return updateNatGatewayStatus(tenant, gateway.getId(), true);
                    }

                    return gateway; // 直接使用现有网关
                }
            }

            // 如果没有找到可用的NAT网关，创建新的
            log.debug("未找到可用的NAT网关，开始创建新的NAT网关");
            return createNatGateway(tenant, vcnId, displayName, isEnabled);

        } catch (Exception e) {
            log.error("创建或获取NAT网关失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 创建NAT网关
     */
    public static NatGateway createNatGateway(Tenant tenant, String vcnId, String displayName, boolean isEnabled) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("开始创建新的NAT网关，VCN ID: {}, 显示名称: {}", vcnId, displayName);

            CreateNatGatewayDetails natGatewayDetails = CreateNatGatewayDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcnId)
                    .displayName(displayName)
                    //.blockTraffic(!isEnabled)
                    .build();

            CreateNatGatewayRequest request = CreateNatGatewayRequest.builder()
                    .createNatGatewayDetails(natGatewayDetails)
                    .build();

            CreateNatGatewayResponse response = virtualNetworkClient.createNatGateway(request);
            NatGateway natGateway = response.getNatGateway();

            log.debug("NAT网关创建成功，ID: {}", natGateway.getId());

            // 等待NAT网关变为可用状态
            waitForNatGatewayAvailable(virtualNetworkClient, natGateway.getId());

            return natGateway;

        } catch (Exception e) {
            log.error("创建NAT网关失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 获取VCN下的所有NAT网关
     */
    public static List<NatGateway> listNatGateways(Tenant tenant, String vcnId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            ListNatGatewaysRequest request = ListNatGatewaysRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcnId)
                    .build();

            ListNatGatewaysResponse response = virtualNetworkClient.listNatGateways(request);
            return response.getItems();

        } catch (Exception e) {
            log.error("获取NAT网关列表失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    /**
     * 更新NAT网关状态
     */
    private static NatGateway updateNatGatewayStatus(Tenant tenant, String natGatewayId, boolean isEnabled) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("更新NAT网关状态: {}, 启用: {}", natGatewayId, isEnabled);

            UpdateNatGatewayDetails updateDetails = UpdateNatGatewayDetails.builder()
                    .blockTraffic(!isEnabled)
                    .build();

            UpdateNatGatewayRequest updateRequest = UpdateNatGatewayRequest.builder()
                    .natGatewayId(natGatewayId)
                    .updateNatGatewayDetails(updateDetails)
                    .build();

            UpdateNatGatewayResponse updateResponse = virtualNetworkClient.updateNatGateway(updateRequest);
            return updateResponse.getNatGateway();

        } catch (Exception e) {
            log.error("更新NAT网关状态失败: {}", e.getMessage(), e);
            return null;
        }
    }

    // ==================== 路由表相关方法 ====================

    /**
     * 创建或获取NAT路由表（如果已存在则直接使用）
     */
    public static RouteTable createOrGetNatRouteTable(Tenant tenant, String vcnId, String natGatewayId, String displayName) {
        try {
            // 先检查是否已存在指定名称的路由表
            log.debug("检查VCN {} 是否已存在名为 '{}' 的路由表", vcnId, displayName);
            List<RouteTable> existingRouteTables = listRouteTables(tenant, vcnId);

            // 查找指定名称的路由表
            for (RouteTable routeTable : existingRouteTables) {
                if (routeTable.getLifecycleState() == RouteTable.LifecycleState.Available) {
                    String routeName = routeTable.getDisplayName();
                    if (displayName.equals(routeName)) {
                        log.debug("找到现有路由表: {} ({})", routeTable.getDisplayName(), routeTable.getId());

                        // 验证路由表是否包含正确的NAT路由规则
                        boolean hasCorrectNatRoute = validateNatRouteRule(routeTable, natGatewayId);
                        if (hasCorrectNatRoute) {
                            log.debug("路由表配置正确，直接使用");
                            return routeTable;
                        } else {
                            log.warn("路由表 '{}' 存在但配置不正确，需要重新配置", displayName);
                            // 可以选择更新现有路由表或删除重建
                            RouteTable updatedTable = updateRouteTableForNat(tenant, routeTable.getId(), natGatewayId);
                            if (updatedTable != null) {
                                return updatedTable;
                            }
                        }
                    }
                }
            }

            // 如果没有找到合适的路由表，创建新的
            log.debug("未找到名为 '{}' 的路由表，开始创建新的路由表", displayName);
            return createNatRouteTable(tenant, vcnId, natGatewayId, displayName);

        } catch (Exception e) {
            log.error("创建或获取NAT路由表失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 验证路由表是否包含正确的NAT路由规则
     */
    private static boolean validateNatRouteRule(RouteTable routeTable, String natGatewayId) {
        for (RouteRule rule : routeTable.getRouteRules()) {
            if ("0.0.0.0/0".equals(rule.getDestination()) &&
                    RouteRule.DestinationType.CidrBlock.equals(rule.getDestinationType()) &&
                    natGatewayId.equals(rule.getNetworkEntityId())) {
                log.debug("找到正确的NAT路由规则: {} -> {}", rule.getDestination(), rule.getNetworkEntityId());
                return true;
            }
        }
        log.warn("未找到指向NAT网关 {} 的默认路由规则", natGatewayId);
        return false;
    }

    private static RouteTable updateRouteTableForNat(Tenant tenant, String routeTableId, String natGatewayId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("更新路由表以包含NAT路由规则，路由表ID: {}", routeTableId);

            // 获取当前路由表
            GetRouteTableRequest getRequest = GetRouteTableRequest.builder()
                    .rtId(routeTableId)
                    .build();
            RouteTable currentTable = virtualNetworkClient.getRouteTable(getRequest).getRouteTable();

            // 检查是否已经存在默认路由，如果存在则替换，如果不存在则添加
            List<RouteRule> updatedRules = new ArrayList<>();
            boolean foundDefaultRoute = false;

            for (RouteRule rule : currentTable.getRouteRules()) {
                if ("0.0.0.0/0".equals(rule.getDestination())) {
                    // 替换现有的默认路由
                    RouteRule natRule = RouteRule.builder()
                            .destination("0.0.0.0/0")
                            .destinationType(RouteRule.DestinationType.CidrBlock)
                            .networkEntityId(natGatewayId)
                            .description("Route all traffic through NAT Gateway")
                            .build();
                    updatedRules.add(natRule);
                    foundDefaultRoute = true;
                    log.debug("替换现有的默认路由规则");
                } else {
                    updatedRules.add(rule);
                }
            }

            // 如果没有找到默认路由，添加新的
            if (!foundDefaultRoute) {
                RouteRule natRule = RouteRule.builder()
                        .destination("0.0.0.0/0")
                        .destinationType(RouteRule.DestinationType.CidrBlock)
                        .networkEntityId(natGatewayId)
                        .description("Route all traffic through NAT Gateway")
                        .build();
                updatedRules.add(natRule);
                log.debug("添加新的NAT默认路由规则");
            }

            // 更新路由表
            UpdateRouteTableDetails updateDetails = UpdateRouteTableDetails.builder()
                    .routeRules(updatedRules)
                    .build();

            UpdateRouteTableRequest updateRequest = UpdateRouteTableRequest.builder()
                    .rtId(routeTableId)
                    .updateRouteTableDetails(updateDetails)
                    .build();

            UpdateRouteTableResponse updateResponse = virtualNetworkClient.updateRouteTable(updateRequest);
            RouteTable updatedTable = updateResponse.getRouteTable();

            log.debug("路由表更新成功，ID: {}", updatedTable.getId());

            // 等待更新完成
            waitForRouteTableAvailable(virtualNetworkClient, updatedTable.getId());

            return updatedTable;

        } catch (Exception e) {
            log.error("更新路由表失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 为NAT网关创建路由表
     */
    public static RouteTable createNatRouteTable(Tenant tenant, String vcnId, String natGatewayId, String displayName) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("开始创建新的NAT路由表，VCN ID: {}, NAT网关ID: {}, 显示名称: {}", vcnId, natGatewayId, displayName);

            // 创建路由规则：所有流量通过NAT网关
            RouteRule natRouteRule = RouteRule.builder()
                    .destination("0.0.0.0/0")
                    .destinationType(RouteRule.DestinationType.CidrBlock)
                    .networkEntityId(natGatewayId)
                    .description("Route all traffic through NAT Gateway")
                    .build();

            List<RouteRule> routeRules = Arrays.asList(natRouteRule);

            CreateRouteTableDetails routeTableDetails = CreateRouteTableDetails.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcnId)
                    .displayName(displayName)
                    .routeRules(routeRules)
                    .build();

            CreateRouteTableRequest request = CreateRouteTableRequest.builder()
                    .createRouteTableDetails(routeTableDetails)
                    .build();

            CreateRouteTableResponse response = virtualNetworkClient.createRouteTable(request);
            RouteTable routeTable = response.getRouteTable();

            log.debug("NAT路由表创建成功，ID: {}, 名称: {}", routeTable.getId(), routeTable.getDisplayName());

            // 等待路由表变为可用状态
            waitForRouteTableAvailable(virtualNetworkClient, routeTable.getId());

            // 验证创建结果
            verifyCreatedRouteTable(virtualNetworkClient, routeTable.getId(), natGatewayId);

            return routeTable;

        } catch (Exception e) {
            log.error("创建NAT路由表失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 验证创建的路由表配置
     */
    private static void verifyCreatedRouteTable(VirtualNetworkClient client, String routeTableId, String natGatewayId) {
        try {
            GetRouteTableRequest request = GetRouteTableRequest.builder()
                    .rtId(routeTableId)
                    .build();

            RouteTable routeTable = client.getRouteTable(request).getRouteTable();

            log.debug("=== 路由表创建验证 ===");
            log.debug("路由表ID: {}", routeTable.getId());
            log.debug("路由表名称: {}", routeTable.getDisplayName());
            log.debug("路由表状态: {}", routeTable.getLifecycleState());
            log.debug("路由规则数量: {}", routeTable.getRouteRules().size());

            for (RouteRule rule : routeTable.getRouteRules()) {
                log.debug("路由规则: {} -> {} (类型: {}, 描述: {})",
                        rule.getDestination(),
                        rule.getNetworkEntityId(),
                        rule.getDestinationType(),
                        rule.getDescription());

                if ("0.0.0.0/0".equals(rule.getDestination()) && natGatewayId.equals(rule.getNetworkEntityId())) {
                    log.debug("✓ NAT路由规则配置正确");
                }
            }

        } catch (Exception e) {
            log.warn("验证路由表配置时出错: {}", e.getMessage());
        }
    }

    /**
     * 获取VCN下的所有路由表
     */
    public static List<RouteTable> listRouteTables(Tenant tenant, String vcnId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            ListRouteTablesRequest request = ListRouteTablesRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcnId)
                    .build();

            ListRouteTablesResponse response = virtualNetworkClient.listRouteTables(request);
            return response.getItems();

        } catch (Exception e) {
            log.error("获取路由表列表失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    /**
     * 更新实例的VNIC路由表
     */
    public static boolean updateInstanceVnicRouteTable(Tenant tenant, String instanceId, String routeTableId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("开始更新实例VNIC路由表，实例ID: {}, 路由表ID: {}", instanceId, routeTableId);

            // 获取实例的主VNIC
            Instance instance = OciUtils.getInstanceById(tenant, instanceId);
            if (instance == null) {
                log.error("未找到实例: {}", instanceId);
                return false;
            }

            Vnic primaryVnic = OciUtils.getVnicPrimary(provider, instance, provider.getTenantId());
            if (primaryVnic == null) {
                log.error("未找到实例的主VNIC，实例ID: {}", instanceId);
                return false;
            }

            log.debug("找到主VNIC: {}, 当前路由表: {}", primaryVnic.getId(),
                    primaryVnic.getRouteTableId() != null ? primaryVnic.getRouteTableId() : "使用子网默认路由表");

            // 直接更新VNIC的路由表
            UpdateVnicDetails updateVnicDetails = UpdateVnicDetails.builder()
                    .routeTableId(routeTableId)
                    .build();

            UpdateVnicRequest updateVnicRequest = UpdateVnicRequest.builder()
                    .vnicId(primaryVnic.getId())
                    .updateVnicDetails(updateVnicDetails)
                    .build();

            UpdateVnicResponse updateVnicResponse = virtualNetworkClient.updateVnic(updateVnicRequest);
            Vnic updatedVnic = updateVnicResponse.getVnic();

            log.debug("VNIC路由表更新成功！");
            log.debug("VNIC ID: {}", updatedVnic.getId());
            log.debug("新路由表ID: {}", updatedVnic.getRouteTableId());

            // 等待VNIC更新完成
            waitForVnicUpdate(virtualNetworkClient, updatedVnic.getId());

            return true;

        } catch (Exception e) {
            log.error("更新实例VNIC路由表失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 等待VNIC更新完成
     */
    private static void waitForVnicUpdate(VirtualNetworkClient client, String vnicId) {
        final int MAX_ATTEMPTS = 20;
        final int WAIT_SECONDS = 3;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                GetVnicRequest request = GetVnicRequest.builder()
                        .vnicId(vnicId)
                        .build();

                Vnic vnic = client.getVnic(request).getVnic();

                if (vnic.getLifecycleState() == Vnic.LifecycleState.Available) {
                    log.debug("VNIC更新完成");
                    return;
                }

                log.debug("等待VNIC更新完成... 当前状态: {}, 尝试次数: {}/{}",
                        vnic.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待VNIC更新过程被中断", e);
            } catch (Exception e) {
                log.warn("检查VNIC更新状态时出错: {}", e.getMessage());
            }
        }

        log.warn("VNIC在预期时间内未完成更新，但可能已经生效");
    }

    // ==================== 网络负载均衡器相关方法 ====================

    /**
     * 创建或获取网络负载均衡器（如果已存在则直接使用）
     */
    public static NetworkLoadBalancer createOrGetNetworkLoadBalancer(String instanceId,Tenant tenant, String subnetId,
                                                                     String displayName, boolean isPrivate, List<BackendServerInfo> backendServerInfos) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try {
            // 先检查是否已存在网络负载均衡器
            log.debug("检查子网 {} 是否已存在网络负载均衡器", subnetId);
            List<NetworkLoadBalancer> existingNLBs = listNetworkLoadBalancers(tenant, compartmentId);

            // 查找同子网中的可用负载均衡器
            for (NetworkLoadBalancer nlb : existingNLBs) {
                if (nlb.getLifecycleState().equals(LifecycleState.Active) &&
                        subnetId.equals(nlb.getSubnetId()) &&
                        nlb.getIsPrivate().equals(isPrivate)) {
                    log.debug("找到现有的网络负载均衡器: {} ({})", nlb.getDisplayName(), nlb.getId());
                    return nlb; // 直接使用现有负载均衡器
                }
            }

            // 如果没有找到合适的负载均衡器，创建新的
            log.debug("未找到合适的网络负载均衡器，开始创建新的");
            return createNetworkLoadBalancer(instanceId,tenant, subnetId, displayName, isPrivate, backendServerInfos);

        } catch (Exception e) {
            log.error("创建或获取网络负载均衡器失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 创建网络负载均衡器
     */
    public static NetworkLoadBalancer createNetworkLoadBalancer(String instanceId, Tenant tenant, String subnetId,
                                                                String displayName, boolean isPrivate, List<BackendServerInfo> backendServerInfos) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        String compartmentId = provider.getTenantId();

        try (NetworkLoadBalancerClient nlbClient = NetworkLoadBalancerClient.builder().build(provider)) {
            log.debug("开始创建网络负载均衡器，子网ID: {}, 显示名称: {}", subnetId, displayName);

            // 构建后端集合
            Map<String, BackendSetDetails> backendSets = new HashMap<>();
            if (!CollectionUtils.isEmpty(backendServerInfos)) {
                List<Backend> backends = new ArrayList<>(); // 使用Backend

                for (int i = 0; i < backendServerInfos.size(); i++) {
                    BackendServerInfo serverInfo = backendServerInfos.get(i);
                    String backendName = "backend-" + (i + 1);

                    // 使用Backend.builder()
                    Backend backend = Backend.builder()
                            .targetId(instanceId)  // 关键：使用实例ID作为targetId
                            .name(backendName)
                            .port(serverInfo.getPort())
                            .ipAddress(serverInfo.getIpAddress())
                            .weight(serverInfo.getWeight() != null ? serverInfo.getWeight() : 1)
                            .isBackup(serverInfo.getIsBackup() != null ? serverInfo.getIsBackup() : false)
                            .build();

                    backends.add(backend);
                    log.debug("添加后端服务器: 名称={}, IP={}, 端口={}, 目标ID={}",
                            backendName, serverInfo.getIpAddress(), serverInfo.getPort(), instanceId);
                }

                // 创建健康检查配置 - 使用HealthChecker
                HealthChecker healthChecker = HealthChecker.builder()
                        .protocol(HealthCheckProtocols.Tcp)  // TCP协议
                        .port(22)                            // 端口22
                        .intervalInMillis(10000)             // 间隔10秒
                        .timeoutInMillis(3000)               // 超时3秒
                        .retries(3)                          // 重试3次
                        .build();

                BackendSetDetails backendSetDetails = BackendSetDetails.builder()
                        .policy(NetworkLoadBalancingPolicy.FiveTuple)  // 五元组策略
                        .healthChecker(healthChecker)
                        .backends(backends)  // 使用Backend列表
                        .build();

                backendSets.put("amd-1", backendSetDetails);  // 使用与控制台一致的名称
            }

            // 构建监听器 - 支持任意端口
            Map<String, ListenerDetails> listeners = new HashMap<>();
            ListenerDetails listenerDetails = ListenerDetails.builder()
                    .name("amd")  // 监听器名称
                    .defaultBackendSetName("amd-1")  // 指向后端集合
                    .protocol(ListenerProtocols.TcpAndUdp)  // 支持TCP和UDP
                    .port(22)  // 监听端口，可以根据需要修改
                    .build();
            listeners.put("amd", listenerDetails);

            // 构建创建网络负载均衡器请求
            CreateNetworkLoadBalancerDetails nlbDetails = CreateNetworkLoadBalancerDetails.builder()
                    .compartmentId(compartmentId)
                    .displayName(displayName)
                    .subnetId(subnetId)
                    .isPrivate(isPrivate)
                    .backendSets(backendSets)
                    .listeners(listeners)
                    .build();

            CreateNetworkLoadBalancerRequest request = CreateNetworkLoadBalancerRequest.builder()
                    .createNetworkLoadBalancerDetails(nlbDetails)
                    .build();

            log.debug("提交网络负载均衡器创建请求...");
            CreateNetworkLoadBalancerResponse response = nlbClient.createNetworkLoadBalancer(request);

            String workRequestId = response.getOpcWorkRequestId();
            log.debug("网络负载均衡器创建请求已提交，工作请求ID: {}", workRequestId);

            // 等待负载均衡器创建完成
            NetworkLoadBalancer nlb = waitForNetworkLoadBalancerCreation(nlbClient, workRequestId, compartmentId);
            if (nlb != null) {
                log.debug("网络负载均衡器创建成功！");
                log.debug("负载均衡器ID: {}", nlb.getId());
                log.debug("负载均衡器名称: {}", nlb.getDisplayName());
                log.debug("负载均衡器状态: {}", nlb.getLifecycleState());
                log.debug("负载均衡器IP地址: {}", nlb.getIpAddresses());

                // 验证后端配置
                verifyNetworkLoadBalancerConfig(nlbClient, nlb.getId());
            }

            return nlb;

        } catch (Exception e) {
            log.error("创建网络负载均衡器失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 验证网络负载均衡器配置
     */
    private static void verifyNetworkLoadBalancerConfig(NetworkLoadBalancerClient client, String nlbId) {
        try {
            GetNetworkLoadBalancerRequest request = GetNetworkLoadBalancerRequest.builder()
                    .networkLoadBalancerId(nlbId)
                    .build();

            NetworkLoadBalancer nlb = client.getNetworkLoadBalancer(request).getNetworkLoadBalancer();

            log.debug("=== 负载均衡器配置验证 ===");
            log.debug("后端集合数量: {}", nlb.getBackendSets().size());

            nlb.getBackendSets().forEach((setName, backendSet) -> {
                log.debug("后端集合 '{}': 包含 {} 个后端服务器", setName, backendSet.getBackends().size());


                if (backendSet.getHealthChecker() != null) {
                    com.oracle.bmc.networkloadbalancer.model.HealthChecker hc = backendSet.getHealthChecker();
                    log.debug("  健康检查: 协议={}, 端口={}, 间隔={}ms, 超时={}ms, 重试={}",
                            hc.getProtocol(), hc.getPort(), hc.getIntervalInMillis(),
                            hc.getTimeoutInMillis(), hc.getRetries());
                }
            });

            log.debug("监听器数量: {}", nlb.getListeners().size());
            nlb.getListeners().forEach((listenerName, listener) -> {
                log.debug("监听器 '{}': 协议={}, 端口={}, 默认后端集合={}",
                        listenerName, listener.getProtocol(), listener.getPort(),
                        listener.getDefaultBackendSetName());
            });

        } catch (Exception e) {
            log.warn("验证负载均衡器配置时出错: {}", e.getMessage());
        }
    }

    /**
     * 获取指定区间下的所有网络负载均衡器
     */
    public static List<NetworkLoadBalancer> listNetworkLoadBalancers(Tenant tenant, String compartmentId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (NetworkLoadBalancerClient nlbClient = NetworkLoadBalancerClient.builder().build(provider)) {
            ListNetworkLoadBalancersRequest request = ListNetworkLoadBalancersRequest.builder()
                    .compartmentId(compartmentId)
                    .build();

            ListNetworkLoadBalancersResponse response = nlbClient.listNetworkLoadBalancers(request);
            return response.getNetworkLoadBalancerCollection().getItems()
                    .stream()
                    .map(summary -> {
                        try {
                            GetNetworkLoadBalancerRequest getRequest = GetNetworkLoadBalancerRequest.builder()
                                    .networkLoadBalancerId(summary.getId())
                                    .build();
                            return nlbClient.getNetworkLoadBalancer(getRequest).getNetworkLoadBalancer();
                        } catch (Exception e) {
                            log.warn("获取网络负载均衡器详情失败: {}", e.getMessage());
                            return null;
                        }
                    })
                    .filter(Objects::nonNull)
                    .collect(Collectors.toList());

        } catch (Exception e) {
            log.error("获取网络负载均衡器列表失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    // ==================== 等待方法 ====================

    /**
     * 等待NAT网关变为可用状态
     */
    private static void waitForNatGatewayAvailable(VirtualNetworkClient client, String natGatewayId) {
        final int MAX_ATTEMPTS = 30;
        final int WAIT_SECONDS = 10;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                GetNatGatewayRequest request = GetNatGatewayRequest.builder()
                        .natGatewayId(natGatewayId)
                        .build();

                NatGateway natGateway = client.getNatGateway(request).getNatGateway();

                if (natGateway.getLifecycleState() == NatGateway.LifecycleState.Available) {
                    log.debug("NAT网关已变为可用状态");
                    return;
                }

                log.debug("等待NAT网关变为可用状态... 当前状态: {}, 尝试次数: {}/{}",
                        natGateway.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待NAT网关可用过程被中断", e);
            } catch (Exception e) {
                log.warn("检查NAT网关状态时出错: {}", e.getMessage());
            }
        }

        throw new RuntimeException("NAT网关在预期时间内未变为可用状态");
    }

    /**
     * 等待路由表变为可用状态
     */
    private static void waitForRouteTableAvailable(VirtualNetworkClient client, String routeTableId) {
        final int MAX_ATTEMPTS = 20;
        final int WAIT_SECONDS = 5;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                GetRouteTableRequest request = GetRouteTableRequest.builder()
                        .rtId(routeTableId)
                        .build();

                RouteTable routeTable = client.getRouteTable(request).getRouteTable();

                if (routeTable.getLifecycleState() == RouteTable.LifecycleState.Available) {
                    log.debug("路由表已变为可用状态");
                    return;
                }

                log.debug("等待路由表变为可用状态... 当前状态: {}, 尝试次数: {}/{}",
                        routeTable.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待路由表可用过程被中断", e);
            } catch (Exception e) {
                log.warn("检查路由表状态时出错: {}", e.getMessage());
            }
        }

        throw new RuntimeException("路由表在预期时间内未变为可用状态");
    }

    /**
     * 等待网络负载均衡器创建完成
     */
    private static NetworkLoadBalancer waitForNetworkLoadBalancerCreation(NetworkLoadBalancerClient client,
                                                                          String workRequestId, String compartmentId) {
        final int MAX_ATTEMPTS = 60;
        final int WAIT_SECONDS = 30;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                // 获取所有网络负载均衡器，查找最新创建的
                ListNetworkLoadBalancersRequest request = ListNetworkLoadBalancersRequest.builder()
                        .compartmentId(compartmentId)
                        .build();

                List<NetworkLoadBalancerSummary> nlbs = client.listNetworkLoadBalancers(request)
                        .getNetworkLoadBalancerCollection().getItems();

                // 查找状态为ACTIVE的最新负载均衡器
                for (NetworkLoadBalancerSummary summary : nlbs) {
                    if (summary.getLifecycleState().equals(LifecycleState.Active)) {
                        GetNetworkLoadBalancerRequest getRequest = GetNetworkLoadBalancerRequest.builder()
                                .networkLoadBalancerId(summary.getId())
                                .build();

                        return client.getNetworkLoadBalancer(getRequest).getNetworkLoadBalancer();
                    }
                }

                log.debug("等待网络负载均衡器创建完成... 尝试次数: {}/{}", attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待网络负载均衡器创建过程被中断", e);
            } catch (Exception e) {
                log.warn("检查网络负载均衡器创建状态时出错: {}", e.getMessage());
            }
        }

        log.warn("网络负载均衡器在预期时间内未创建完成");
        return null;
    }

    // ==================== 删除方法 ====================

    /**
     * 删除NAT网关
     */
    public static boolean deleteNatGateway(Tenant tenant, String natGatewayId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("开始删除NAT网关，ID: {}", natGatewayId);

            DeleteNatGatewayRequest request = DeleteNatGatewayRequest.builder()
                    .natGatewayId(natGatewayId)
                    .build();

            virtualNetworkClient.deleteNatGateway(request);

            // 等待NAT网关被删除
            waitForNatGatewayTermination(virtualNetworkClient, natGatewayId);

            log.debug("NAT网关删除成功，ID: {}", natGatewayId);
            return true;

        } catch (Exception e) {
            log.error("删除NAT网关失败: {}", e.getMessage(), e);
            return false;
        }
    }


    private static void waitForNetworkLoadBalancerDeletion(NetworkLoadBalancerClient client, String networkLoadBalancerId) {
        final int MAX_ATTEMPTS = 60;
        final int WAIT_SECONDS = 30;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                GetNetworkLoadBalancerRequest request = GetNetworkLoadBalancerRequest.builder()
                        .networkLoadBalancerId(networkLoadBalancerId)
                        .build();

                NetworkLoadBalancer nlb = client.getNetworkLoadBalancer(request).getNetworkLoadBalancer();

                if (nlb.getLifecycleState().equals(LifecycleState.Deleted)) {
                    log.debug("网络负载均衡器已被删除");
                    return;
                }

                log.debug("等待网络负载均衡器删除... 当前状态: {}, 尝试次数: {}/{}",
                        nlb.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (BmcException e) {
                if (e.getStatusCode() == 404) {
                    log.debug("网络负载均衡器已不存在，删除成功");
                    return;
                }
                throw e;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待网络负载均衡器删除过程被中断", e);
            } catch (Exception e) {
                log.warn("检查网络负载均衡器删除状态时出错: {}", e.getMessage());
            }
        }

        throw new RuntimeException("网络负载均衡器在预期时间内未被删除");
    }

    /**
     * 等待路由表删除完成
     */
    private static void waitForRouteTableDeletion(VirtualNetworkClient client, String routeTableId) {
        final int MAX_ATTEMPTS = 30;
        final int WAIT_SECONDS = 10;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                GetRouteTableRequest request = GetRouteTableRequest.builder()
                        .rtId(routeTableId)
                        .build();

                RouteTable routeTable = client.getRouteTable(request).getRouteTable();

                if (routeTable.getLifecycleState() == RouteTable.LifecycleState.Terminated) {
                    log.debug("路由表已被终止");
                    return;
                }

                log.debug("等待路由表删除... 当前状态: {}, 尝试次数: {}/{}",
                        routeTable.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (BmcException e) {
                if (e.getStatusCode() == 404) {
                    log.debug("路由表已不存在，删除成功");
                    return;
                }
                throw e;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待路由表删除过程被中断", e);
            } catch (Exception e) {
                log.warn("检查路由表删除状态时出错: {}", e.getMessage());
            }
        }

        throw new RuntimeException("路由表在预期时间内未被删除");
    }

    /**
     * 删除网络负载均衡器
     */
    public static boolean deleteNetworkLoadBalancer(Tenant tenant, String networkLoadBalancerId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (NetworkLoadBalancerClient nlbClient = NetworkLoadBalancerClient.builder().build(provider)) {
            log.debug("开始删除网络负载均衡器，ID: {}", networkLoadBalancerId);

            // 创建删除请求
            DeleteNetworkLoadBalancerRequest request = DeleteNetworkLoadBalancerRequest.builder()
                    .networkLoadBalancerId(networkLoadBalancerId)
                    .build();

            DeleteNetworkLoadBalancerResponse response = nlbClient.deleteNetworkLoadBalancer(request);

            String workRequestId = response.getOpcWorkRequestId();
            log.debug("网络负载均衡器删除请求已提交，工作请求ID: {}", workRequestId);

            // 等待负载均衡器被删除
            waitForNetworkLoadBalancerDeletion(nlbClient, networkLoadBalancerId);

            log.debug("网络负载均衡器删除成功，ID: {}", networkLoadBalancerId);
            return true;

        } catch (Exception e) {
            log.error("删除网络负载均衡器失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 删除路由表
     */
    public static boolean deleteRouteTable(Tenant tenant, String routeTableId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

        try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {
            log.debug("开始删除路由表，ID: {}", routeTableId);

            // 创建删除请求
            DeleteRouteTableRequest request = DeleteRouteTableRequest.builder()
                    .rtId(routeTableId)
                    .build();

            virtualNetworkClient.deleteRouteTable(request);

            // 等待路由表被删除
            waitForRouteTableDeletion(virtualNetworkClient, routeTableId);

            log.debug("路由表删除成功，ID: {}", routeTableId);
            return true;

        } catch (Exception e) {
            log.error("删除路由表失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 等待NAT网关终止
     */
    private static void waitForNatGatewayTermination(VirtualNetworkClient client, String natGatewayId) {
        final int MAX_ATTEMPTS = 30;
        final int WAIT_SECONDS = 10;

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                GetNatGatewayRequest request = GetNatGatewayRequest.builder()
                        .natGatewayId(natGatewayId)
                        .build();

                NatGateway natGateway = client.getNatGateway(request).getNatGateway();

                if (natGateway.getLifecycleState() == NatGateway.LifecycleState.Terminated) {
                    log.debug("NAT网关已被终止");
                    return;
                }

                log.debug("等待NAT网关终止... 当前状态: {}, 尝试次数: {}/{}",
                        natGateway.getLifecycleState(), attempt + 1, MAX_ATTEMPTS);

                Thread.sleep(WAIT_SECONDS * 1000);

            } catch (BmcException e) {
                if (e.getStatusCode() == 404) {
                    log.debug("NAT网关已不存在，删除成功");
                    return;
                }
                throw e;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("等待NAT网关终止过程被中断", e);
            } catch (Exception e) {
                log.warn("检查NAT网关终止状态时出错: {}", e.getMessage());
            }
        }

        throw new RuntimeException("NAT网关在预期时间内未被终止");
    }

    /**
     * 后端服务器信息
     */
    @Data
    public static class BackendServerInfo {
        private String ipAddress;
        private Integer port;
        private Integer weight;
        private Boolean isBackup;

        public BackendServerInfo(String ipAddress, Integer port) {
            this.ipAddress = ipAddress;
            this.port = port;
            this.weight = 1;
            this.isBackup = false;
        }

        public BackendServerInfo(String ipAddress, Integer port, Integer weight, Boolean isBackup) {
            this.ipAddress = ipAddress;
            this.port = port;
            this.weight = weight;
            this.isBackup = isBackup;
        }

    }

    /**
     * 网络配置结果类
     */
    @Data
    public static class NetworkConfigResult {
        private boolean success;
        private String message;
        private String errorMessage;
        private String natGatewayId;
        private String natGatewayName;
        private String routeTableId;
        private String routeTableName;
        private boolean routeTableUpdated;
        private boolean loadBalancerCreated;
        private String networkLoadBalancerId;
        private String networkLoadBalancerName;

        private List<IpAddress> ipAddress;

        public NetworkConfigResult() {
            this.success = false;
            this.routeTableUpdated = false;
            this.loadBalancerCreated = false;
        }
    }


}
