package com.doubledimple.ociserver.controller.otherCloud;

import com.doubledimple.dao.entity.OtherBootInstance;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.gcp.GcpInstanceCreateDto;
import com.doubledimple.ociserver.service.otherCloud.OtherBootService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import javax.annotation.Resource;
import javax.validation.Valid;
import java.util.HashMap;
import java.util.Map;

/**
 * 其他云厂商开机控制器
 */
@Slf4j
@Controller
@RequestMapping("/other/instances")
@RequiredArgsConstructor
public class OtherBootInstanceController  extends BaseController {

    @Resource
    private OtherBootService otherBootService;

    /**
     * 创建GCP实例（支持自定义配置）
     */
    @PostMapping("/save")
    public String createInstance(@Valid @ModelAttribute GcpInstanceCreateDto createDto,
                                 BindingResult bindingResult,
                                 RedirectAttributes redirectAttributes) {

        if (bindingResult.hasErrors()) {
            redirectAttributes.addFlashAttribute("error", "参数验证失败：" +
                    bindingResult.getFieldError().getDefaultMessage());
            return "redirect:/other/instances/add?tenantId=" + createDto.getTenantId();
        }

        try {
            // 验证自定义机器配置
            if (Boolean.TRUE.equals(createDto.getIsCustomMachine())) {
                String customValidationError = validateCustomMachineConfig(createDto);
                if (customValidationError != null) {
                    redirectAttributes.addFlashAttribute("error", customValidationError);
                    return "redirect:/tenants/gcpBootPage?tenantId=" + createDto.getTenantId();
                }
            }

            log.info("开始创建GCP实例，租户ID: {}, 实例名称: {}, 数量: {}, 机器配置: {}",
                    createDto.getTenantId(), createDto.getInstanceName(), createDto.getInstanceCount(),
                    createDto.getMachineConfigDescription());

            // 创建实例
            String instanceName = createDto.getInstanceName();
            createDto.setInstanceName(instanceName + "-" + System.currentTimeMillis() + "-instance");
            otherBootService.createGcpInstances(createDto);

            String successMessage = String.format("成功提交创建 %d 个GCP实例的请求 - %s",
                    createDto.getInstanceCount(), createDto.getMachineConfigDescription());
            redirectAttributes.addFlashAttribute("success", successMessage);

        } catch (Exception e) {
            log.error("创建GCP实例失败", e);
            String errorMessage = "创建实例失败：" + e.getMessage();

            // 如果是自定义机器类型相关的错误，提供更详细的信息
            if (e.getMessage().contains("custom") || e.getMessage().contains("CPU") || e.getMessage().contains("内存")) {
                errorMessage += " (请检查自定义CPU和内存配置是否符合GCP规则)";
            }

            redirectAttributes.addFlashAttribute("error", errorMessage);
            return "redirect:/tenants/list";
        }

        return "redirect:/tenants/list";
    }

    /**
     * 验证自定义机器配置
     *
     * @param createDto 创建请求DTO
     * @return 验证错误信息，如果验证通过返回null
     */
    private String validateCustomMachineConfig(GcpInstanceCreateDto createDto) {
        if (!Boolean.TRUE.equals(createDto.getIsCustomMachine())) {
            return null; // 非自定义配置不需要验证
        }

        Integer cpuCount = createDto.getCustomCpuCount();
        Integer memoryMb = createDto.getCustomMemoryMb();

        // 检查必填字段
        if (cpuCount == null || memoryMb == null) {
            return "自定义配置下CPU数量和内存大小不能为空";
        }

        // 检查CPU范围
        if (cpuCount < 1 || cpuCount > 96) {
            return "CPU数量必须在1-96之间";
        }

        // 检查CPU规则：1或偶数
        if (cpuCount > 1 && cpuCount % 2 != 0) {
            return "CPU数量必须是1或偶数";
        }

        // 检查内存范围
        if (memoryMb < 1024 || memoryMb > 638976) { // 1GB - 624GB
            return "内存大小必须在1GB-624GB之间";
        }

        // 检查内存规则：每个vCPU对应0.9-6.5GB内存
        double memoryGb = memoryMb / 1024.0;
        double minMemory = Math.max(0.9 * cpuCount, 1.0);
        double maxMemory = 6.5 * cpuCount;

        if (memoryGb < minMemory || memoryGb > maxMemory) {
            return String.format("对于%d个CPU，内存大小必须在%.2fGB-%.2fGB之间",
                    cpuCount, minMemory, maxMemory);
        }

        // 检查内存是0.25GB(256MB)的倍数
        if (memoryMb % 256 != 0) {
            return "内存大小必须是256MB(0.25GB)的倍数";
        }

        // 验证机器类型名称格式
        String customMachineType = createDto.getActualMachineType();
        if (!customMachineType.matches("^custom-\\d+-\\d+$")) {
            return "自定义机器类型格式错误：" + customMachineType;
        }

        return null; // 验证通过
    }

