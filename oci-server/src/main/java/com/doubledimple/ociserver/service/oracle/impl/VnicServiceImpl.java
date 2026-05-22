package com.doubledimple.ociserver.service.oracle.impl;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.RegisterDetail;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.RegisterDetailRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.enums.oci.AccountTypeSubEnum;
import com.doubledimple.ocicommon.enums.oci.PlanTypeSubEnum;
import com.doubledimple.ociserver.pojo.enums.AccountTypeEnum;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.service.oracle.VnicService;
import com.doubledimple.ociserver.utils.oracle.OciNetworkUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.NatGateway;
import com.oracle.bmc.core.model.RouteTable;
import com.oracle.bmc.core.model.Subnet;
import com.oracle.bmc.core.model.UpdateSubnetDetails;
import com.oracle.bmc.core.model.UpdateVnicDetails;
import com.oracle.bmc.core.model.Vnic;
import com.oracle.bmc.core.requests.GetSubnetRequest;
import com.oracle.bmc.core.requests.GetVnicRequest;
import com.oracle.bmc.core.requests.ListRouteTablesRequest;
import com.oracle.bmc.core.requests.UpdateSubnetRequest;
import com.oracle.bmc.core.requests.UpdateVnicRequest;
import com.oracle.bmc.core.responses.UpdateVnicResponse;
import com.oracle.bmc.networkloadbalancer.model.IpAddress;
import com.oracle.bmc.networkloadbalancer.model.NetworkLoadBalancer;
import com.oracle.bmc.ospgateway.model.Subscription;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_LOAD_BALANCER_RESTORE_SUCCESS_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_LOAD_BALANCER_SUCCESS_TEMPLATE;
import static com.doubledimple.ociserver.pojo.enums.AccountTypeEnum.TRIAL_PAID_ACCOUNT;
import static com.doubledimple.ociserver.pojo.enums.AccountTypeEnum.UPGRADE_ACCOUNT;
import static com.doubledimple.ociserver.utils.oracle.OciNetworkUtils.DEFAULT_NAME;
import static com.doubledimple.ociserver.utils.oracle.OciNetworkUtils.createNatRouteTable;
import static com.doubledimple.ociserver.utils.oracle.OciNetworkUtils.createOrGetNatRouteTable;
import static com.doubledimple.ociserver.utils.oracle.OciNetworkUtils.deleteNetworkLoadBalancer;
import static com.doubledimple.ociserver.utils.oracle.OciNetworkUtils.deleteRouteTable;
import static com.doubledimple.ociserver.utils.oracle.OciNetworkUtils.listRouteTables;
import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * @version 1.0.0
 * @ClassName VnicServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-23 11:51
 */
@Service
@Slf4j
public class VnicServiceImpl implements VnicService {

    @Resource
    private TenantService tenantService;


    @Resource
    private OracleInstanceService oracleInstanceService;

    @Resource
    MessageFactory messageFactory;



