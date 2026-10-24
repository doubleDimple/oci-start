package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.VpnProxyRecordService;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.server.ResponseStatusException;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

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

    /**
     * 代理列表(支持分页)
     */
    @PostMapping("/pageList")
    @ResponseBody
    public ApiResponse pageList(@RequestBody VpnProxyRecordRequest vpnProxyRecordRequest,
                                @RequestParam(defaultValue = "false") boolean redacted,
                                HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        if (redacted) guardProxyAccess(httpRequest);
        try {
            Page<VpnProxyRecord> page = vpnProxyRecordService.listPage(vpnProxyRecordRequest);
            return ApiResponse.success(redacted ? page.map(this::safeProxy) : page);
        } catch (Exception e) {
            return ApiResponse.error("查询vpn代理配置列表失败");
        }
    }

    @PostMapping("/password")
    @ResponseBody
    public ApiResponse password(@RequestBody VpnProxyRecordRequest request,
                                HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        guardProxyAccess(httpRequest);
        try {
            String password = vpnProxyRecordService.getPassword(request.getId());
            Map<String, Object> data = new HashMap<>();
            data.put("id", String.valueOf(request.getId()));
            data.put("proxyPassword", password);
            return ApiResponse.success(data);
        } catch (Exception e) {
            return ApiResponse.error("读取代理密码失败");
        }
    }

    @PostMapping("/force")
    @ResponseBody
    public ApiResponse force(@RequestBody ForceRequest request, HttpServletRequest httpRequest) {
        guardProxyAccess(httpRequest);
        try {
            vpnProxyRecordService.updateForce(request.getId(), request.getForceProxy());
            return ApiResponse.success();
        } catch (Exception e) {
            return ApiResponse.error("修改强制代理状态未确认完成，请重新读取配置");
        }
    }

    @Data
    public static class ForceRequest {
        private Long id;
        private Integer forceProxy;
    }

    /**
     * 代理列表(支持分页)
     */
    @PostMapping("/saveOrUpdate")
    @ResponseBody
    public ApiResponse saveOrUpdate(@RequestBody VpnProxyRecordRequest vpnProxyRecordRequest, HttpServletRequest httpRequest) {
        guardProxyAccess(httpRequest);
        try {
            vpnProxyRecordService.saveOrUpdate(vpnProxyRecordRequest);
            return ApiResponse.success();
        } catch (Exception e) {
            return ApiResponse.error("保存vpn代理配置失败，请检查配置并重新读取确认");
        }
    }

    //删除
    @PostMapping("/delete")
    @ResponseBody
    public ApiResponse delete(@RequestBody VpnProxyRecordRequest vpnProxyRecordRequest, HttpServletRequest httpRequest) {
        guardProxyAccess(httpRequest);
        try {
            vpnProxyRecordService.delete(vpnProxyRecordRequest);
            return ApiResponse.success();
        } catch (Exception e) {
            return ApiResponse.error("删除vpn代理配置未确认完成，请重新读取配置");
        }
    }

    /**
     * 测试单条代理连通性，结果写入 availableStatus
     */
    @PostMapping("/testConnection")
    @ResponseBody
    public ApiResponse testConnection(@RequestBody VpnProxyRecordRequest request, HttpServletRequest httpRequest) {
        guardProxyAccess(httpRequest);
        try {
            if (request == null || request.getId() == null) {
                return ApiResponse.error("代理 id 不能为空");
            }
            java.util.Map<String, Object> data = vpnProxyRecordService.testConnection(request.getId());
            if (data.get("connected") == null) {
                return ApiResponse.success("代理配置已更改或删除，测试结果未写入", data);
            }
            boolean connected = Boolean.TRUE.equals(data.get("connected"));
            return ApiResponse.success(connected ? "代理连通" : "代理不通", data);
        } catch (Exception e) {
            return ApiResponse.error("测试代理连通未确认完成，请重新读取配置");
        }
    }

    /**
     * 一键测试全部代理连通性，结果逐条落库
     */
    @PostMapping("/testAll")
    @ResponseBody
    public ApiResponse testAll(HttpServletRequest httpRequest) {
        guardProxyAccess(httpRequest);
        try {
            java.util.Map<String, Object> data = vpnProxyRecordService.testAll();
            int total = data.get("total") instanceof Number ? ((Number) data.get("total")).intValue() : 0;
            int ok = data.get("successCount") instanceof Number ? ((Number) data.get("successCount")).intValue() : 0;
            int fail = data.get("failCount") instanceof Number ? ((Number) data.get("failCount")).intValue() : 0;
            String msg = "全部测试完成：共 " + total + " 条，通 " + ok + "，不通 " + fail;
            return ApiResponse.success(msg, data);
        } catch (Exception e) {
            return ApiResponse.error("一键测试代理未确认完成，请重新读取配置");
        }
    }

    /**
     * 查询租户当前绑定的代理（用于租户列表护盾快捷配置）
     * body: { tenantId }
     */
    @PostMapping("/findByTenant")
    @ResponseBody
    public ApiResponse findByTenant(@RequestBody VpnProxyRecordRequest request, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        try {
            if (request == null || request.getTenantId() == null) {
                return ApiResponse.error("租户 id 不能为空");
            }
            VpnProxyRecord record = vpnProxyRecordService.findBoundByTenantId(request.getTenantId());
            return ApiResponse.success(record);
        } catch (Exception e) {
            return ApiResponse.error("查询租户绑定代理失败");
        }
    }

    /**
     * 租户快捷绑定/解绑代理
     * body: { tenantId, id: proxyId 可空=解绑 }
     */
    @PostMapping("/bindTenant")
    @ResponseBody
    public ApiResponse bindTenant(@RequestBody VpnProxyRecordRequest request, HttpServletRequest httpRequest) {
        guardProxyAccess(httpRequest);
        try {
            if (request == null || request.getTenantId() == null) {
                return ApiResponse.error("租户 id 不能为空");
            }
            // id 表示目标代理；null/0 = 解绑
            vpnProxyRecordService.bindTenant(request.getTenantId(), request.getId());
            return ApiResponse.success();
        } catch (Exception e) {
            return ApiResponse.error("绑定租户代理未确认完成，请重新读取配置");
        }
    }

    private Map<String, Object> safeProxy(VpnProxyRecord record) {
        Map<String, Object> data = new HashMap<>();
        data.put("id", String.valueOf(record.getId()));
        data.put("proxyType", record.getProxyType());
        data.put("proxyHost", record.getProxyHost());
        data.put("proxyPort", record.getProxyPort());
        data.put("proxyUsername", record.getProxyUsername());
        data.put("hasPassword", record.getProxyPassword() != null && !record.getProxyPassword().isEmpty());
        data.put("availableStatus", record.getAvailableStatus());
        data.put("forceProxy", record.getForceProxy());
        data.put("customName", record.getCustomName());
        data.put("tenantId", record.getTenantId() == null ? null : String.valueOf(record.getTenantId()));
        data.put("tenantIds", record.getTenantIds().stream().map(String::valueOf).collect(Collectors.toList()));
        data.put("tenantName", record.getTenantName());
        data.put("createTime", record.getCreateTime());
        data.put("updateTime", record.getUpdateTime());
        return data;
    }

    private static void guardProxyAccess(HttpServletRequest request) {
        String site = request.getHeader("Sec-Fetch-Site");
        if ("same-origin".equals(site)) return;
        if (site != null && !"none".equals(site)) throw forbidden();
        String origin = request.getHeader("Origin");
        if (origin == null) return; // Existing authenticated native callers remain supported.
        try {
            URI uri = new URI(origin);
            if (uri.getHost() == null || uri.getScheme() == null || uri.getRawUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null || !"".equals(uri.getRawPath())) throw forbidden();
            int port = uri.getPort() < 0 ? ("https".equalsIgnoreCase(uri.getScheme()) ? 443 : 80) : uri.getPort();
            if (!uri.getScheme().equalsIgnoreCase(request.getScheme()) || port != request.getServerPort()
                    || !unbracket(uri.getHost()).equalsIgnoreCase(unbracket(request.getServerName()))) throw forbidden();
        } catch (URISyntaxException e) {
            throw forbidden();
        }
    }

    private static String unbracket(String host) {
        return host.startsWith("[") && host.endsWith("]") ? host.substring(1, host.length() - 1) : host;
    }

    private static ResponseStatusException forbidden() {
        return new ResponseStatusException(HttpStatus.FORBIDDEN, "只允许同源页面访问代理配置");
    }
}
