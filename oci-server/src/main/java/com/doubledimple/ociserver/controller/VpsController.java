package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.PingUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName VpsController
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-14 16:22
 */
@Controller
@RequestMapping("/vps/instances")
@Slf4j
public class VpsController extends BaseController{

    @Resource
    OracleInstanceService oracleInstanceService;

    /** VPS uses all providers; the OCI-specific JSON endpoint intentionally does not. */
    @GetMapping("/list/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> listJson(
            @RequestParam(defaultValue = "200") int size,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) String tenantId) {
        if (page < 0 || size < 1 || size > 1000) {
            return ResponseEntity.badRequest().body(listError("分页参数无效"));
        }
        if (tenantId != null) {
            try {
                if (!tenantId.matches("[1-9][0-9]*") || Long.parseLong(tenantId) <= 0) {
                    return ResponseEntity.badRequest().body(listError("租户标识无效"));
                }
            } catch (NumberFormatException e) {
                return ResponseEntity.badRequest().body(listError("租户标识无效"));
            }
        }
        try {
            Page<InstanceDetailsRes> records = oracleInstanceService.getAllInstances(page, size, tenantId);
            List<Map<String, Object>> content = new ArrayList<>();
            for (InstanceDetailsRes record : records.getContent()) content.add(vpsListRow(record));
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("content", content);
            result.put("currentPage", records.getNumber());
            result.put("totalPages", records.getTotalPages());
            result.put("totalElements", records.getTotalElements());
            result.put("size", records.getSize());
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("读取VPS资源列表失败", e);
            return ResponseEntity.status(500).body(listError("读取VPS资源列表失败"));
        }
    }

    private Map<String, Object> vpsListRow(InstanceDetailsRes record) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", record.getId());
        row.put("instanceId", record.getInstanceId());
        row.put("tenantId", String.valueOf(record.getTenantId()));
        row.put("displayName", record.getDisplayName());
        row.put("publicIps", record.getPublicIps());
        row.put("tenancyName", record.getTenancyName());
        row.put("regionName", record.getRegionName());
        row.put("regionCode", record.getRegionCode());
        row.put("architecture", record.getArchitecture());
        row.put("cloudType", record.getCloudType());
        row.put("ocpus", record.getOcpus());
        row.put("memoryInGBs", record.getMemoryInGBs());
        row.put("bootVolumeSizeInGBs", record.getBootVolumeSizeInGBs());
        row.put("onLineEnable", record.getOnLineEnable());
        row.put("enablePing", record.getEnablePing());
        row.put("monitorInstalled", record.getMonitorInstalled());
        row.put("lastHeartbeat", record.getLastHeartbeat() == null ? null : record.getLastHeartbeat().getTime());
        return row;
    }

    private Map<String, Object> listError(String message) {
        Map<String, Object> error = new LinkedHashMap<>();
        error.put("success", false);
        error.put("message", message);
        return error;
    }

    /**
    * @Description: 批量启用ping测试
    * @Param: []
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubelemple
    * @Date: 9/21/25 4:22 PM
    */
    @PostMapping("enablePing")
    @ResponseBody
    public ApiResponse enablePing() {
        return oracleInstanceService.enablePing(1);
    }

    /**
    * @Description: 批量停用ping 测试
    * @Param: []
    * @return: com.doubledimple.ociserver.pojo.response.base.ApiResponse
    * @Author: doubleDimple
    * @Date: 9/21/25 4:23 PM
    */
    @PostMapping("disablePing")
    @ResponseBody
    public ApiResponse disablePing() {
        return oracleInstanceService.disablePing(1);
    }

    //手动批量ping测试
    @PostMapping("ping")
    @ResponseBody
    public ApiResponse ping() {
        return oracleInstanceService.batchPing(1);
    }

    //根据ip获取金纬度
    @PostMapping("getLatLon")
    @ResponseBody
    public ApiResponse getLatLon(String ip) {
        double[] latLonByGeoIP = PingUtil.getLatLonByGeoIP(ip);
        return ApiResponse.success(latLonByGeoIP);
    }
}
