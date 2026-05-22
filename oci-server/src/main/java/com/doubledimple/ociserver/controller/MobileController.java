package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.ModelAttribute;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 移动端专属控制器，路由前缀 /m
 */
@Controller
@RequestMapping("/m")
@Slf4j
public class MobileController extends BaseController {

    @Resource
    private TenantService tenantService;

    @Resource
    private BootInstanceService bootInstanceService;

    @Resource
    private OracleInstanceService oracleInstanceService;

    @Resource
    private BootInstanceRepository bootInstanceRepository;

    @Resource
    private SystemConfigService systemConfigService;

    // ===================== 公共属性 =====================

    @ModelAttribute("currentUsername")
    public String currentUsername() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return auth != null ? auth.getName() : "";
    }

    // ===================== 页面路由 =====================

    @GetMapping({"", "/"})
    public String home() {
        return "redirect:/m/tenants";
    }

    @GetMapping("/tenants")
    public String tenantsPage(Model model) {
        model.addAttribute("activePage", "tenants");
        return "mobile/tenants";
    }

    @GetMapping("/boot")
    public String bootPage(Model model) {
        model.addAttribute("activePage", "boot");
        return "mobile/boot";
    }

    @GetMapping("/instances")
    public String instancesPage(Model model) {
        model.addAttribute("activePage", "instances");
        return "mobile/instances";
    }

    @GetMapping("/speedtest")
    public String speedtestPage(Model model) {
        model.addAttribute("activePage", "speedtest");
        return "mobile/speedtest";
    }

    @GetMapping("/monitor")
    public String monitorPage(Model model) {
        model.addAttribute("activePage", "monitor");
        return "mobile/monitor";
    }

    @GetMapping("/sysHelp")
    public String sysHelpPage(@RequestParam(required = false) String instanceId, Model model) {
        if (instanceId == null || instanceId.trim().isEmpty()) {
            log.warn("移动端系统救援页面：instanceId 为空，重定向到租户页");
            return "redirect:/m/tenants";
        }
        try {
            com.doubledimple.dao.entity.InstanceDetails instance =
                    oracleInstanceService.getInstanceById(Long.valueOf(instanceId.trim()));
            if (instance == null) {
                return "redirect:/m/tenants";
            }
            model.addAttribute("instance", instance);
            model.addAttribute("instanceId", instanceId);
            model.addAttribute("activePage", "");
            return "mobile/sys_help";
        } catch (Exception e) {
            log.error("移动端系统救援页面加载失败, instanceId={}", instanceId, e);
            return "redirect:/m/tenants";
        }
    }

    @GetMapping("/vnic/manage")
    public String vnicManagePage(@RequestParam String instanceId, Model model) {
        try {
            com.doubledimple.dao.entity.InstanceDetails instance =
                    oracleInstanceService.getInstanceByInstanceId(instanceId);
            model.addAttribute("instanceId", instanceId);
            model.addAttribute("instanceName", instance != null ? instance.getDisplayName() : "");
            model.addAttribute("activePage", "");
            return "mobile/vnic_manage";
        } catch (Exception e) {
            log.error("移动端网络管理页面加载失败, instanceId={}", instanceId, e);
            model.addAttribute("instanceId", instanceId);
            model.addAttribute("instanceName", "");
            model.addAttribute("activePage", "");
            return "mobile/vnic_manage";
        }
    }

    @GetMapping("/settings")
    public String settingsPage(Model model, Authentication authentication) {
        model.addAttribute("activePage", "settings");
        model.addAttribute("githubConfig", systemConfigService.getGithubConfig());
        model.addAttribute("googleConfig", systemConfigService.getGoogleConfig());
        model.addAttribute("mfaConfig", systemConfigService.getMfaConfig());
        return "mobile/settings";
    }

    @GetMapping("/arm-regions")
    public String armRegionsPage(Model model) {
        model.addAttribute("activePage", "arm-regions");
        return "mobile/arm_regions";
    }

    @GetMapping("/cloudflare")
    public String cloudflarePage(Model model) {
        model.addAttribute("activePage", "cloudflare");
        model.addAttribute("cloudflareConfig", systemConfigService.getCloudflareConfig());
        return "mobile/cloudflare";
    }

    @GetMapping("/ai")
    public String aiPage(Model model) {
        model.addAttribute("activePage", "ai");
        return "mobile/ai";
    }

    @GetMapping("/notify-settings")
    public String notifySettingsPage(Model model) {
        model.addAttribute("activePage", "notify-settings");
        model.addAttribute("telegramConfig", systemConfigService.getTelegramConfig());
        model.addAttribute("dingTalkConfig", systemConfigService.getDingTalkConfig());
        model.addAttribute("barkConfig", systemConfigService.getBarkConfig());
        model.addAttribute("feishuConfig", systemConfigService.getFeishuConfig());
        model.addAttribute("proxyConfig", systemConfigService.getProxyConfig());
        model.addAttribute("taskConfig", systemConfigService.getTaskConfig());
        return "mobile/notify_settings";
    }

    @GetMapping("/traffic")
    public String trafficPage(@RequestParam(required = false) String tenantId, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("activePage", "traffic");
        return "mobile/traffic";
    }

    @GetMapping("/cost")
    public String costPage(@RequestParam(required = false) String tenantId, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("activePage", "cost");
        return "mobile/cost";
    }

    @GetMapping("/region-sub")
    public String regionSubPage(@RequestParam(required = false) String tenantId,
                                @RequestParam(required = false) String tenantName, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("tenantName", tenantName != null ? tenantName : "");
        model.addAttribute("activePage", "tenants");
        return "mobile/region_sub";
    }

    @GetMapping("/user-mgr")
    public String userMgrPage(@RequestParam(required = false) String tenantId,
                              @RequestParam(required = false) String tenantName, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("tenantName", tenantName != null ? tenantName : "");
        model.addAttribute("activePage", "tenants");
        return "mobile/user_mgr";
    }

    @GetMapping("/audit-log")
    public String auditLogPage(@RequestParam(required = false) String tenantId,
                               @RequestParam(required = false) String tenantName, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("tenantName", tenantName != null ? tenantName : "");
        model.addAttribute("activePage", "tenants");
        return "mobile/audit_log";
    }

    @GetMapping("/disk-info")
    public String diskInfoPage(@RequestParam(required = false) String tenantId,
                               @RequestParam(required = false) String tenantName, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("tenantName", tenantName != null ? tenantName : "");
        model.addAttribute("activePage", "tenants");
        return "mobile/disk_info";
    }

    @GetMapping("/security-rules")
    public String securityRulesPage(@RequestParam(required = false) String tenantId,
                                    @RequestParam(required = false) String tenantName, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("tenantName", tenantName != null ? tenantName : "");
        model.addAttribute("activePage", "tenants");
        return "mobile/security_rules";
    }

    @GetMapping("/storage-instances")
    public String storageInstancesPage(@RequestParam(required = false) String tenantId,
                                       @RequestParam(required = false) String tenantName, Model model) {
        model.addAttribute("tenantId", tenantId != null ? tenantId : "");
        model.addAttribute("tenantName", tenantName != null ? tenantName : "");
        model.addAttribute("activePage", "tenants");
        return "mobile/storage_instances";
    }

    @GetMapping("/memo")
    public String memoPage(Model model) {
        model.addAttribute("activePage", "memo");
        return "mobile/memo";
    }

    // ===================== 数据 API =====================

    /**
     * 获取所有父级租户列表（含区域数量）
     */
    @GetMapping("/api/tenants")
    @ResponseBody
    public ApiResponse getTenants() {
        try {
            List<Tenant> parents = tenantService.getParentTenants();
            List<Map<String, Object>> result = new ArrayList<>();
            for (Tenant t : parents) {
                String userName = StringUtils.isBlank(t.getTenancyName()) ? t.getUserName() : t.getTenancyName();
                Map<String, Object> map = new HashMap<>();
                map.put("id", t.getId()+"");
                map.put("tenantId", t.getTenantId());
                map.put("tenancy", t.getTenancy());
                map.put("userName", userName);
                map.put("region", t.getRegion());
                map.put("accountType", t.getAccountType());
                map.put("cloudType", t.getCloudType());
                map.put("activeDays", t.getActiveDays());
                map.put("defName", t.getDefName());
                map.put("accountCost", t.getAccountCost());
                map.put("accountTypeName", t.getAccountTypeName());
                try {
                    List<Tenant> regions = tenantService.regionList(t.getId());
                    map.put("regionCount", regions.size());
                } catch (Exception e) {
                    map.put("regionCount", 0);
                }
                result.add(map);
            }
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取租户列表失败", e);
            return ApiResponse.error("获取租户列表失败: " + e.getMessage());
        }
    }

    /**
     * 获取某个父租户下的所有区域（含实例数量）
     */
    @GetMapping("/api/tenants/{tenantId}/regions")
    @ResponseBody
    public ApiResponse getRegions(@PathVariable Long tenantId) {
        try {
            List<Tenant> regions = tenantService.regionList(tenantId);
            List<Map<String, Object>> result = new ArrayList<>();
            for (Tenant t : regions) {
                Map<String, Object> map = new HashMap<>();
                map.put("id", t.getId()+ "");
                map.put("tenantId", t.getTenantId());
                map.put("region", t.getRegion());
                String regionNameCh = RegionEnum.getNameCh(t.getRegion());
                map.put("regionNameCh", regionNameCh != null ? regionNameCh : t.getRegion());
                map.put("isHomeRegion", t.getIsHomeRegion());
                try {
                    Page<InstanceDetailsRes> instances =
                            oracleInstanceService.getInstancePageByTenantId(t.getId().toString(), 0, 100);
                    map.put("instanceCount", instances.getTotalElements());
                } catch (Exception e) {
                    map.put("instanceCount", 0);
                }
                result.add(map);
            }
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取区域列表失败, tenantId={}", tenantId, e);
            return ApiResponse.error("获取区域列表失败: " + e.getMessage());
        }
    }

    /**
     * 获取指定区域（子租户）的实例列表
     */
    @GetMapping("/api/regions/{tenantId}/instances")
    @ResponseBody
    public ApiResponse getRegionInstances(@PathVariable String tenantId,
                                          @RequestParam(defaultValue = "0") int page,
                                          @RequestParam(defaultValue = "50") int size) {
        try {
            Page<InstanceDetailsRes> instances =
                    oracleInstanceService.getInstancePageByTenantId(tenantId, page, size);
            Map<String, Object> result = new HashMap<>();
            result.put("list", instances.getContent());
            result.put("total", instances.getTotalElements());
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取区域实例失败, tenantId={}", tenantId, e);
            return ApiResponse.error("获取实例列表失败: " + e.getMessage());
        }
    }

    /**
     * 获取所有开机任务列表
     */
    @GetMapping("/api/boot")
    @ResponseBody
    public ApiResponse getBootTasks(@RequestParam(defaultValue = "0") int page,
                                    @RequestParam(defaultValue = "100") int size) {
        try {
            Page<BootInstanceRes> boots = bootInstanceService.getAllBoots(page, size);
            Map<String, Object> result = new HashMap<>();
            result.put("list", boots.getContent());
            result.put("total", boots.getTotalElements());
            long runningCount = bootInstanceService.countByStatus(1);
            result.put("runningCount", runningCount);
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取开机任务失败", e);
            return ApiResponse.error("获取开机任务失败: " + e.getMessage());
        }
    }

    /**
     * 启动某个开机任务
     */
    @PostMapping("/api/boot/{bootId}/start")
    @ResponseBody
    public ApiResponse startBoot(@PathVariable Long bootId) {
        try {
            Optional<BootInstance> opt = bootInstanceRepository.findById(bootId);
            if (!opt.isPresent()) {
                return ApiResponse.error("任务不存在");
            }
            BootInstance bootInstance = opt.get();
            bootInstanceService.startInstance(bootInstance);
            return ApiResponse.success("启动成功");
        } catch (Exception e) {
            log.error("启动开机任务失败, bootId={}", bootId, e);
            return ApiResponse.error("启动失败: " + e.getMessage());
        }
    }

    /**
     * 停止某个开机任务
     */
    @PostMapping("/api/boot/{bootId}/stop")
    @ResponseBody
    public ApiResponse stopBoot(@PathVariable Long bootId) {
        try {
            Optional<BootInstance> opt = bootInstanceRepository.findById(bootId);
            if (!opt.isPresent()) {
                return ApiResponse.error("任务不存在");
            }
            BootInstance bootInstance = opt.get();
            if (bootInstance.getStatus() == 1) {
                bootInstanceService.stopBoot(bootInstance);
            }
            return ApiResponse.success("已停止");
        } catch (Exception e) {
            log.error("停止开机任务失败, bootId={}", bootId, e);
            return ApiResponse.error("停止失败: " + e.getMessage());
        }
    }

    /**
     * 删除单个开机任务（详情级别删除）
     */
    @PostMapping("/api/boot/{bootId}/delete")
    @ResponseBody
    public ApiResponse deleteSingleBoot(@PathVariable Long bootId) {
        try {
            Optional<BootInstance> opt = bootInstanceRepository.findById(bootId);
            if (!opt.isPresent()) {
                return ApiResponse.error("任务不存在");
            }
            bootInstanceService.deleteBoot(opt.get());
            return ApiResponse.success("已删除");
        } catch (Exception e) {
            log.error("删除开机任务失败, bootId={}", bootId, e);
            return ApiResponse.error("删除失败: " + e.getMessage());
        }
    }

    /**
     * 删除同一租户+架构下的全部开机任务（外层分组删除）
     */
    @PostMapping("/api/boot/{bootId}/deleteAll")
    @ResponseBody
    public ApiResponse deleteAllBoot(@PathVariable Long bootId) {
        try {
            Optional<BootInstance> opt = bootInstanceRepository.findById(bootId);
            if (!opt.isPresent()) {
                return ApiResponse.error("任务不存在");
            }
            BootInstance ref = opt.get();
            List<BootInstance> all = bootInstanceRepository
                    .findByTenantIdAndArchitectureOrderByCreatedAtDesc(
                            ref.getTenantId(), ref.getArchitecture());
            for (BootInstance instance : all) {
                bootInstanceService.deleteBoot(instance);
            }
            return ApiResponse.success("已全部删除");
        } catch (Exception e) {
            log.error("批量删除开机任务失败, bootId={}", bootId, e);
            return ApiResponse.error("删除失败: " + e.getMessage());
        }
    }

    /**
     * 获取某个开机任务组的所有子任务（按 tenantId + architecture 查询）
     */
    @GetMapping("/api/boot/{bootId}/subtasks")
    @ResponseBody
    public ApiResponse getBootSubtasks(@PathVariable Long bootId) {
        try {
            Optional<BootInstance> opt = bootInstanceRepository.findById(bootId);
            if (!opt.isPresent()) {
                return ApiResponse.error("任务不存在");
            }
            BootInstance ref = opt.get();
            List<BootInstance> subtasks = bootInstanceRepository
                    .findByTenantIdAndArchitectureOrderByCreatedAtDesc(
                            ref.getTenantId(), ref.getArchitecture());

            List<Map<String, Object>> result = new ArrayList<>();
            for (BootInstance b : subtasks) {
                Map<String, Object> item = new HashMap<>();
                item.put("id", b.getId());
                item.put("status", b.getStatus());
                item.put("currentAttemptCount", b.getCurrentAttemptCount());
                item.put("addCount", b.getAddCount());
                item.put("successCount", b.getSuccessCount());
                item.put("failCount", b.getFailCount());
                item.put("yesterdayAttemptCount", b.getYesterdayAttemptCount());
                item.put("rootPassword", b.getRootPassword());
                item.put("operatingSystem", b.getOperatingSystem());
                item.put("operatingSystemVersion", b.getOperatingSystemVersion());
                item.put("ocpu", b.getOcpu());
                item.put("memory", b.getMemory());
                item.put("disk", b.getDisk());
                item.put("loopTime", b.getLoopTime());
                item.put("dayGap", b.getDayGap());
                // 补充区域名称
                Tenant tenant = tenantService.getById(b.getTenantId());
                if (tenant != null) {
                    item.put("regionName", RegionEnum.getNameSimple(tenant.getRegion()));
                    item.put("region", tenant.getRegion());
                } else {
                    item.put("regionName", "");
                    item.put("region", "");
                }
                result.add(item);
            }
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取开机子任务失败, bootId={}", bootId, e);
            return ApiResponse.error("获取子任务失败: " + e.getMessage());
        }
    }

    /**
     * 获取全局实例列表
     */
    @GetMapping("/api/instances")
    @ResponseBody
    public ApiResponse getInstances(@RequestParam(defaultValue = "0") int page,
                                    @RequestParam(defaultValue = "50") int size,
                                    @RequestParam(required = false) String tenantId) {
        try {
            Page<InstanceDetailsRes> instances;
            if (tenantId != null && !tenantId.isEmpty()) {
                instances = oracleInstanceService.getInstancePageByTenantId(tenantId, page, size);
            } else {
                instances = oracleInstanceService.getAllInstances(page, size, null);
            }
            Map<String, Object> result = new HashMap<>();
            result.put("list", instances.getContent());
            result.put("total", instances.getTotalElements());
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取实例列表失败", e);
            return ApiResponse.error("获取实例列表失败: " + e.getMessage());
        }
    }
}
