package com.doubledimple.ociserver.controller;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.TrafficAlert;
import com.doubledimple.dao.repository.TrafficAlertRepository;
import com.doubledimple.ociserver.service.oracle.InstanceTrafficService;
import com.doubledimple.ociserver.pojo.request.TrafficQueryRequest;
import com.doubledimple.ociserver.pojo.request.TrafficTrendRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.InstanceTrafficVO;
import com.doubledimple.ociserver.config.task.InstanceTrafficTask;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 流量统计控制器
 */
@Controller
@RequestMapping("monitor")
@Slf4j
public class TrafficStatisticsController  extends BaseController{

    @Resource
    private InstanceTrafficService instanceTrafficService;

    @Resource
    private TrafficAlertRepository trafficAlertRepository;

    @GetMapping("/homePage")
    public String monitor(Model model, @RequestParam(required = false) String tenantId) {
        model.addAttribute("activePage", "api-management");
        if (tenantId != null && !tenantId.isEmpty()) {
            model.addAttribute("tenantId", tenantId);
        }
        return "oci_monitor";
    }

    /**
     * 获取所有实例流量数据
     * 可以根据租户ID筛选
     */
    @PostMapping("/api/instances/traffic")
    @ResponseBody
    public ResponseEntity<List<InstanceTrafficVO>> getAllInstanceTraffic(@RequestBody TrafficQueryRequest request) {
        // 如果未指定日期，默认为当天
        if (request.getStartDate() == null) {
            request.setStartDate(LocalDate.now());
        }
        if (request.getEndDate() == null) {
            request.setEndDate(LocalDate.now());
        }

        // 验证日期范围
        if (request.getStartDate().until(request.getEndDate(), ChronoUnit.DAYS) > 90) {
            throw new IllegalArgumentException("查询时间范围不能超过3个月");
        }
        final List<InstanceTrafficVO> allInstanceTraffic = instanceTrafficService.getAllInstanceTraffic(
                request.getTenantIds(),
                request.getStartDate(),
                request.getEndDate(),
                request.getPeriod()
        );
        return ResponseEntity.ok(allInstanceTraffic);
    }

    @PostMapping("/api/instances/traffic/trend")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getTrafficTrend(@RequestBody TrafficTrendRequest request) {
        // 如果未指定日期，默认为当天
        if (request.getStartDate() == null) {
            request.setStartDate(LocalDate.now());
        }
        if (request.getEndDate() == null) {
            request.setEndDate(LocalDate.now());
        }

        // 验证日期范围
        if (request.getStartDate().until(request.getEndDate(), ChronoUnit.DAYS) > 90) {
            throw new IllegalArgumentException("查询时间范围不能超过3个月");
        }

        return ResponseEntity.ok(instanceTrafficService.getTrafficTrend(
                request.getInstanceId(),
                request.getTenantIds(),
                request.getStartDate(),
                request.getEndDate()
        ));
    }

    //获取预警流量
    @GetMapping("/api/traffic/alert")
    @ResponseBody
    public ApiResponse getTrafficAlert(@RequestParam(required = false) String tenantId) {
        if (tenantId == null || tenantId.isEmpty()) {
            return ApiResponse.success();
        }
        Optional<TrafficAlert> alertOpt = trafficAlertRepository.findByTenantId(Long.valueOf(tenantId));
        if (alertOpt.isPresent()){
            return ApiResponse.success(alertOpt.get());
        }else {
            return ApiResponse.success();
        }
    }
}
