package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ociserver.pojo.request.IpSwitchRequest;
import com.doubledimple.ociserver.pojo.request.IpVnicSwitchRequest;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.service.oracle.VnicService;
import com.doubledimple.ociserver.utils.oracle.OciNetworkUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.doubledimple.ociserver.utils.oracle.vnic.BatchVnicCreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.Ipv6CreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicManagementUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName VnicManagementController
 * @Description VNIC网络管理控制器
 * @Author doubleDimple
 * @Date 2025-01-20 10:00
 */
@Slf4j
@Controller
@RequestMapping("/oci/vnic")
public class VnicManagementController  extends BaseController{

    @Resource
    private TenantService tenantService;

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private OracleInstanceService oracleInstanceService;

    @Resource
    @Lazy
    VnicService vnicService;

    /**
     * 显示VNIC管理页面
     */
    @GetMapping("/manage")
    public String vnicManagePage(@RequestParam("instanceId") String instanceId, Model model) {
        try {
            log.info("访问VNIC管理页面，实例ID: {}", instanceId);

            // 只传递必要的参数，页面会异步加载数据
            model.addAttribute("instanceId", instanceId);
            model.addAttribute("activePage", "api-management");

            // 初始化空数据，避免模板报错
            model.addAttribute("vnicList", java.util.Collections.emptyList());
            model.addAttribute("primaryVnic", new VnicCreationResult());
            model.addAttribute("secondaryVnics", java.util.Collections.emptyList());

            return "oci_network_manage";

        } catch (Exception e) {
            log.error("显示VNIC管理页面失败: " + e.getMessage(), e);
            model.addAttribute("error", "加载页面失败: " + e.getMessage());
            return "error";
        }
    }

