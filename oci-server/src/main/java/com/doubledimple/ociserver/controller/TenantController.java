package com.doubledimple.ociserver.controller;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TrafficAlert;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.config.context.UserContext;
import com.doubledimple.ociserver.config.exception.OciExceptionFactory;
import com.doubledimple.ociserver.pojo.domain.query.BootInstanceQuery;
import com.doubledimple.ociserver.pojo.dto.TenantTransferRequest;
import com.doubledimple.ociserver.pojo.request.AuditLogRequest;
import com.doubledimple.ociserver.pojo.request.DeleteOciUserRequest;
import com.doubledimple.ociserver.pojo.request.ImageInfoReq;
import com.doubledimple.ociserver.pojo.request.ResetOciPassRequest;
import com.doubledimple.ociserver.pojo.request.UpdateCustomNameRequest;
import com.doubledimple.ociserver.pojo.request.UpdatePasswordPolicyRequest;
import com.doubledimple.ociserver.pojo.response.PasswordPolicyDetail;
import com.doubledimple.ociserver.pojo.response.RegionSubscriptionResult;
import com.doubledimple.ociserver.service.VerifyService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.request.BootVolumeUpdateRequest;
import com.doubledimple.ociserver.pojo.request.CreateUserRequest;
import com.doubledimple.ociserver.pojo.request.DeleteBootVolumeReq;
import com.doubledimple.ociserver.pojo.request.SecurityRuleDTO;
import com.doubledimple.ociserver.pojo.request.TenantDTO;
import com.doubledimple.ociserver.pojo.request.TrafficAlertDTO;
import com.doubledimple.ociserver.pojo.response.AccountCheckRes;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.pojo.response.BootVolumeRes;
import com.doubledimple.ociserver.pojo.response.OciGroupResp;
import com.doubledimple.ociserver.pojo.response.TenantResp;
import com.doubledimple.ociserver.pojo.response.TrafficAlertResponse;
import com.doubledimple.ociserver.pojo.response.UserRes;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.doubledimple.ociserver.service.SecurityRuleService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.TrafficAlertService;
import com.doubledimple.ociserver.utils.PageUtils;
import com.doubledimple.ociserver.utils.oracle.MFAUtils;
import com.doubledimple.ociserver.utils.oracle.OciLimitsUtils;
import com.doubledimple.ociserver.utils.oracle.notify.NotificationUtils;
import com.doubledimple.ociserver.utils.oracle.region.OciRegionSubscriptionUtils;
import com.oracle.bmc.limits.model.ResourceAvailability;
import com.oracle.bmc.core.responses.UpdateBootVolumeResponse;
import com.oracle.bmc.identity.model.Region;
import com.oracle.bmc.identity.model.RegionSubscription;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import com.doubledimple.ociserver.config.context.UserContext;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.validation.Valid;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

/**
 * @author doubleDimple
 * @date 2024:10:07日 21:05
 */
@Controller
@RequestMapping("/tenants")
@Slf4j
public class TenantController extends BaseController{

    @Resource
    private TenantService tenantService;

    @Resource
    private BootInstanceService bootInstanceService;

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    SecurityRuleService securityRuleService;

    @Resource
    TrafficAlertService trafficAlertService;

    @Resource
    VerifyService verifyService;



    /**
    * 租户列表
    */
    @GetMapping("/list")
    public String listUsers(@RequestParam(defaultValue = "10") int size,
                            @RequestParam(defaultValue = "0") int page,
                            @RequestParam(required = false) String keyword,
                            @RequestParam(required = false) Integer cloudType,
                            HttpServletRequest request,
                            Model model) {

        boolean mobileRequest = isMobileRequest(request);
        if (null == cloudType) cloudType = 1;
        if (mobileRequest && size == 10) {
            size = 20;
        }
        int adjustedPage = Math.max(0, page);

        Page<Tenant> userPage;

        try {
            if (keyword != null && !keyword.trim().isEmpty()) {
                userPage = tenantService.searchTenants(keyword, cloudType, adjustedPage, size);
                model.addAttribute("keyword", keyword);
            } else {
                userPage = tenantService.getAllTenants(cloudType, adjustedPage, size);
            }

            log.debug("获取租户列表JSON成功,结果是:{}", JSON.toJSONString(userPage.getContent()));
            model.addAttribute("tenants", userPage.getContent());
            model.addAttribute("cloudType", cloudType);
            model.addAttribute("currentPage", userPage.getNumber()); // Spring的page从0开始
            model.addAttribute("totalPages", userPage.getTotalPages());
            model.addAttribute("totalElements", userPage.getTotalElements());
            model.addAttribute("size", size);
            model.addAttribute("keyword", keyword);

            // 分页计算
            model.addAttribute("hasPrevious", userPage.hasPrevious());
            model.addAttribute("hasNext", userPage.hasNext());
            model.addAttribute("isFirst", userPage.isFirst());
            model.addAttribute("isLast", userPage.isLast());

            // 页码范围计算（用于PC端分页导航）
            int startPage = Math.max(0, userPage.getNumber() - 2);
            int endPage = Math.min(userPage.getTotalPages() - 1, userPage.getNumber() + 2);
            model.addAttribute("startPage", startPage);
            model.addAttribute("endPage", endPage);

            // 用于移动端的分页信息
            if (mobileRequest) {
                Map<String, Object> paginationInfo = new HashMap<>();
                paginationInfo.put("currentPage", userPage.getNumber());
                paginationInfo.put("totalPages", userPage.getTotalPages());
                paginationInfo.put("totalElements", userPage.getTotalElements());
                paginationInfo.put("size", size);
                paginationInfo.put("hasContent", userPage.hasContent());
                paginationInfo.put("numberOfElements", userPage.getNumberOfElements());
                model.addAttribute("paginationInfo", paginationInfo);
            }

            // 设置第一个租户ID（如果存在）
            if (userPage.getContent().size() > 0) {
                model.addAttribute("tenantId", String.valueOf(userPage.getContent().get(0).getId()));
            }

        } catch (Exception e) {
            log.error("获取租户列表失败", e);
            model.addAttribute("tenants", Collections.emptyList());
            model.addAttribute("currentPage", 0);
            model.addAttribute("totalPages", 0);
            model.addAttribute("totalElements", 0);
            model.addAttribute("size", size);
            model.addAttribute("error", "加载数据失败，请稍后重试");
        }
        model.addAttribute("activePage", "api-management");
        return "tenant_list";

    }

