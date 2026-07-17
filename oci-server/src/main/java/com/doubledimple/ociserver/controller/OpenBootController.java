package com.doubledimple.ociserver.controller;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.ociserver.pojo.request.UpdateBootInstanceRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.BootInstanceRes;
import com.doubledimple.ociserver.pojo.response.DashboardStats;
import com.doubledimple.ociserver.service.BootInstanceService;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.config.task.StartBootInstanceTask;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.util.CollectionUtils;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ThreadPoolExecutor;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

/**
 * @author doubleDimple
 * @date 2024:10:11日 22:35
 */
@Controller
@CrossOrigin
@RequestMapping("/boot")
@Slf4j
public class OpenBootController  extends BaseController{


    @Resource
    private BootInstanceService bootInstanceService;

    @Resource
    private BootInstanceRepository bootInstanceRepository;

    @Resource
    private BootTotalInstanceService bootTotalInstanceService;

    @Resource
    private StartBootInstanceTask startBootInstanceTask;

    @Resource
    ThreadPoolExecutor threadPoolExecutor;

    @GetMapping("/fullBootList")
    public String bootList(@RequestParam(defaultValue = "20") int size,
                           @RequestParam(defaultValue = "0") int page,
                           @RequestParam(required = false) String tenantId,
                           HttpServletRequest request,
                           Model model) {
        // 参数校验
        if (size <= 0) size = 20;
        if (page < 0) page = 0;
        boolean mobileRequest = isMobileRequest(request);
        Page<BootInstanceRes> bootPage;
        if (StringUtils.isNotBlank(tenantId)) {
            bootPage = bootInstanceService.getBootsByTenantId(tenantId, page, size);
        } else {
            bootPage = bootInstanceService.getAllBoots(page, size);
        }

        log.debug("抢机实例记录是:{}", JSONUtil.toJsonStr(bootPage.getContent()));
        // 添加分页相关属性
        model.addAttribute("bootInstances", bootPage.getContent());
        model.addAttribute("currentPage", page);
        model.addAttribute("totalPages", bootPage.getTotalPages());
        model.addAttribute("totalElements", bootPage.getTotalElements());
        model.addAttribute("size", size);
        model.addAttribute("activePage", "api-fullBootList");

        // PC端：返回原有模板
        model.addAttribute("activePage", "api-fullBootList");
        return "full_machine_list";

    }