    @GetMapping("/loadData")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> loadVnicData(@RequestParam("instanceId") String instanceId) {
        Map<String, Object> response = new HashMap<>();

        try {
            log.info("加载VNIC数据，实例ID: {}", instanceId);

            // 根据instanceId获取租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // API获取实例的所有VNIC信息
            List<VnicCreationResult> vnicList = VnicManagementUtils.getInstanceVnics(
                    tenant, instanceId,instanceDetails.getCompartmentId());

            // 从vnicList中解析主VNIC和辅助VNIC
            VnicCreationResult primaryVnic = null;
            List<VnicCreationResult> secondaryVnics = new ArrayList<>();

            for (VnicCreationResult vnic : vnicList) {
                if (vnic.getIsPrimary()) {
                    primaryVnic = vnic;
                } else {
                    secondaryVnics.add(vnic);
                }
            }

            // 生成统计信息
            Map<String, Object> statistics = generateStatistics(vnicList, primaryVnic, secondaryVnics);

            Map<String, Object> data = new HashMap<>();
            data.put("vnicList", vnicList);
            data.put("primaryVnic", primaryVnic);
            data.put("secondaryVnics", secondaryVnics);
            data.put("statistics", statistics);
            data.put("tenantId", String.valueOf(instanceDetails.getTenantId()));

            response.put("success", true);
            response.put("data", data);
            response.put("message", "数据加载成功");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("加载VNIC数据失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "加载VNIC数据失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * 创建VNIC
     */
    @PostMapping("/create")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> createVnic(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String instanceId = (String) request.get("instanceId");
            String subnetId = (String) request.get("subnetId");
            Integer vnicCount = (Integer) request.get("vnicCount");
            Integer ipv6CountPerVnic = (Integer) request.get("ipv6CountPerVnic");

            log.info("创建VNIC请求 - 实例: {}, 子网: {}, VNIC数量: {}, IPv6数量: {}",
                    instanceId, subnetId, vnicCount, ipv6CountPerVnic);

            // 参数验证
            if (instanceId == null || subnetId == null || vnicCount == null || ipv6CountPerVnic == null) {
                response.put("success", false);
                response.put("message", "参数不完整");
                return ResponseEntity.badRequest().body(response);
            }

            // 验证参数范围
            VnicManagementUtils.validateVnicCreationParameters(vnicCount, ipv6CountPerVnic);
            // 根据instanceId获取租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            // 获取租户信息
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 创建VNIC
            boolean isCreateSubnet = false;
            BatchVnicCreationResult result = VnicManagementUtils.createMultipleVnicsWithIpv6(
                    tenant, instanceId, vnicCount, ipv6CountPerVnic,instanceDetails,subnetId,isCreateSubnet);
            if (result.isAllSuccessful()){
                response.put("success", result.isAllSuccessful());
                response.put("message", result.getSummary());
                response.put("details", result);
            }else{
                log.error("VNIC创建失败: " + result.getSummary());
                response.put("success", false);
                response.put("message", result.getSummary());
                return ResponseEntity.badRequest().body(response);
            }


            if (result.isAllSuccessful()) {
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.ok(response); // 部分成功也返回200，让前端根据success字段判断
            }

        } catch (IllegalArgumentException e) {
            log.error("VNIC创建参数错误: " + e.getMessage());
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(response);

        } catch (Exception e) {
            log.error("创建VNIC失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "创建VNIC失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * 删除VNIC
     */
    @PostMapping("/delete")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> deleteVnic(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String instanceId = (String) request.get("instanceId");
            String vnicId = (String) request.get("vnicId");

            log.info("删除VNIC请求 - 实例: {}, VNIC: {}", instanceId, vnicId);

            if (instanceId == null || vnicId == null) {
                response.put("success", false);
                response.put("message", "参数不完整");
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

            // 删除VNIC
            boolean success = VnicManagementUtils.deleteVnicWithIpv6(tenant, instanceId, vnicId);

            response.put("success", success);
            response.put("message", success ? "VNIC删除成功" : "VNIC删除失败");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("删除VNIC失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "删除VNIC失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * 为VNIC创建IPv6地址
     */
    @PostMapping("/createIpv6")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> createIpv6(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String vnicId = (String) request.get("vnicId");
            Integer ipv6Count = (Integer) request.get("ipv6Count");
            String instanceId = (String) request.get("instanceId");

            log.info("创建IPv6请求 - VNIC: {}, 数量: {}", vnicId, ipv6Count);

            if (vnicId == null || ipv6Count == null || instanceId == null) {
                response.put("success", false);
                response.put("message", "参数不完整");
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

            // 创建IPv6地址
            List<Ipv6CreationResult> ipv6Results = VnicManagementUtils.createIpv6ForVnic(tenant, vnicId, ipv6Count);

            long successCount = ipv6Results.stream().mapToLong(r -> r.isSuccess() ? 1 : 0).sum();
            boolean allSuccess = successCount == ipv6Count;

            OciUtils.resetInstance(tenant, instanceId);

            response.put("success", allSuccess);
            response.put("message", String.format("IPv6地址创建完成 - 成功: %d/%d", successCount, ipv6Count));
            response.put("details", ipv6Results);

            //重新启动实例
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("创建IPv6地址失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "创建IPv6地址失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * 删除IPv6地址
     */
    @PostMapping("/deleteIpv6")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> deleteIpv6(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String ipv6Address = (String) request.get("ipv6Address");  // 改为接收IPv6地址
            String vnicId = (String) request.get("vnicId");           // 同时接收VNIC ID
            String instanceId = (String) request.get("instanceId");

            log.info("删除IPv6请求 - IPv6地址: {}, VNIC: {}", ipv6Address, vnicId);

            if (ipv6Address == null || vnicId == null || instanceId == null) {
                response.put("success", false);
                response.put("message", "参数不完整");
                return ResponseEntity.badRequest().body(response);
            }

            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 调用修改后的删除方法
            boolean success = VnicManagementUtils.deleteIpv6Address(tenant, vnicId, ipv6Address);

            response.put("success", success);
            response.put("message", success ? "IPv6地址删除成功" : "IPv6地址删除失败");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("删除IPv6地址失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "删除IPv6地址失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * 删除所有辅助VNIC
     */
    @PostMapping("/deleteAllSecondary")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> deleteAllSecondaryVnics(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String instanceId = (String) request.get("instanceId");

            log.info("删除所有辅助VNIC请求 - 实例: {}", instanceId);

            if (instanceId == null) {
                response.put("success", false);
                response.put("message", "实例ID不能为空");
                return ResponseEntity.badRequest().body(response);
            }

            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 删除所有辅助VNIC
            Map<String, Boolean> deleteResults = VnicManagementUtils.deleteAllSecondaryVnics(
                    tenant, instanceId,instanceDetails.getCompartmentId());

            long successCount = deleteResults.values().stream().mapToLong(result -> result ? 1 : 0).sum();
            boolean allSuccess = successCount == deleteResults.size();

            response.put("success", allSuccess);
            response.put("message", String.format("辅助VNIC删除完成 - 成功: %d/%d", successCount, deleteResults.size()));
            response.put("details", deleteResults);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("删除所有辅助VNIC失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "删除所有辅助VNIC失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * 刷新VNIC信息
     */
    @GetMapping("/refresh")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> refreshVnicInfo(@RequestParam("instanceId") String instanceId) {
        Map<String, Object> response = new HashMap<>();

        try {
            log.info("加载VNIC数据，实例ID: {}", instanceId);

            // 根据instanceId获取租户信息
            InstanceDetails instanceDetails = oracleInstanceService.getInstanceByInstanceId(instanceId);
            Tenant tenant = tenantService.getById(instanceDetails.getTenantId());
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "找不到对应的租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // API获取实例的所有VNIC信息
            List<VnicCreationResult> vnicList = VnicManagementUtils.getInstanceVnics(
                    tenant, instanceId,instanceDetails.getCompartmentId());

            // 从vnicList中解析主VNIC和辅助VNIC
            VnicCreationResult primaryVnic = null;
            List<VnicCreationResult> secondaryVnics = new ArrayList<>();

            for (VnicCreationResult vnic : vnicList) {
                if (vnic.getIsPrimary()) {
                    primaryVnic = vnic;
                } else {
                    secondaryVnics.add(vnic);
                }
            }

            // 生成统计信息
            Map<String, Object> statistics = generateStatistics(vnicList, primaryVnic, secondaryVnics);

            Map<String, Object> data = new HashMap<>();
            data.put("vnicList", vnicList);
            data.put("primaryVnic", primaryVnic);
            data.put("secondaryVnics", secondaryVnics);
            data.put("statistics", statistics);

            response.put("success", true);
            response.put("data", data);
            response.put("message", "数据加载成功");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("加载VNIC数据失败: " + e.getMessage(), e);
            response.put("success", false);
            response.put("message", "加载VNIC数据失败: " + e.getMessage());
            return ResponseEntity.internalServerError().body(response);
        }
    }

    private Map<String, Object> generateStatistics(List<VnicCreationResult> vnicList,
                                                   VnicCreationResult primaryVnic,
                                                   List<VnicCreationResult> secondaryVnics) {
        Map<String, Object> statistics = new HashMap<>();

        // 总VNIC数量
        statistics.put("totalVnicCount", vnicList.size());

        // 活跃VNIC数量（状态为ATTACHED的）
        long activeCount = vnicList.stream()
                .filter(vnic -> "ATTACHED".equals(vnic.getLifecycleState()))
                .count();
        statistics.put("activeVnicCount", activeCount);

        // 辅助VNIC数量
        statistics.put("secondaryVnicCount", secondaryVnics.size());

        // 总IPv6地址数量
        int totalIpv6Count = vnicList.stream()
                .mapToInt(vnic -> vnic.getIpv6Addresses() != null ? vnic.getIpv6Addresses().size() : 0)
                .sum();
        statistics.put("totalIpv6Count", totalIpv6Count);

        // 主VNIC IPv6数量
        int primaryIpv6Count = 0;
        if (primaryVnic != null && primaryVnic.getIpv6Addresses() != null) {
            primaryIpv6Count = primaryVnic.getIpv6Addresses().size();
        }
        statistics.put("primaryIpv6Count", primaryIpv6Count);

        return statistics;
    }


    @PostMapping("/changeSpecIp")
    public ResponseEntity<?> changeSpecIp(@RequestBody IpVnicSwitchRequest ipVnicSwitchRequest){
        InstanceDetails byInstanceId = oracleInstanceDetailRepository.findByInstanceId(ipVnicSwitchRequest.getInstanceId());
        IpSwitchRequest build = IpSwitchRequest.builder()
                .instanceId(byInstanceId.getId())
                .tenantId(byInstanceId.getTenantId())
                .cidrRanges(ipVnicSwitchRequest.getCidrRanges())
                .build();
        return oracleInstanceService.switchVnicToSpecificIpRange(ipVnicSwitchRequest);
    }

    /**
     * 一键配置负载均衡
     */
    @PostMapping("/network/configureLoadBalancer")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> configureLoadBalancer(@RequestBody Map<String, Object> request) {
        String instanceId = (String) request.get("instanceId");
        return vnicService.configureLoadBalancer(instanceId);
    }


    /**
     * 还原网络配置
     */
    @PostMapping("/network/restoreNetwork")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> restoreNetwork(@RequestBody Map<String, Object> request) {
        String instanceId = (String) request.get("instanceId");
        return vnicService.restoreNetwork(instanceId);
    }
}
