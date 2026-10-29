package com.doubledimple.ociserver.controller;

import com.doubledimple.ocicommon.enums.RegionCoordinatesEnum;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.TenantService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

/** Region metadata and account associations come from this installation only. */
@RestController
@RequestMapping("/resource")
@Slf4j
public class RegionResourcesController extends BaseController {

    @Resource
    private TenantService tenantService;

    @GetMapping("/my-regions")
    public ApiResponse getMyRegions() {
        try {
            Map<String, Object> result = new HashMap<>();
            result.put("hasRecords", tenantService.listOwnedOciRegions().stream()
                    .map(region -> Collections.singletonMap("region", region))
                    .collect(Collectors.toList()));
            result.put("regionMap", Arrays.stream(RegionCoordinatesEnum.values())
                    .collect(Collectors.toMap(RegionCoordinatesEnum::getCode, RegionCoordinatesEnum::getName)));
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("获取账号关联区域失败", e);
            return ApiResponse.error("获取账号关联区域失败，请稍后重试");
        }
    }
}