    /**
     * 租户列表 JSON（AJAX分页）
     */
    @GetMapping("/list/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> listJson(
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "1") Integer cloudType,
            @RequestParam(required = false) Integer emailEnable) {
        Page<Tenant> userPage;
        try {
            if (emailEnable != null) {
                userPage = tenantService.getTenantsByEmailEnable(cloudType, emailEnable, keyword, page, size);
            } else if (keyword != null && !keyword.trim().isEmpty()) {
                userPage = tenantService.searchTenants(keyword, cloudType, page, size);
            } else {
                userPage = tenantService.getAllTenants(cloudType, page, size);
            }
        } catch (Exception e) {
            log.error("获取租户列表JSON失败", e);
            userPage = org.springframework.data.domain.Page.empty();
        }
        Map<String, Object> result = new HashMap<>();
        result.put("content", userPage.getContent());
        result.put("currentPage", page);
        result.put("totalPages", userPage.getTotalPages());
        result.put("totalElements", userPage.getTotalElements());
        result.put("size", size);
        return ResponseEntity.ok(result);
    }

    /**
     * 区域列表
     */
    @GetMapping("/regionList")
    public String regionList(@RequestParam(defaultValue = "25") long tenantId,
                            Model model,HttpServletRequest request) {
        List<Tenant> tenants = tenantService.regionList(tenantId);
        model.addAttribute("tenants", tenants);
        model.addAttribute("activePage", "api-management");
        if (tenants.size() > 0){
            model.addAttribute("tenantId", String.valueOf(tenantId));
        }
        model.addAttribute("activePage", "api-management");
        return "tenant_region_list";
    }

    /**
     * 区域订阅
     */
    @GetMapping("/regionSubList")
    public String regionSubList(@RequestParam(defaultValue = "25") long tenantId,
                                Model model, HttpServletRequest request) {
        Tenant tenant = tenantService.getById(tenantId);
        // 不再这里调用耗时的 regionSub 方法
        model.addAttribute("tenantId", String.valueOf(tenantId));
        model.addAttribute("tenant", tenant);
        model.addAttribute("activePage", "api-management");
        return "region_sub";
    }

    @GetMapping("/subscribed-regions-data")
    @ResponseBody
    public List<Map<String, Object>> getSubscribedData(@RequestParam long tenantId) {
        List<RegionSubscription> originalList = tenantService.regionSub(tenantId);

        List<Map<String, Object>> result = new ArrayList<>();
        for (RegionSubscription sub : originalList) {
            Map<String, Object> map = new HashMap<>();
            map.put("regionKey", sub.getRegionKey());
            map.put("regionName", sub.getRegionName());
            map.put("status", new HashMap<String, String>() {{
                put("value", sub.getStatus().getValue());
            }});
            map.put("isHomeRegion", sub.getIsHomeRegion());
            result.add(map);
        }
        return result;
    }

    /**
     * 获取区域摘要信息
     */
    @GetMapping("/region-summary")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getRegionSummary(@RequestParam long tenantId) {
        Map<String, Object> summary = new HashMap<>();
        Map<String, Object> error = new HashMap<>();
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                summary.put("error", "租户不存在");
                return ResponseEntity.badRequest().body(summary);
            }

            // 获取所有可用区域
            List<Region> allRegions = OciRegionSubscriptionUtils.getAllAvailableRegions(tenant);

            // 获取已订阅区域
            List<RegionSubscription> subscribedRegions = OciRegionSubscriptionUtils.getSubscribedRegions(tenant);

            // 获取未订阅区域
            List<Region> unsubscribedRegions = OciRegionSubscriptionUtils.getUnsubscribedRegions(tenant);

            summary.put("totalRegions", allRegions.size());
            summary.put("subscribedRegions", subscribedRegions.size());
            summary.put("unsubscribedRegions", unsubscribedRegions.size());

            return ResponseEntity.ok(summary);
        } catch (Exception e) {
            log.error("获取区域摘要信息失败", e);
            error.put("error", "获取区域摘要信息失败");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(error);
        }
    }

    /**
     * 获取未订阅区域列表
     */
    @GetMapping("/unsubscribed-regions")
    @ResponseBody
    public ResponseEntity<List<Map<String, Object>>> getUnsubscribedRegions(@RequestParam long tenantId) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                return ResponseEntity.badRequest().body(Collections.emptyList());
            }

            List<Region> unsubscribedRegions = OciRegionSubscriptionUtils.getUnsubscribedRegions(tenant);

            List<Map<String, Object>> result = unsubscribedRegions.stream()
                    .map(region -> {
                        Map<String, Object> regionMap = new HashMap<>();
                        regionMap.put("key", region.getKey());
                        regionMap.put("name", region.getName());
                        regionMap.put("cnName", RegionEnum.getNameCh(region.getName()));
                        return regionMap;
                    })
                    .collect(Collectors.toList());

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("获取未订阅区域列表失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Collections.emptyList());
        }
    }

    /**
     * 订阅指定区域
     */
    @PostMapping("/subscribe-regions")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> subscribeToRegions(@RequestBody Map<String, Object> request) {
        HashMap<String, Object> error = new HashMap<>();
        try {
            Long tenantId = Long.valueOf(request.get("tenantId").toString());
            @SuppressWarnings("unchecked")
            List<String> regionKeys = (List<String>) request.get("regionKeys");

            if (regionKeys == null || regionKeys.isEmpty()) {
                error.put("error", "未指定要订阅的区域");
                return ResponseEntity.badRequest().body(error);
            }

            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                error.put("error", "租户不存在");
                return ResponseEntity.badRequest().body(error);
            }

            List<Map<String, Object>> details = new ArrayList<>();
            boolean allSuccess = true;

            for (String regionKey : regionKeys) {
                try {
                    RegionSubscriptionResult result = OciRegionSubscriptionUtils.subscribeToRegion(tenant, regionKey);

                    Map<String, Object> detail = new HashMap<>();
                    detail.put("regionKey", regionKey);
                    detail.put("success", result.isSuccess());
                    detail.put("message", result.getMessage());

                    details.add(detail);

                    if (!result.isSuccess()) {
                        allSuccess = false;
                    }

                    log.info("区域 {} 订阅结果: {}", regionKey, result.isSuccess() ? "成功" : "失败");

                } catch (Exception e) {
                    Map<String, Object> detail = new HashMap<>();
                    detail.put("regionKey", regionKey);
                    detail.put("success", false);
                    detail.put("message", "订阅失败: " + e.getMessage());

                    details.add(detail);
                    allSuccess = false;

                    log.error("区域 {} 订阅异常", regionKey, e);
                }
            }

            Map<String, Object> response = new HashMap<>();
            response.put("success", allSuccess);
            response.put("message", allSuccess ? "所有区域订阅成功" : "部分区域订阅失败");
            response.put("details", details);

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("批量订阅区域失败", e);
            error.put("error", "订阅失败");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(error);
        }
    }

    /**
     * 检查区域订阅状态
     */
    @GetMapping("/check-subscription-status")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> checkSubscriptionStatus(
            @RequestParam long tenantId,
            @RequestParam String regionKey) {

        HashMap<String, Object> error = new HashMap<>();
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                error.put("error", "租户不存在");
                return ResponseEntity.badRequest().body(error);
            }

            String status = OciRegionSubscriptionUtils.getRegionSubscriptionStatus(tenant, regionKey);

            Map<String, Object> response = new HashMap<>();
            if (status != null) {
                response.put("regionKey", regionKey);
                response.put("status", status);
                response.put("subscribed", true);
            } else {
                response.put("regionKey", regionKey);
                response.put("status", "NOT_SUBSCRIBED");
                response.put("subscribed", false);
            }

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("检查区域订阅状态失败", e);
            error.put("error", "检查状态失败");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(error);
        }
    }

    /**
     * 获取所有租户列表
     */
    @GetMapping("/listAll")
    public ResponseEntity<List<TenantDTO>> getTenantsList() {
        return ResponseEntity.ok(tenantService.getAllTenantsForDropdown());
    }

    @GetMapping("/addSpeed")
    public String addSpeedPage(Model model) {
        model.addAttribute("tenant", new Tenant());
        model.addAttribute("activePage", "api-management");
        return "tenant_speed_add";
    }

    /**
    * oci 添加机器页
    */
    @GetMapping("/bootPage")
    public String addBootPage(Model model,@RequestParam("tenantId") Long id,HttpServletRequest request) {
        model.addAttribute("tenantId", id);
        model.addAttribute("activePage", "api-management");
        return "add_boot";

    }

    /**
     * gcp 添加机器页
     */
    @GetMapping("/gcpBootPage")
    public String addGcpBootPage(Model model,@RequestParam("tenantId") Long id,HttpServletRequest request) {
        model.addAttribute("tenantId", id);
        model.addAttribute("activePage", "api-management");

        return "gcp_add_boot";

    }


    /**
    * @Description: 抢机配置
    * @Param: [com.doubledimple.dao.entity.BootInstance, org.springframework.web.servlet.mvc.support.RedirectAttributes, org.springframework.ui.Model, javax.servlet.http.HttpServletRequest]
    * @return: java.lang.String
    * @Author: doubleDimple
    * @Date: 10/29/25 9:08 AM
    */
    @PostMapping("/boot/save")
    @ResponseBody
    public ApiResponse saveBootInstance(@ModelAttribute BootInstance bootInstance) {
        try {
            bootInstanceService.saveBootInstance(bootInstance);
        } catch (Exception e) {
            return OciExceptionFactory.buildException(e);
        }
        return ApiResponse.success("实例创建成功");
    }

    //获取租户下的系统镜像
    @PostMapping(value = "/querySystemImages")
    @ResponseBody
    public ApiResponse querySystemImages(@RequestBody @Valid ImageInfoReq imageInfoReq) {
        return ApiResponse.success(bootInstanceService.querySystemImage(imageInfoReq));
    }




    /**
    * 保存api信息
    */
    @PostMapping(path = "/save", consumes = "multipart/form-data")
    @ResponseBody
    public ApiResponse saveApi(Tenant tenant, @RequestParam("keyFileStr") MultipartFile keyFile) {
        try {
            tenantService.saveTenant(tenant, keyFile);
            return ApiResponse.success();
        } catch (IOException e) {
            log.error("保存租户信息失败", e);
            return ApiResponse.error("保存失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("保存租户信息失败", e);
            return ApiResponse.error("网络异常，请稍后重试");
        }
    }


    /**
     * 删除api
     * @param tenantId
     * @return
     */
    @GetMapping(path = "/deleteApi")
    public ResponseEntity<Map<String, Object>> deleteApiV2(@RequestParam("tenantId") String tenantId) {
        Map<String, Object> result = new HashMap<>();

        try {
            tenantService.deleteApi(Long.valueOf(tenantId), Boolean.TRUE);
            result.put("success", true);
            result.put("message", "删除成功");
            log.debug("成功删除租户API，tenantId: {}", tenantId);
            return ResponseEntity.ok(result);
        } catch (NumberFormatException e) {
            result.put("success", false);
            result.put("message", "租户ID格式错误");
            log.warn("删除失败，租户ID格式错误: {}", e.getMessage());
            return ResponseEntity.badRequest().body(result);
        } catch (Exception e) {
            result.put("success", false);
            result.put("message", "删除失败，请稍后重试");
            log.error("删除租户API失败，tenantId: {}, 错误: {}", tenantId, e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
        }
    }

    /**
     * 更新租户的注册信息
     * @param tenantId
     * @return
     */
    @GetMapping(path = "/updateAccountDetail")
    public String updateAccountDetail(@RequestParam("tenantId") String tenantId,Model model) {
        try {
            tenantService.updateTenancyDetail(tenantId);
            //tenantService.updateAccountDetail(Long.valueOf(tenantId));
        } catch (Exception e) {
            log.warn("更新失败,原因为:{}",e.getMessage());
        }
        model.addAttribute("activePage", "api-management");
        return "redirect:/tenants/list";
    }

    //使用SSE实现更新租户的信息以及资源信息
    @GetMapping("/updateTenant")
    public SseEmitter updateTenant(@RequestParam("tenantId") String tenantId,
                                   HttpServletRequest request,
                                   HttpServletResponse response) {
        SseEmitter emitter = new SseEmitter(600000L);
        emitter.onCompletion(() -> log.info("SSE 连接已完成, tenantId: {}", tenantId));
        emitter.onTimeout(() -> {
            log.warn("SSE 连接超时, tenantId: {}", tenantId);
            emitter.complete();
        });
        emitter.onError((e) -> log.error("SSE 连接出错, tenantId: {}", tenantId, e));
        tenantService.updateTenantWithSSE(tenantId, emitter);
        return emitter;
    }

    @GetMapping("/bootList")
    public String bootList(@RequestParam("tenantId") String tenantId,
                            Model model,
                           HttpServletRequest request,
                           @RequestParam(value = "mobile",required = false) Boolean  mobile) {
        BootInstanceQuery query = new BootInstanceQuery();
        query.setTenantId(Long.valueOf(tenantId));
        Pageable pageable = PageRequest.of(0, 1000);
        Page<BootInstanceRes> bootPage = bootInstanceService.findBootInstances(query, pageable);
        model.addAttribute("bootInstances", bootPage.getContent());
        model.addAttribute("currentPage", 0);
        model.addAttribute("totalPages", bootPage.getTotalPages());
        model.addAttribute("activePage", "api-fullBootList");
        if (isMobileRequest( request)){
            return "mobile/full_machine_list";
        }else{
            return "full_machine_list";
        }

    }


    @PostMapping("test-instances")
    public void queryInstances(){
        //oracleInstanceService.queryInstanceByApis();
    }


    @GetMapping("/syncOci")
    @ResponseBody
    public ResponseEntity<String> syncOci(@RequestParam("tenantId") String tenantId) {
        try {
            tenantService.syncOci(Long.valueOf(tenantId));
            return ResponseEntity.ok("{\"status\": \"success\"}");
        } catch (Exception e) {
            log.error("同步出现错误,原因为:{}",e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("{\"status\": \"error\", \"message\": \"" + e.getMessage() + "\"}");
        }
    }

    @GetMapping("/checkStatus")
    public ResponseEntity<?> checkAccountStatus(@RequestParam Long tenantId) {
        return oracleInstanceService.checkAccountStatus(tenantId);
    }

    @GetMapping("/security-rules")
    public ResponseEntity<?> getSecurityRules(@RequestParam String tenantId,
                                              @RequestParam String type) {
        try {
            List<SecurityRuleDTO> rules = securityRuleService.getSecurityRules(tenantId, type);
            return ResponseEntity.ok(rules);
        } catch (Exception e) {
            log.error("Failed to get security rules", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Failed to get security rules: " + e.getMessage());
        }
    }

    /**
    * 添加规则
    */
    @PostMapping("/security-rules")
    public ResponseEntity<?> addSecurityRule(@RequestBody SecurityRuleDTO ruleDTO) {
        try {
            SecurityRuleDTO savedRule = securityRuleService.addSecurityRule(ruleDTO);
            return ResponseEntity.ok(savedRule);
        } catch (Exception e) {
            log.error("Failed to add security rule", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Failed to add security rule: " + e.getMessage());
        }
    }

    /**
    * @Description: 删除规则
    * @Param: [java.lang.String]
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author: doubleDimple
    * @Date: 9/29/25 5:13 AM
    */
    @DeleteMapping("/security-rules/{id}")
    public ResponseEntity<?> deleteSecurityRule(@PathVariable String id) {
        try {
            securityRuleService.deleteSecurityRule(id);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Failed to delete security rule", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Failed to delete security rule: " + e.getMessage());
        }
    }


    /**
    * @Description: createOciUser
    * @Param: [com.doubledimple.ociserver.request.UpdateVolumeDefRequest]
    * @return: org.springframework.http.ResponseEntity<com.doubledimple.ociserver.response.ApiResponse>
    * @Author: doubleDimple
    * @Date: 12/14/24 4:21 PM
    */
    @PostMapping("/oracle-users")
    public ResponseEntity<Map<String, String>> createOciUser(@RequestBody CreateUserRequest request) {
        try {
            String password = tenantService.createUser(request.getTenantId(), request.getUsername(), request.getEmail(),request.getGroupId());
            Map<String, String> response = new HashMap<>();
            response.put("username", request.getUsername());
            response.put("email", request.getEmail());
            response.put("password", password); // 返回生成的密码
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            // 打印错误日志并返回错误状态
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 更新用户密码策略
     */
    @PostMapping("/oracle-users/password-policy")
    public ResponseEntity<Map<String, Object>> updatePasswordPolicy(@RequestBody UpdatePasswordPolicyRequest request) {
        try {
            Map<String, Object> response = new HashMap<>();
            Boolean aBoolean = tenantService.updateUserPasswordPolicy(request.getTenantId(),
                    request.isEnablePasswordExpiry(), request.getExpiryDays());
            if (!aBoolean){
                response.put("success", false);
                response.put("message", "error");
            }else{
                response.put("success", true);
                response.put("message", "success");
            }
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            e.printStackTrace();
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", "error: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }

    /**
     * 重置控制台登录密码
     */
    @PostMapping("/oracle-users/resetPassword")
    @ResponseBody
    public ApiResponse resetPassword(@RequestBody @Valid ResetOciPassRequest request) {
        return tenantService.resetPassword(request);
    }

    /**
     * 删除一个 用户
     */
    @PostMapping("/oracle-users/deleteUser")
    @ResponseBody
    public ApiResponse deleteUser(@RequestBody @Valid DeleteOciUserRequest request) {
        return tenantService.deleteUser(request);
    }

    /**
     * 获取当前租户的密码策略
     */
    @PostMapping("/oracle-users/getPasspolicy")
    @ResponseBody
    public ApiResponse getPasspolicy(@RequestBody UpdatePasswordPolicyRequest request) {
        try {
            List<PasswordPolicyDetail> policyDetailList = tenantService.getPasspolicy(request.getTenantId());
            return ApiResponse.success(policyDetailList);
        } catch (Exception e) {
            log.warn("获取密码策略失败: " + e.getMessage());
            return ApiResponse.error("获取密码策略失败");
        }
    }


    /**
     * 查询用户组
     */
    @PostMapping("/groups")
    public ResponseEntity<List<OciGroupResp>> groups(@RequestBody CreateUserRequest request) {
        try {
            List<OciGroupResp>  response =  tenantService.findGroups(request.getTenantId());
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 获取指定租户的用户列表
     *
     * @param tenantId 租户 ID
     * @return 用户列表
     */
    @GetMapping("/oracle-users")
    public ResponseEntity<List<UserRes>> getUsers(@RequestParam String tenantId) {
        try {
            List<UserRes> users = tenantService.listUsers(tenantId).stream()
                    .map(user -> new UserRes
                            (
                                    user.getId(),
                                    user.getName(),
                                    user.getLifecycleState().name(),
                                    user.getName(),
                                    user.getEmail(),
                                    user.getLastSuccessfulLoginTime(),
                                    user.getTimeCreated(),
                                    extractDomain(user.getName())
                            ))
                    .collect(Collectors.toList());
            return ResponseEntity.ok(users);
        } catch (Exception e) {
            // 打印错误日志并返回失败信息
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Collections.emptyList());
        }
    }

    @GetMapping("/oracle-users-page")
    public ResponseEntity<List<UserRes>> getPageUsers(@RequestParam(defaultValue = "10") int size, // 默认改为20
                                                  @RequestParam(defaultValue = "0") int page,
                                                  @RequestParam String tenantId,
                                                      Model model) {
        try {
            List<UserRes> users = tenantService.getPageUsers(tenantId).stream()
                    .map(user -> new UserRes
                            (
                                    user.getId(),
                                    user.getName(),
                                    user.getLifecycleState().name(),
                                    user.getName(),
                                    user.getEmail(),
                                    user.getLastSuccessfulLoginTime(),
                                    user.getTimeCreated(),
                                    extractDomain(user.getName())
                            ))
                    .collect(Collectors.toList());
            Page<UserRes> emptyPage = PageUtils.createEmptyPage(page, size);
            return ResponseEntity.ok(users);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Collections.emptyList());
        }
    }

    private String extractDomain(String userName) {
        if (userName.contains("/")) {
            return userName.substring(0, userName.indexOf("/"));
        } else {
            return "Default";
        }
    }


    /**
     * 导出租户数据（增加验证逻辑）
     */
    @GetMapping("/export")
    public ResponseEntity<?> exportData(HttpServletRequest request) {
        // 1. 从自定义 Header 获取验证码
        String code = request.getHeader("X-Verify-Code");
        String username = UserContext.getUsername();

        try {
            // 2. 校验验证码：如果校验失败会抛出 IllegalStateException
            verifyService.checkCodeForExport(username, code);

            // 3. 校验通过，执行原有的导出逻辑
            return tenantService.exportData();
        } catch (IllegalStateException e) {
            // 4. 验证码错误或过期，返回 403 状态码
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(e.getMessage());
        }
    }

    /**
     * 导出某个租户数据（增加验证逻辑）
     */
    @GetMapping("/exportByTenant")
    public ResponseEntity<?> exportByTenant(@RequestParam String id, HttpServletRequest request) {
        String code = request.getHeader("X-Verify-Code");
        String username = UserContext.getUsername();

        try {
            verifyService.checkCodeForExport(username, code);
            return tenantService.exportData(Long.valueOf(id));
        } catch (IllegalStateException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(e.getMessage());
        }
    }

    @PostMapping("/verify/sendExportCode")
    @ResponseBody
    public ResponseEntity<?> sendExportCode(HttpServletRequest request) {
        String username = UserContext.getUsername();
        try {
            verifyService.sendVerifyCodeForExport(username, request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(e.getMessage());
        }
    }

    /**
     * 导入 Tenant 和 BootInstance 数据
     */
    @PostMapping("/import")
    public ResponseEntity<?> importData(@RequestBody List<Map<String, Object>> requestData) {
        try {
            tenantService.importData(requestData);
            return ResponseEntity.ok("导入成功！");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("导入失败：" + e.getMessage());
        }
    }

    /**
    * @Description: 批量检查账号状态
    * @Param: []
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author doubleDimple
    * @Date: 12/22/24 9:06 AM
    */
    @GetMapping("/checkAccounts")
    public ResponseEntity<?> checkBatchAccounts() {
        try {
            AccountCheckRes result = tenantService.checkBatchAccounts();
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            e.printStackTrace();
            // 返回JSON格式的错误信息，而不是字符串
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("message", "检测失败：" + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    /**
     * 实时账号检测（SSE流式输出）
     */
    @GetMapping("/checkAccountsStream")
    public SseEmitter checkAccountsStream() {
        return tenantService.streamAccountCheckProgress();
    }


    // 查询所有引导卷
    @GetMapping("boot-volumes")
    public ResponseEntity<List<BootVolumeRes>> getAllBootVolumes(@RequestParam String tenantId) {
        try {
            List<BootVolumeRes> allBootVolumes = tenantService.getAllBootVolumes(tenantId);
            return ResponseEntity.ok(allBootVolumes);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
    * @Description: 修改引导卷性能参数和名称
    * @Param: [java.lang.String, com.doubledimple.ociserver.request.BootVolumeUpdateRequest]
    * @return: org.springframework.http.ResponseEntity<?>
    * @Author doubleDimple
    * @Date: 2/16/25 11:46 AM
    */
    @PutMapping("/update-volumes/{bootVolumeId}")
    public ResponseEntity<?> updateBootVolumeVpus(@PathVariable String bootVolumeId, @RequestBody BootVolumeUpdateRequest request) {
        try {
            UpdateBootVolumeResponse response = tenantService.updateBootVolumeVpus(bootVolumeId, request);
            if (response != null && response.getBootVolume() != null) {
                return ResponseEntity.ok(new HashMap<String, Object>() {{
                    put("success", true);
                    put("message", "引导卷更新成功");
                    put("data", response.getBootVolume().getId());
                }});
            } else {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(new HashMap<String, Object>() {{
                            put("success", false);
                            put("message", "引导卷更新失败");
                        }});
            }
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(new HashMap<String, Object>() {{
                        put("success", false);
                        put("message", "更新过程中发生错误: " + e.getMessage());
                    }});
        }
    }

    // 删除引导卷
    @DeleteMapping("/delete-volume/{volumeId}")
    public ResponseEntity<Map<String, Object>> deleteBootVolume(
            @PathVariable String volumeId,
            @RequestBody DeleteBootVolumeReq request) {
        Map<String, Object> response = new HashMap<>();
        try {
            response = tenantService.deleteBootVolume(request.getTenantId(), volumeId);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            response.put("success", false);
            response.put("message", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }

    /**
    * 批量开启所有协议
    */
    @PostMapping("/enableAll")
    public ResponseEntity<ApiResponse> batchAllSecurityRule() {
        ApiResponse apiResponse = null;
        try {
            apiResponse = securityRuleService.batchAllSecurityRule("all");
        } catch (Exception e) {
            log.error("批量开启icmp出现错误,原因为:{}",e.getMessage(),e);
            return ResponseEntity.ok().body(ApiResponse.error("批量开启所有协议出现异常,请稍后再试"));
        }
        return ResponseEntity.ok().body(apiResponse);
    }

    /**
     * 获取所有父级租户（返回DTO对象，id作为字符串）
     * @return 父级租户DTO列表
     */
    @GetMapping("/listParentTenants")
    @ResponseBody
    public List<TenantResp> listParentTenants() {
        List<Tenant> parentTenants = tenantService.getParentTenants();
        // 将Tenant实体转换为DTO对象
        return parentTenants.stream()
                .map(TenantResp::fromTenant)
                .collect(Collectors.toList());
    }

    /**
     * 获取指定租户下的所有区域（返回DTO对象，id作为字符串）
     * @param parentId 父级租户ID
     * @return 区域DTO列表
     */
    @GetMapping("/listRegions")
    @ResponseBody
    public List<TenantResp> listRegions(@RequestParam String parentId) {
        try {
            Long parentIdLong = Long.valueOf(parentId);
            List<Tenant> regions = tenantService.regionList(parentIdLong);
            // 将Tenant实体转换为DTO对象
            return regions.stream()
                    .map(TenantResp::fromTenant)
                    .collect(Collectors.toList());
        } catch (NumberFormatException e) {
            log.error("无效的租户ID: {}", parentId, e);
            return Collections.emptyList();
        }
    }

    @PostMapping("/resetAccountFactor")
    @ResponseBody
    public ApiResponse resetAccountFactor(@RequestParam String tenantId) {
        return tenantService.resetAccountFactor(Long.valueOf(tenantId));

    }

    /**
     * 获取流量预警配置
     */
    @GetMapping("/traffic-alert/{tenantId}")
    public ResponseEntity<?> getTrafficAlert(@PathVariable Long tenantId) {
        try {
            TrafficAlertDTO config = trafficAlertService.getTrafficAlert(tenantId);
            return ResponseEntity.ok(config);
        } catch (Exception e) {
            log.error("Failed to get traffic alert config", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(TrafficAlertResponse.error("获取配置失败: " + e.getMessage()));
        }
    }

    /**
     * 保存流量预警配置
     */
    @PostMapping("/traffic-alert")
    public ResponseEntity<?> saveTrafficAlert(@RequestBody TrafficAlertDTO dto) {
        try {
            if (dto == null || dto.getTenantId() == null) {
                return ResponseEntity.badRequest()
                        .body(TrafficAlertResponse.error("租户ID不能为空"));
            }
            // 阈值必须 > 0，避免误存为 0 导致下次加载时显示为空
            if (dto.getThreshold() == null || dto.getThreshold() <= 0) {
                return ResponseEntity.badRequest()
                        .body(TrafficAlertResponse.error("请设置有效的预警阈值"));
            }

            trafficAlertService.saveTrafficAlert(dto);
            return ResponseEntity.ok(TrafficAlertResponse.success(dto));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest()
                    .body(TrafficAlertResponse.error(e.getMessage()));
        } catch (Exception e) {
            log.error("Failed to save traffic alert config", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(TrafficAlertResponse.error("保存配置失败: " + e.getMessage()));
        }
    }

    /**
     * 更新租户的自定义名称
     * @param request 更新请求
     * @return 更新结果
     */
    @PostMapping("/updateCustomName")
    @ResponseBody
    public ResponseEntity<ApiResponse> updateCustomName(@RequestBody UpdateCustomNameRequest request) {
        try {
            // 参数验证
            if (request.getTenantId() == null) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("租户ID不能为空"));
            }

            // 验证租户是否存在
            Tenant tenant = tenantService.getById(Long.valueOf(request.getTenantId()));
            if (tenant == null) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("租户不存在"));
            }

            // 更新自定义名称
            boolean success = tenantService.updateCustomName(tenant, request.getDefName());

            if (success) {
                log.debug("成功更新租户自定义名称，tenantId: {}, defName: {}",
                        request.getTenantId(), request.getDefName());
                return ResponseEntity.ok(ApiResponse.success("更新成功"));
            } else {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("更新失败"));
            }

        } catch (Exception e) {
            log.error("更新租户自定义名称失败，tenantId: {}, 错误: {}",
                    request.getTenantId(), e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("更新失败，请稍后重试"));
        }
    }

    @PostMapping("/updateAccountCost")
    @ResponseBody
    public ResponseEntity<ApiResponse> updateAccountCost(@RequestBody UpdateCustomNameRequest request) {
        try {
            // 参数验证
            if (request.getTenantId() == null) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("租户ID不能为空"));
            }

            // 验证租户是否存在
            Tenant tenant = tenantService.getById(Long.valueOf(request.getTenantId()));
            if (tenant == null) {
                return ResponseEntity.badRequest()
                        .body(ApiResponse.error("租户不存在"));
            }

            // 更新自定义名称
            boolean success = tenantService.updateAccountCost(tenant, request.getAccountCost());

            if (success) {
                return ResponseEntity.ok(ApiResponse.success("更新成功"));
            } else {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(ApiResponse.error("更新失败"));
            }

        } catch (Exception e) {
            log.error("更新租户成本失败，tenantId: {}, 错误: {}",
                    request.getTenantId(), e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("更新失败，请稍后重试"));
        }
    }

    /**
     * 获取租户通知收件人
     */
    @PostMapping("/notification/recipients")
    public ResponseEntity<Map<String, Object>> getNotificationRecipients(@RequestBody Map<String, Object> request) {
        try {
            Tenant tenant = tenantService.getById(Long.parseLong(String.valueOf(request.get("tenantId"))));
            Map<String, Object> result = NotificationUtils.getCurrentRecipients(tenant);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("获取通知收件人失败", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "获取通知收件人失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    /**
     * 更新租户通知收件人
     */
    @PostMapping("/notification/update")
    public ResponseEntity<Map<String, Object>> updateNotificationRecipients(@RequestBody Map<String, Object> request) {
        try {
            String tenantId = String.valueOf(request.get("tenantId"));
            @SuppressWarnings("unchecked")
            List<String> emails = (List<String>) request.get("emails");

            if (emails == null || emails.isEmpty()) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "邮箱列表不能为空");
                return ResponseEntity.badRequest().body(errorResponse);
            }

            Tenant tenant = tenantService.getById(Long.parseLong(tenantId));
            Map<String, Object> result = NotificationUtils.updateNotificationRecipients(tenant, emails);
            return ResponseEntity.ok(result);

        } catch (Exception e) {
            log.error("更新通知收件人失败", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "更新通知收件人失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    /**
     * 启用或禁用邮箱MFA
     */
    @PostMapping("/mfa/email")
    @ResponseBody
    public Map<String, Object> toggleEmailMFA(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String tenantIdStr = (String) request.get("tenantId");
            Boolean enableEmail = (Boolean) request.get("enableEmail");

            if (tenantIdStr == null || enableEmail == null) {
                response.put("success", false);
                response.put("message", "参数不完整");
                return response;
            }
            Tenant tenant = tenantService.getById(Long.parseLong(tenantIdStr));
            Map<String, Object> result = MFAUtils.enableEmailMFA(tenant, enableEmail, null);

            return result;

        } catch (Exception e) {
            log.error("MFA设置失败", e);
            response.put("success", false);
            response.put("message", "MFA设置失败: " + e.getMessage());
            return response;
        }
    }

    /**
     * 获取MFA状态
     */
    @GetMapping("/mfa/status")
    @ResponseBody
    public Map<String, Object> getMfaStatus(@RequestParam String tenantId) {
        Map<String, Object> response = new HashMap<>();

        try {
            Tenant tenant = tenantService.getById(Long.parseLong(tenantId));
            Map<String, Object> mfaConfig = MFAUtils.getMFAConfiguration(tenant);
            if ((Boolean) mfaConfig.get("success")) {
                response.put("success", true);
                response.put("data", mfaConfig);
                response.put("message", "获取MFA状态成功");
            } else {
                response.put("success", false);
                response.put("message", mfaConfig.get("message"));
            }

        } catch (Exception e) {
            log.error("获取MFA状态失败", e);
            response.put("success", false);
            response.put("message", "获取MFA状态失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 启用邮件服务
     * @param request 包含tenantId的请求体
     * @return 启用结果
     */
    @PostMapping("/email/enable")
    @ResponseBody
    public ApiResponse enableEmailService(@RequestBody Map<String, Object> request) {
        return tenantService.enableEmailService(request);
    }

    /**
     * 获取租户邮件服务状态
     * @param tenantId 租户ID
     * @return 邮件服务状态
     */
    @GetMapping("/email/status")
    @ResponseBody
    public ApiResponse getEmailServiceStatus(@RequestParam Long tenantId) {
        return tenantService.getEmailServiceStatus(tenantId);
    }

    /**
     * 禁用邮件服务
     * @param request 包含tenantId的请求体
     * @return 禁用结果
     */
    @PostMapping("/email/disable")
    @ResponseBody
    public ApiResponse disableEmailService(@RequestBody Map<String, Object> request) {
        return tenantService.disableEmailService(request);
    }

    /**
     * 测试邮件发送
     * @param request 包含tenantId和testEmail的请求体
     * @return 测试结果
     */
    @PostMapping("/email/test")
    @ResponseBody
    public ApiResponse testEmailService(@RequestBody Map<String, Object> request) {
        return tenantService.testEmailService(request);
    }

    //查询租户的审计日志
    @PostMapping("/audit/log")
    @ResponseBody
    public ApiResponse getAuditLogs(@RequestBody AuditLogRequest auditLogRequest){
        return tenantService.queryAuditLogs(auditLogRequest);
    }

    //资产分析
    @GetMapping("/asset/analysis")
    @ResponseBody
    public ApiResponse assetAnalysis(@RequestParam(required = false) Integer cloudType){
        return tenantService.assetAnalysis(cloudType);
    }

    @PostMapping("/transfer")
    @ResponseBody
    public ApiResponse transferTenant(@RequestBody TenantTransferRequest request) {
        try {
            if (request.getTenantId() == null) {
                return ApiResponse.error("租户ID不能为空");
            }
            return tenantService.transferTenant(request);
        } catch (Exception e) {
            log.error("账号转移操作失败: {}", e.getMessage(), e);
            return ApiResponse.error("转移失败: " + e.getMessage());
        }
    }

    /**
     * 一键审计所有账号
     * 前端通过 SSE 接收流式分析报告
     */
    @GetMapping(value = "/analyze", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter startAudit() {
        SseEmitter emitter = new SseEmitter(300000L);
        tenantService.analyzeAllTenantsStream(emitter);
        return emitter;
    }

    /**
     * 查看账号配额（ARM/AMD 总配额与可用配额）
     * 若该租户含子区域，则逐区域返回；否则只返回本租户的配额
     */
    @GetMapping("/quota")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getTenantQuota(
            @RequestParam Long tenantId,
            @RequestParam(defaultValue = "compute") String serviceName,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int pageSize) {
        try {
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                Map<String, Object> err = new HashMap<>();
                err.put("error", "租户不存在");
                return ResponseEntity.badRequest().body(err);
            }
            Map<String, Object> pagedResult = OciLimitsUtils.getSingleServiceQuotasPaged(tenant, serviceName, page, pageSize);
            Map<String, Object> result = new HashMap<>();
            result.put("region", tenant.getRegion() != null ? tenant.getRegion() : "");
            result.put("regionEn", tenant.getRegionEn() != null ? tenant.getRegionEn() : "");
            result.put("service", serviceName);
            result.putAll(pagedResult);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("获取租户配额失败, tenantId: {}", tenantId, e);
            Map<String, Object> err = new HashMap<>();
            err.put("error", "获取配额失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(err);
        }
    }
}
