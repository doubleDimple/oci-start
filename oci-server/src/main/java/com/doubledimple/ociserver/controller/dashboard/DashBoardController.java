package com.doubledimple.ociserver.controller.dashboard;

import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.response.DashboardStats;
import com.doubledimple.ociserver.pojo.response.SystemMetrics;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.service.monitor.SystemMonitorService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;

/**
 * @version 1.0.0
 * @ClassName DashBoardController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-25 22:34
 */
@Controller
@CrossOrigin
@Slf4j
public class DashBoardController extends BaseController {



    @Resource
    private SystemMonitorService monitorService;

    @Resource
    private BootTotalInstanceService bootTotalInstanceService;

    @RequestMapping("/boot/dashboard")
    public String dashboard(Model model){
        model.addAttribute("activePage", "api-dashboard");
        return "dashboard";
    }

    @GetMapping("/boot/dashboard-stats")
    @ResponseBody
    public ApiResponse getDashboardStats() {
        try {
            DashboardStats dashboardStats = bootTotalInstanceService.count();
            return ApiResponse.success(dashboardStats);
        } catch (Exception e) {
            return ApiResponse.error("获取仪表盘数据失败: " + e.getMessage());
        }
    }

    @GetMapping("/boot/stats")
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
