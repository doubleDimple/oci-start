package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.VpnProxyRecordService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;

/**
 * @version 1.0.0
 * @ClassName VpnProxyRecordController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-01 13:43
 */
@Controller
@RequestMapping("/vpnProxy")
@Slf4j
public class VpnProxyRecordController extends BaseController{

    @Resource
    private VpnProxyRecordService vpnProxyRecordService;


    @GetMapping("/page")
    public String vpnProxy(HttpServletRequest request,
                           Model model){
        // 默认第一页，方便首次加载
        model.addAttribute("pageNum", 1);
        model.addAttribute("pageSize", 10);
        model.addAttribute("totalPages", 0);
        model.addAttribute("totalElements", 0);
        model.addAttribute("activePage", "vpnProxy-management");
        return "vpn_proxy";
    }



    /**
     * 代理列表(支持分页)
     */
    @PostMapping("/pageList")
    @ResponseBody
    public ApiResponse pageList(@RequestBody VpnProxyRecordRequest vpnProxyRecordRequest) {
        try {
            Page<VpnProxyRecord> page = vpnProxyRecordService.listPage(vpnProxyRecordRequest);
            return ApiResponse.success(page);
        } catch (Exception e) {
            log.error("查询vpn代理配置列表失败", e);
            return ApiResponse.error("查询vpn代理配置列表失败: " + e.getMessage());
        }
    }


    /**
     * 代理列表(支持分页)
     */
    @PostMapping("/saveOrUpdate")
    @ResponseBody
    public ApiResponse saveOrUpdate(@RequestBody VpnProxyRecordRequest vpnProxyRecordRequest) {
        try {
            vpnProxyRecordService.saveOrUpdate(vpnProxyRecordRequest);
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("查询vpn代理配置列表失败", e);
            return ApiResponse.error("查询vpn代理配置列表失败: " + e.getMessage());
        }
    }

    //删除
    @PostMapping("/delete")
    @ResponseBody
    public ApiResponse delete(@RequestBody VpnProxyRecordRequest vpnProxyRecordRequest) {
        try {
            vpnProxyRecordService.delete(vpnProxyRecordRequest);
            return ApiResponse.success();
        } catch (Exception e) {
            log.error("查询vpn代理配置列表失败", e);
            return ApiResponse.error("查询vpn代理配置列表失败: " + e.getMessage());
        }
    }

    /**
     * 测试单条代理连通性，结果写入 availableStatus
     */
    @PostMapping("/testConnection")
    @ResponseBody
    public ApiResponse testConnection(@RequestBody VpnProxyRecordRequest request) {
        try {
            if (request == null || request.getId() == null) {
                return ApiResponse.error("代理 id 不能为空");
            }
            java.util.Map<String, Object> data = vpnProxyRecordService.testConnection(request.getId());
            boolean connected = Boolean.TRUE.equals(data.get("connected"));
            return ApiResponse.success(connected ? "代理连通" : "代理不通", data);
        } catch (Exception e) {
            log.error("测试代理连通失败", e);
            return ApiResponse.error("测试代理连通失败: " + e.getMessage());
        }
    }

    /**
     * 一键测试全部代理连通性，结果逐条落库
     */
    @PostMapping("/testAll")
    @ResponseBody
    public ApiResponse testAll() {
        try {
            java.util.Map<String, Object> data = vpnProxyRecordService.testAll();
            int total = data.get("total") instanceof Number ? ((Number) data.get("total")).intValue() : 0;
            int ok = data.get("successCount") instanceof Number ? ((Number) data.get("successCount")).intValue() : 0;
            int fail = data.get("failCount") instanceof Number ? ((Number) data.get("failCount")).intValue() : 0;
            String msg = "全部测试完成：共 " + total + " 条，通 " + ok + "，不通 " + fail;
            return ApiResponse.success(msg, data);
        } catch (Exception e) {
            log.error("一键测试代理失败", e);
            return ApiResponse.error("一键测试代理失败: " + e.getMessage());
        }
    }
}