    @Override
    public ResponseEntity<Map<String, Object>> configureLoadBalancer(String instanceId) {
        Map<String, Object> response = new HashMap<>();

        try {

            log.info("开始配置负载均衡 - 实例ID: {}", instanceId);

            if (instanceId == null) {
                response.put("success", false);
                response.put("message", "实例ID不能为空");
                return ResponseEntity.badRequest().body(response);
            }

            // 根据instanceId获取租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            String accountType = tenant.getAccountType();

            AccountTypeEnum type = AccountTypeEnum.getType(accountType);
            if (type != null &&
                    (type.equals(TRIAL_PAID_ACCOUNT) || type.equals(UPGRADE_ACCOUNT)) &&
                    instanceDetails.getArchitecture().equals(ArchitectureEnum.AMD.getType())){
                log.info("符合基本开启负载均衡条件");
            }else{
                log.warn("该账号不支持开启负载均衡,instanceDetails:{}",instanceDetails);
                response.put("success", false);
                response.put("message", "当前租户不支持");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取实例信息
            Instance instance = OciUtils.getInstanceById(tenant, instanceId);
            if (instance == null) {
                response.put("success", false);
                response.put("message", "找不到指定的实例");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取实例的VCN ID和子网ID
            String vcnId = null;
            String subnetId = null;

            // 获取主VNIC信息
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            Vnic primaryVnic = OciUtils.getVnicPrimary(provider, instance, provider.getTenantId());
            if (primaryVnic != null) {
                subnetId = primaryVnic.getSubnetId();
                // 通过子网获取VCN ID
                vcnId = getVcnIdFromSubnet(tenant, subnetId);
            }

            if (vcnId == null || subnetId == null) {
                response.put("success", false);
                response.put("message", "无法获取实例的网络信息");
                return ResponseEntity.badRequest().body(response);
            }

            log.info("实例网络信息 - VCN ID: {}, 子网ID: {}", vcnId, subnetId);

            // 使用工具类配置完整的网络环境（包含负载均衡器）
            OciNetworkUtils.NetworkConfigResult result = OciNetworkUtils.fullConfigureInstanceNetwork(
                    tenant, instanceId, vcnId, subnetId);

            if (result.isSuccess()) {
                // 构建详细信息
                String nlpPublicIpAddress = result.getIpAddress().stream()
                        .filter(ip -> ip.getIsPublic() != null && ip.getIsPublic())
                        .map(IpAddress::getIpAddress)
                        .findFirst()
                        .orElse(null);
                Map<String, Object> details = new HashMap<>();
                details.put("natGatewayId", result.getNatGatewayId());
                details.put("natGatewayName", result.getNatGatewayName());
                details.put("routeTableId", result.getRouteTableId());
                details.put("routeTableName", result.getRouteTableName());
                details.put("networkLoadBalancerId", result.getNetworkLoadBalancerId());
                details.put("networkLoadBalancerName", result.getNetworkLoadBalancerName());
                details.put("nlpIpAddress",nlpPublicIpAddress);
                response.put("success", true);
                response.put("message", result.getMessage());
                response.put("details", details);

                log.info("负载均衡配置成功 - 实例: {}, 结果: {},公网ip:{}", instanceId, result,nlpPublicIpAddress);
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(
                        String.format(MESSAGE_LOAD_BALANCER_SUCCESS_TEMPLATE,
                                tenant.getUserName(),
                                RegionEnum.getRegionCode(tenant.getRegion()),
                                instance.getDisplayName(),
                                nlpPublicIpAddress
                                ));

            } else {
                response.put("success", false);
                response.put("message", result.getErrorMessage());

                log.error("负载均衡配置失败 - 实例: {}, 错误: {}", instanceId, result.getErrorMessage());
            }

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("配置负载均衡失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "配置负载均衡失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    @Override
    public ResponseEntity<Map<String, Object>> restoreNetwork(String instanceId) {
        Map<String, Object> response = new HashMap<>();

        try {

            log.info("开始还原网络配置 - 实例ID: {}", instanceId);

            if (instanceId == null) {
                response.put("success", false);
                response.put("message", "实例ID不能为空");
                return ResponseEntity.badRequest().body(response);
            }

            // 根据instanceId获取租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            String accountType = tenant.getAccountType();

            AccountTypeEnum type = AccountTypeEnum.getType(accountType);
            if (type != null &&
                    (type.equals(TRIAL_PAID_ACCOUNT) || type.equals(UPGRADE_ACCOUNT)) &&
                    instanceDetails.getArchitecture().equals(ArchitectureEnum.AMD.getType())){
                log.info("符合基本开启负载均衡条件");
            }else{
                log.warn("该账号不支持开启负载均衡,instanceDetails:{}",instanceDetails);
                response.put("success", false);
                response.put("message", "当前租户不支持");
                return ResponseEntity.badRequest().body(response);
            }
            // 获取实例信息
            Instance instance = OciUtils.getInstanceById(tenant, instanceId);
            if (instance == null) {
                response.put("success", false);
                response.put("message", "找不到指定的实例");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取VCN ID
            String vcnId = null;
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            Vnic primaryVnic = OciUtils.getVnicPrimary(provider, instance, provider.getTenantId());
            if (primaryVnic != null) {
                String subnetId = primaryVnic.getSubnetId();
                vcnId = getVcnIdFromSubnet(tenant, subnetId);
            }

            if (vcnId == null) {
                response.put("success", false);
                response.put("message", "无法获取实例的VCN信息");
                return ResponseEntity.badRequest().body(response);
            }

            boolean success = restoreOriginalNetworkConfig(tenant, instanceId, vcnId);

            if (success) {
                response.put("success", true);
                response.put("message", "网络配置已成功还原到原始状态");

                log.info("网络配置还原成功 - 实例: {}", instanceId);

                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(
                        MESSAGE_LOAD_BALANCER_RESTORE_SUCCESS_TEMPLATE,
                        tenant.getUserName(),
                        RegionEnum.getRegionCode(tenant.getRegion()),
                        instance.getDisplayName(),
                        instanceDetails.getPublicIps()));
            } else {
                response.put("success", false);
                response.put("message", "网络配置还原失败，请检查日志");

                log.error("网络配置还原失败 - 实例: {}", instanceId);
            }

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("还原网络配置失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "还原网络配置失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }


    /**
     * 从子网ID获取VCN ID
     */
    private String getVcnIdFromSubnet(Tenant tenant, String subnetId) {
        try {
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (VirtualNetworkClient virtualNetworkClient =
                         VirtualNetworkClient.builder().build(provider)) {

                GetSubnetRequest request =
                        GetSubnetRequest.builder()
                                .subnetId(subnetId)
                                .build();

                Subnet subnet = virtualNetworkClient.getSubnet(request).getSubnet();
                return subnet.getVcnId();
            }

        } catch (Exception e) {
            log.error("获取VCN ID失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 还原原始网络配置
     */
    private boolean restoreOriginalNetworkConfig(Tenant tenant, String instanceId, String vcnId) {
        try {
            String compartmentId = getProvider(tenant).getTenantId();
            boolean allSuccess = true;

            log.info("开始还原网络配置 - VCN: {}", vcnId);


            // 1. 还原路由表到默认配置
            try {
                // 获取实例的主VNIC
                Instance instance = OciUtils.getInstanceById(tenant, instanceId);
                SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
                Vnic primaryVnic = OciUtils.getVnicPrimary(provider, instance, compartmentId);

                if (primaryVnic != null) {
                    // 将子网的路由表重置为默认路由表
                    //resetSubnetToDefaultRouteTable(tenant, primaryVnic.getSubnetId(), vcnId);
                    resetVnicToDefaultRouteTable(tenant, instanceId);
                }
            } catch (Exception e) {
                log.warn("还原路由表时出错: " + e.getMessage());
                allSuccess = false;
            }

            // 2. 删除网络负载均衡器
            try {
                List<NetworkLoadBalancer> nlbs =
                        OciNetworkUtils.listNetworkLoadBalancers(tenant, compartmentId);

                for (NetworkLoadBalancer nlb : nlbs) {
                    if (nlb.getDisplayName().contains("amd")) {
                        log.info("删除网络负载均衡器: {}", nlb.getDisplayName());
                        // 这里需要添加删除网络负载均衡器的方法
                        deleteNetworkLoadBalancer(tenant, nlb.getId());
                    }
                }
            } catch (Exception e) {
                log.warn("删除网络负载均衡器时出错: " + e.getMessage());
                allSuccess = false;
            }

            // 3. 删除NAT网关
            RouteTable amd = null;
            try {
                List<NatGateway> natGateways =
                        OciNetworkUtils.listNatGateways(tenant, vcnId);


                for (NatGateway gateway : natGateways) {
                    if (gateway.getDisplayName().contains("amd")) {
                        log.info("删除NAT网关: {}", gateway.getDisplayName());
                        //删除路由
                        amd = createOrGetNatRouteTable(tenant, vcnId, gateway.getId(),DEFAULT_NAME);
                        if (amd != null){
                            deleteRouteTable(tenant, amd.getId());
                        }
                        boolean deleteSuccess = OciNetworkUtils.deleteNatGateway(tenant, gateway.getId());
                        if (!deleteSuccess) {
                            allSuccess = false;
                        }
                    }
                }
            } catch (Exception e) {
                log.warn("删除NAT网关时出错: " + e.getMessage());
                allSuccess = false;
            }

            log.info("网络配置还原完成 - 成功: {}", allSuccess);
            return allSuccess;

        } catch (Exception e) {
            log.error("还原网络配置失败: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 将子网重置为默认路由表
     */
    private void resetSubnetToDefaultRouteTable(Tenant tenant, String subnetId, String vcnId) {
        try {
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (VirtualNetworkClient virtualNetworkClient =
                         VirtualNetworkClient.builder().build(provider)) {

                // 获取VCN的默认路由表
                ListRouteTablesRequest listRequest =
                        ListRouteTablesRequest.builder()
                                .compartmentId(provider.getTenantId())
                                .vcnId(vcnId)
                                .build();

                List<RouteTable> routeTables =
                        virtualNetworkClient.listRouteTables(listRequest).getItems();

                // 找到默认路由表（通常是第一个创建的）
                RouteTable defaultRouteTable = null;
                for (RouteTable rt : routeTables) {
                    if (rt.getDisplayName().toLowerCase().contains("default")) {
                        defaultRouteTable = rt;
                        break;
                    }
                }

                // 如果没找到默认路由表，使用第一个
                if (defaultRouteTable == null && !routeTables.isEmpty()) {
                    defaultRouteTable = routeTables.get(0);
                }

                if (defaultRouteTable != null) {
                    // 更新子网的路由表
                    UpdateSubnetDetails updateSubnetDetails =
                            UpdateSubnetDetails.builder()
                                    .routeTableId(defaultRouteTable.getId())
                                    .build();

                    UpdateSubnetRequest updateRequest =
                            UpdateSubnetRequest.builder()
                                    .subnetId(subnetId)
                                    .updateSubnetDetails(updateSubnetDetails)
                                    .build();

                    virtualNetworkClient.updateSubnet(updateRequest);

                    log.info("子网路由表已重置为默认路由表: {}", defaultRouteTable.getDisplayName());
                }
            }

        } catch (Exception e) {
            log.error("重置子网路由表失败: " + e.getMessage(), e);
            throw e;
        }
    }

    /**
     * 将VNIC从定制路由表切换回使用子网的默认路由表
     */
    private void resetVnicToDefaultRouteTable(Tenant tenant, String instanceId) {
        try {
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (VirtualNetworkClient virtualNetworkClient = VirtualNetworkClient.builder().build(provider)) {

                log.info("开始将VNIC重置为使用VCN或子网路由表，实例ID: {}", instanceId);

                // 获取实例的主VNIC
                Instance instance = OciUtils.getInstanceById(tenant, instanceId);
                if (instance == null) {
                    log.error("未找到实例: {}", instanceId);
                    return;
                }

                Vnic primaryVnic = OciUtils.getVnicPrimary(provider, instance, provider.getTenantId());
                if (primaryVnic == null) {
                    log.error("未找到实例的主VNIC，实例ID: {}", instanceId);
                    return;
                }

                log.debug("找到主VNIC: {}, 当前路由表设置: {}",
                        primaryVnic.getId(),
                        primaryVnic.getRouteTableId() != null ? primaryVnic.getRouteTableId() : "使用子网默认路由表");

                String subnetId = primaryVnic.getSubnetId();
                // 通过子网获取VCN ID
                String vcnId = getVcnIdFromSubnet(tenant, subnetId);
                List<RouteTable> existingRouteTables = listRouteTables(tenant, vcnId);
                String routeTableId = "";
                for (RouteTable existingRouteTable : existingRouteTables) {
                    final String displayName = existingRouteTable.getDisplayName();
                    if (!displayName.equals(DEFAULT_NAME)){
                        routeTableId = existingRouteTable.getId();
                        break;
                    }
                }


                UpdateVnicDetails updateVnicDetails = UpdateVnicDetails.builder()
                        .routeTableId(routeTableId)
                        .build();

                UpdateVnicRequest updateVnicRequest = UpdateVnicRequest.builder()
                        .vnicId(primaryVnic.getId())
                        .updateVnicDetails(updateVnicDetails)
                        .build();

                UpdateVnicResponse response = virtualNetworkClient.updateVnic(updateVnicRequest);

                log.info("VNIC路由表设置已重置！");
                log.info("VNIC现在使用: 子网默认路由表");
                log.info("VNIC ID: {}", response.getVnic().getId());
                log.info("路由表ID: {}", response.getVnic().getRouteTableId() == null ? "null (使用子网路由表)" : response.getVnic().getRouteTableId());

                // 等待VNIC更新完成
                waitForVnicUpdate(virtualNetworkClient, primaryVnic.getId());

                // 验证切换结果
                verifyVnicRouteTableReset(virtualNetworkClient, primaryVnic.getId());

            }

        } catch (Exception e) {
            log.error("重置VNIC路由表失败: " + e.getMessage(), e);
            throw e;
        }
    }

    /**
     * 验证VNIC路由表重置结果
     */
    private void verifyVnicRouteTableReset(VirtualNetworkClient client, String vnicId) {
        try {
            GetVnicRequest request = GetVnicRequest.builder()
                    .vnicId(vnicId)
                    .build();

            Vnic vnic = client.getVnic(request).getVnic();

            log.info("=== VNIC路由表重置验证 ===");
            log.info("VNIC ID: {}", vnic.getId());

            if (vnic.getRouteTableId() == null) {
                log.info("✅ VNIC已成功切换为使用子网路由表");
                log.info("路由模式: 使用 VCN 或子网路由表");

                // 获取子网信息显示实际使用的路由表
                GetSubnetRequest subnetRequest = GetSubnetRequest.builder()
                        .subnetId(vnic.getSubnetId())
                        .build();
                Subnet subnet = client.getSubnet(subnetRequest).getSubnet();

                log.info("实际使用的路由表: {} (来自子网)", subnet.getRouteTableId());

            } else {
                log.warn("⚠️ VNIC仍在使用定制路由表: {}", vnic.getRouteTableId());
                log.info("路由模式: 选择用于 VNIC 的定制路由表");
            }

        } catch (Exception e) {
            log.warn("验证VNIC路由表重置结果时出错: {}", e.getMessage());
        }
    }

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
                    log.info("VNIC更新完成");
                    return;
                }

                log.info("等待VNIC更新完成... 当前状态: {}, 尝试次数: {}/{}",
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

}
