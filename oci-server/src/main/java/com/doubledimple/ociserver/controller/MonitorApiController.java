package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.monitor.MonitorAlert;
import com.doubledimple.ocicommon.param.monitor.MonitorReportDTO;
import com.doubledimple.ocimonitor.service.MonitorCoreService;
import com.doubledimple.ocimonitor.service.MonitorDeployService;
import com.doubledimple.ociserver.config.socker.MonitorWebSocketHandler;
import com.doubledimple.ociserver.service.AlertService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;

import java.util.List;

import static com.doubledimple.ocicommon.utils.IpUtils.getPublicIp2;

/**
 * @version 1.0.0
 * @ClassName MonitorApiController
 * @Description TODO
 * @Author renyx
 * @Date 2026-02-05 13:43
 */
@RestController
@RequestMapping("/api/monitor")
@Slf4j
public class MonitorApiController extends BaseController{

    @Resource
    private MonitorCoreService monitorCoreService;

    @Resource
    private MonitorDeployService monitorDeployService;

    @Resource
    private MonitorWebSocketHandler monitorWebSocketHandler;

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    AlertService alertService;

    /**
     * 接口 1: 脚本下载接口 todo 不需要验证登录
     * VPS 执行 curl 时会访问这里
     * URL: GET /api/monitor/download?token=xxxx
     */
    @GetMapping(value = "/download", produces = "text/plain;charset=UTF-8")
    public String downloadScript(@RequestParam String token) {
        return monitorCoreService.generateInstallScript(token, 5);
    }

    /**
    * @Description: receiveReport
    * @Param: [com.doubledimple.ocicommon.param.monitor.MonitorReportDTO]
    * @return: com.doubledimple.ocicommon.param.ApiResponse
    * @Author: renyx
    * @Date: 2/5/26 2:20 PM
    */
    @PostMapping("/report")
    public ApiResponse receiveReport(@RequestBody MonitorReportDTO reportDto) {
        monitorWebSocketHandler.broadcast(reportDto);
        alertService.sendAlertAsync(reportDto);
        return ApiResponse.success("ok");
    }

    /**
     * [管理端] 一键安装监控
     * 前端点击 "开启监控" 按钮时调用
     */
    @PostMapping("/install")
    public ApiResponse installAgent(@RequestParam String vpsId) {
        log.info("接收到安装请求, vpsId: {}", vpsId);
        try {
            return monitorDeployService.installAgent(vpsId);
        } catch (Exception e) {
            log.error("安装探针失败", e);
            return ApiResponse.error("安装失败: " + e.getMessage());
        }
    }

    /**
     * [管理端] 一键卸载监控
     * 前端点击 "关闭监控" 按钮时调用
     */
    @PostMapping("/uninstall")
    public ApiResponse uninstallAgent(@RequestParam String vpsId) {
        try {
            String result = monitorDeployService.uninstallAgent(vpsId);
            return ApiResponse.success(result);
        } catch (Exception e) {
            log.error("卸载探针失败", e);
            return ApiResponse.error("卸载失败: " + e.getMessage());
        }
    }
}