    /**
     * 开机任务列表 JSON（Mac / AJAX 分页，对齐 /tenants/list/json 形态）
     */
    @GetMapping("/fullBootList/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> bootListJson(
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) String tenantId) {
        if (size <= 0) size = 20;
        if (page < 0) page = 0;
        Page<BootInstanceRes> bootPage;
        try {
            if (StringUtils.isNotBlank(tenantId)) {
                bootPage = bootInstanceService.getBootsByTenantId(tenantId, page, size);
            } else {
                bootPage = bootInstanceService.getAllBoots(page, size);
            }
        } catch (Exception e) {
            log.error("获取开机列表JSON失败", e);
            bootPage = Page.empty(org.springframework.data.domain.PageRequest.of(page, size));
        }
        Map<String, Object> result = new HashMap<>();
        result.put("content", bootPage.getContent());
        result.put("currentPage", page);
        result.put("totalPages", bootPage.getTotalPages());
        result.put("totalElements", bootPage.getTotalElements());
        result.put("size", size);
        return ResponseEntity.ok(result);
    }

    /**
     * 执行开机操作
     */
    @RequestMapping("/startBoot")
    @ResponseBody
    public Map<String, Object> startBoot(@RequestParam("bootId") Long booId, Model model){
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
            BootInstance bootInstance = bootInstance1.get();
            List<BootInstance> byTenantIdAndArchitecture = bootInstanceRepository.findByTenantIdAndArchitectureOrderByCreatedAtDesc(bootInstance.getTenantId(), bootInstance.getArchitecture());
            if (!CollectionUtils.isEmpty(byTenantIdAndArchitecture)){
                for (BootInstance instance : byTenantIdAndArchitecture) {
                    if (instance.getStatus() == 0) {
                        bootInstanceService.startInstance(instance);
                    }
                }
            }
            result.put("success", true);
        } catch(Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }


    /**
     * 执行clone开机操作
     */
    @RequestMapping("/startCloneBoot")
    @ResponseBody
    public Map<String, Object> startCloneBoot(@RequestParam("bootId") Long booId, Model model){
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstancePre = bootInstanceRepository.findById(booId);
            if (bootInstancePre.isPresent()){
                BootInstance bootInstance = bootInstancePre.get();
                bootInstance.setId(null);
                bootInstance.setCurrentAttemptCount(0);
                bootInstance.setYesterdayAttemptCount(0);
                bootInstance.setAddCount(0);
                bootInstanceService.saveBootInstance(bootInstance);
            }
            result.put("success", true);
        } catch(Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }

    /**
     * 执行开机操作
     */
    @RequestMapping("/bootDetail")
    @ResponseBody
    public Map<String, Object> bootDetail(@RequestParam("bootId") Long booId, Model model){
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
            BootInstance bootInstance = bootInstance1.get();
            List<BootInstance> bootInstanceList = bootInstanceRepository.findByTenantIdAndArchitectureOrderByCreatedAtDesc(bootInstance.getTenantId(), bootInstance.getArchitecture());
            result.put("data", bootInstanceList);
            result.put("success", true);
        } catch(Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }

    /**
    * @Description: 手动开机请求
    * @Param: [java.lang.Long, org.springframework.ui.Model]
    * @return: java.util.Map<java.lang.String,java.lang.Object>
    * @Author doubleDimple
    * @Date: 1/4/25 8:29 AM
    */
    @RequestMapping("/manualBoot")
    @ResponseBody
    public Map<String, Object> manualBoot(@RequestParam("bootId") Long booId, Model model) {
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
            BootInstance bootInstance = bootInstance1.get();
            /*if (bootInstance.getStatus() != 2) {
                //暂时不修改了
                //bootInstanceService.startInstance(bootInstance);
                startBootInstanceTask.doStartInstance(bootInstance);
            }*/
            //不限制,手动点了就可以抢
            //手动开机一次开一台就可以,不需要同区域都开
            threadPoolExecutor.execute(() ->startBootInstanceTask.doStartInstance(bootInstance));
            result.put("success", true);
        } catch(Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }


    /**
     * 终止开机操作
     */
    @RequestMapping("/stopBoot")
    @ResponseBody
    public Map<String, Object> stopBoot(@RequestParam("bootId") Long booId, Model model) {
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
            BootInstance bootInstance = bootInstance1.get();
            List<BootInstance> byTenantIdAndArchitecture = bootInstanceRepository.findByTenantIdAndArchitectureOrderByCreatedAtDesc(bootInstance.getTenantId(), bootInstance.getArchitecture());
            if (!CollectionUtils.isEmpty(byTenantIdAndArchitecture)) {
                for (BootInstance instance : byTenantIdAndArchitecture) {
                    if (instance.getStatus() == 1) {
                        bootInstanceService.stopBoot(instance);
                    }
                }
            }
            result.put("success", true);
        } catch (Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        //model.addAttribute("tenantId",bootInstance.getTenantId());
        return result;
    }


    @PostMapping("/batchStart")
    @ResponseBody
    public Map<String, Object> batchStartBoot() {
        Map<String, Object> result = new HashMap<>();
        try {
            List<BootInstance> all = bootInstanceRepository.findAll();
            if (all.size() > 0){
                for (BootInstance bootInstance : all) {
                    if (bootInstance.getStatus() == 0) {
                        bootInstanceService.startInstance(bootInstance);
                    }
                }
            }
            result.put("success", true);
        } catch (Exception e) {
            log.error("批量开机失败", e);
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }

    @PostMapping("/batchStop")
    @ResponseBody
    public Map<String, Object> batchStopBoot() {
        Map<String, Object> result = new HashMap<>();
        try {
            List<BootInstance> all = bootInstanceRepository.findAll();
            if (all.size() > 0){
                for (BootInstance bootInstance : all) {
                    if (bootInstance.getStatus() == 1){
                        bootInstanceService.stopBoot(bootInstance);
                    }
                }
            }
            result.put("success", true);
        } catch (Exception e) {
            log.error("批量停止失败", e);
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }


    @PostMapping("/batchInitFailCount")
    @ResponseBody
    public Map<String, Object> batchInitFailCount() {
        Map<String, Object> result = new HashMap<>();
        try {
            bootInstanceService.batchInitFailCount();
            result.put("success", true);
        } catch (Exception e) {
            log.error("批量停止失败", e);
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }



    /**
     * 删除机器操作
     */
    @RequestMapping("/deleteBoot")
    @ResponseBody
    public Map<String, Object> deleteBoot(@RequestParam("bootId") Long booId,Model model){
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
            if (bootInstance1.isPresent()){
                BootInstance bootInstance = bootInstance1.get();
                //根据 tenantId和架构查询,同时删除其他的记录
                List<BootInstance> all = bootInstanceRepository.findByTenantIdAndArchitectureOrderByCreatedAtDesc(bootInstance.getTenantId(), bootInstance.getArchitecture());
                if (!CollectionUtils.isEmpty( all)){
                    for (BootInstance instance : all) {
                        bootInstanceService.deleteBoot(instance);
                    }
                }
                result.put("success", true);
            }
        } catch (Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        //model.addAttribute("tenantId",bootInstance.getTenantId());
        model.addAttribute("activePage", "api-fullBootList");
        return result;
    }

    /**
     * 详情删除开机
     */
    @RequestMapping("/deleteBootDetail")
    @ResponseBody
    public Map<String, Object> deleteBootDetail(@RequestParam("bootId") Long booId,Model model){
        Map<String, Object> result = new HashMap<>();
        try {
            Optional<BootInstance> bootInstance1 = bootInstanceRepository.findById(booId);
            if (bootInstance1.isPresent()){
                BootInstance bootInstance = bootInstance1.get();
                Long tenantId = bootInstance.getTenantId();
                String architecture = bootInstance.getArchitecture();
                bootInstanceService.deleteBoot(bootInstance);
                result.put("tenantId", tenantId.toString());
                result.put("architecture", architecture);
                result.put("success", true);
            }
        } catch (Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }

    @PostMapping("/bootDetailList")
    @ResponseBody
    public Map<String, Object> bootDetailList(@RequestBody Map<String, Object> param) {
        Map<String, Object> result = new HashMap<>();
        try {
            Long tenantId = Long.valueOf(param.get("tenantId").toString());
            String architecture = param.get("architecture").toString();

            List<BootInstance> list =
                    bootInstanceRepository.findByTenantIdAndArchitectureOrderByCreatedAtDesc(tenantId, architecture);

            if (list == null || list.isEmpty()) {
                // 没有记录了
                result.put("success", true);
                result.put("bootId", null);
            } else {
                BootInstance first = list.get(0);
                result.put("success", true);
                result.put("bootId", first.getId());
            }

        } catch (Exception e) {
            result.put("success", false);
            result.put("message", e.getMessage());
        }
        return result;
    }

    @PostMapping("/updateBoot")
    public ResponseEntity<ApiResponse> updateBootInstance(@RequestBody UpdateBootInstanceRequest request) {
        ApiResponse apiResponse = bootInstanceService.updateBootInstance(request);
        if (apiResponse.isSuccess()){
            return ResponseEntity.ok(apiResponse);
        }else {
            return ResponseEntity.badRequest().body(apiResponse);
        }

    }

    @GetMapping("/getOfflineCount")
    @ResponseBody
    public Map<String, Object> getOfflineCount() {
        Map<String, Object> result = new HashMap<>();
        long count = bootInstanceService.countByStatus(0);  // 未开机状态
        result.put("count", count);
        return result;
    }

    @GetMapping("/getStartingCount")
    @ResponseBody
    public Map<String, Object> getStartingCount() {
        Map<String, Object> result = new HashMap<>();
        long count = bootInstanceService.countByStatus(1);  // 开机中状态
        result.put("count", count);
        return result;
    }


    /**
     * 单个实例状态切换（启动/停止）
     */
    @PostMapping("/toggleStatus")
    @ResponseBody
    public ApiResponse toggleStatus(@RequestParam("id") Long id,
                                            @RequestParam("status") Integer status) {
        try {
            // 1. 获取实例对象
            Optional<BootInstance> optional = bootInstanceRepository.findById(id);
            if (!optional.isPresent()) {
                return ApiResponse.error("未找到该实例记录");
            }

            BootInstance instance = optional.get();

            // 2. 根据目标状态执行不同逻辑
            if (status == 1) {
                if (instance.getStatus() == 0){
                    bootInstanceService.startInstance(instance);
                }
                return ApiResponse.success("操作成功");
            } else {
                // 执行停止逻辑
                if (instance.getStatus() == 1){
                    bootInstanceService.stopBoot(instance);
                }
                return ApiResponse.success("操作成功");
            }
        } catch (Exception e) {
            log.error("切换状态异常 ID: {}, Status: {}", id, status, e);
            return ApiResponse.error("操作失败: " + e.getMessage());
        }
    }
}
