package com.doubledimple.ociserver.controller;

import com.doubledimple.ocicommon.enums.RegionCoordinatesEnum;
import com.doubledimple.ocicommon.param.OpenRegionNotify;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.OpenApiService;
import com.doubledimple.ociserver.service.TenantService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName ArmResourcesController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-18 09:13
 */
@Controller
@RequestMapping("/resource")
@Slf4j
public class ArmResourcesController  extends BaseController{

    @Resource
    private OpenApiService openApiService;

    @Resource
    private TenantService tenantService;

    /**
     * 获取ARM数据和区域映射 - 返回统一ApiResponse格式
     */
    @GetMapping("/arm-data")
    @ResponseBody
    public ApiResponse getArmData() {
        try {
            Map<String, Object> result = new HashMap<>();
            // 获取ARM记录数据
            OpenRegionNotify openRegionNotify = new OpenRegionNotify();
            openRegionNotify.setArchitectureType("ARM");
            List<OpenRegionNotify> armRecords = openApiService.armRecordsLocal(openRegionNotify);
            List<OpenRegionNotify> sortedArmRecords = armRecords.stream()
                    .sorted(Comparator.comparing(OpenRegionNotify::getLastNotifyTime,
                            Comparator.nullsLast(Comparator.reverseOrder())))
                    .filter(record -> record.getArchitectureType().equalsIgnoreCase("ARM"))
                    .collect(Collectors.toList());

            // 获取区域映射
            Map<String, String> regionMap = Arrays.stream(RegionCoordinatesEnum.values())
                    .collect(Collectors.toMap(
                            RegionCoordinatesEnum::getCode,
                            RegionCoordinatesEnum::getName
                    ));
            result.put("armRecords", sortedArmRecords);
            result.put("regionMap", regionMap);
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取ARM数据失败", e);
            return ApiResponse.error("获取ARM数据失败: " + e.getMessage());
        }
    }

    /**
     * 获取我的区域数据 - 返回统一ApiResponse格式
     */
    @GetMapping("/my-regions")
    @ResponseBody
    public ApiResponse getMyRegions() {
        try {
            Map<String, Object> result = new HashMap<>();
            List<OpenRegionNotify> selfHasRecords = tenantService.listDisTenants();
            result.put("hasRecords", selfHasRecords);
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取我的区域数据失败", e);
            return ApiResponse.error("获取我的区域数据失败: " + e.getMessage());
        }
    }

    /**
     * 原来的页面渲染方法保持不变（如果还需要的话）
     */
    @GetMapping("/list")
    public String listUsers(Model model) {
        model.addAttribute("activePage", "api-records");
        return "arm_records";
    }
}