    /**
     * 获取实例列表
     */
    @GetMapping("/list")
    public String listInstances(@RequestParam(defaultValue = "0") Long tenantId,
                                @RequestParam(defaultValue = "2") Integer cloudType,
                                @RequestParam(defaultValue = "0") int page,
                                @RequestParam(defaultValue = "20") int size,
                                Model model) {
        try {
            // 创建分页请求
            Pageable pageable = PageRequest.of(page, size);
            Page<OtherBootInstance> instancePage;
            // 获取分页数据
            if (tenantId == null || tenantId == 0L){
                instancePage = otherBootService.getInstancesByCloudType(cloudType, pageable);
            }else {
                instancePage = otherBootService.getInstancesByTenantAndCloudType(tenantId, cloudType, pageable);
            }

            model.addAttribute("tenantId", tenantId);
            model.addAttribute("cloudType", cloudType);
            model.addAttribute("instances", instancePage.getContent());
            model.addAttribute("currentPage", page);
            model.addAttribute("size", size);
            model.addAttribute("totalPages", instancePage.getTotalPages());
            model.addAttribute("totalElements", instancePage.getTotalElements());
            //api-ociBootList
            model.addAttribute("activePage", "api-ociBootList");

            return "other_instance_list";
        } catch (Exception e) {
            log.error("获取实例列表失败", e);
            model.addAttribute("error", "获取实例列表失败：" + e.getMessage());
            return "error";
        }
    }

    /**
     * 删除实例
     */
    @PostMapping("/{bootId}/delete")
    @ResponseBody
    public Map<String, Object> deleteInstance(@PathVariable String bootId,
                                              @RequestBody Map<String, Object> request) {
        Map<String, Object> result = new HashMap<>();
        try {
            otherBootService.deleteGcpInstance(bootId);
            result.put("success", true);
            result.put("message", "实例删除请求已提交");
        } catch (Exception e) {
            log.error("删除GCP实例失败", e);
            result.put("success", false);
            result.put("message", "删除实例失败：" + e.getMessage());
        }
        return result;
    }

    /**
     * 更新实例状态
     */
    @PostMapping("/{bootId}/refresh")
    public ResponseEntity<Map<String, Object>> refreshInstance(@PathVariable String bootId) {
        Map<String, Object> result = new HashMap<>();
        try {
            String s = otherBootService.refreshInstance(bootId);
            if (s.equals("SUCCESS")){
                result.put("success", true);
                result.put("message", "实例状态刷新成功");
                return ResponseEntity.ok(result);
            }else{
                if (s.equals("NOT_FOUND")){
                    result.put("success", false);
                    result.put("message", "刷新实例失败,实例可能已被删除");
                    return ResponseEntity.ok(result);
                }else{
                    result.put("success", false);
                    result.put("message", "刷新实例失败：");
                    return ResponseEntity.ok(result);
                }
            }
        } catch (Exception e) {
            log.error("refresh实例失败", e);
            result.put("success", false);
            result.put("message", "刷新实例失败：" + e.getMessage());
            return ResponseEntity.ok(result);
        }
    }

    /**
     * 切换实例ip
     */
    @PostMapping("/{bootId}/changeIp")
    public ResponseEntity<Map<String, Object>> changeIp(@PathVariable String bootId) {
        Map<String, Object> result = new HashMap<>();
        try {
            String s = otherBootService.changeIp(bootId);
            if (s.equals("SUCCESS")){
                result.put("success", true);
                result.put("message", "实例状态刷新成功");
                return ResponseEntity.ok(result);
            }else{
                if (s.equals("NOT_FOUND")){
                    result.put("success", false);
                    result.put("message", "切换IP失败,实例可能已被删除");
                    return ResponseEntity.ok(result);
                }else{
                    result.put("success", false);
                    result.put("message", "切换IP失败");
                    return ResponseEntity.ok(result);
                }
            }
        } catch (Exception e) {
            log.error("切换IP失败", e);
            result.put("success", false);
            result.put("message", "切换IP失败：" + e.getMessage());
            return ResponseEntity.ok(result);
        }
    }

    /**
     * 获取区域列表（API接口）- 返回前端写死的数据结构说明
     */
    @GetMapping("/api/regions")
    @ResponseBody
    public ResponseEntity<String> getRegions() {
        try {
            return ResponseEntity.ok("请使用前端写死的GCP_REGIONS数据");
        } catch (Exception e) {
            log.error("获取GCP区域列表失败", e);
            return ResponseEntity.status(500).body("获取区域列表失败：" + e.getMessage());
        }
    }

    /**
     * 获取机器类型列表（API接口）- 返回前端写死的数据结构说明
     */
    @GetMapping("/api/machine-types")
    @ResponseBody
    public ResponseEntity<String> getMachineTypes() {
        try {
            return ResponseEntity.ok("请使用前端写死的GCP_MACHINE_TYPES数据");
        } catch (Exception e) {
            log.error("获取GCP机器类型列表失败", e);
            return ResponseEntity.status(500).body("获取机器类型列表失败：" + e.getMessage());
        }
    }

    /**
     * 获取镜像列表（API接口）- 返回前端写死的数据结构说明
     */
    @GetMapping("/api/images")
    @ResponseBody
    public ResponseEntity<String> getImages() {
        try {
            return ResponseEntity.ok("请使用前端写死的GCP_IMAGES数据");
        } catch (Exception e) {
            log.error("获取GCP镜像列表失败", e);
            return ResponseEntity.status(500).body("获取镜像列表失败：" + e.getMessage());
        }
    }
}
