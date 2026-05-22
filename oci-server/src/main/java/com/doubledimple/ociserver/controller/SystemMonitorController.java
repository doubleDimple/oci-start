package com.doubledimple.ociserver.controller;

import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.monitor.SystemMonitorService;
import com.doubledimple.ociserver.pojo.response.SystemMetrics;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;

/**
 * @author doubleDimple
 * @date 2024:11:28日 22:42
 */
@RestController
@RequestMapping("/monitor")
@Slf4j
public class SystemMonitorController  extends BaseController{

    @Resource
    private SystemMonitorService monitorService;

    /**
    * @Description: 部署机系统原数据
    * @Param: []
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 12/21/25 8:27 AM
    */
    @GetMapping("/stats")
    @ResponseBody
    public ApiResponse getSystemStats() {
        try {
            SystemMetrics metrics = monitorService.collectMetrics();
            return ApiResponse.success(metrics);
        } catch (Exception e) {
            log.error("Failed to get system stats", e);
            return ApiResponse.error("数据获取异常,请稍后再试");
        }
    }
}

