package com.doubledimple.ociserver.controller.dns;

import com.doubledimple.dao.repository.DnsRecordRepository;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.third.dns.TencentEdgeOneService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 腾讯云EdgeOne DNS管理控制器
 */
@Slf4j
@Controller
@RequestMapping("/dns/edgeone")
public class EdgeOneController  extends BaseController {
    @Resource
    private TencentEdgeOneService edgeOneService;

    @Resource
    private DnsRecordRepository dnsRecordRepository;

    @Resource
    SystemConfigService systemConfigService;

    /**
     * 获取Zone列表
     */
    @GetMapping("/api/zones")
    @ResponseBody
    public ApiResponse getZones() {
        try {
            List<Map<String, Object>> zones = edgeOneService.listAllZones();
            return ApiResponse.success( zones);
        } catch (Exception e) {
            log.warn("获取EdgeOne Zone列表失败: {}", e.getMessage());
            return ApiResponse.error("获取域名列表失败: " + e.getMessage());
        }
    }

    /**
     * 获取记录（支持DNS记录和加速域名）
     */
    @GetMapping("/api/records")
    @ResponseBody
    public ApiResponse getRecords(
            @RequestParam String zoneId,
            @RequestParam(defaultValue = "dns") String type) {
        try {
            List<Map<String, Object>> records;
            if ("domain".equals(type)) {
                records = edgeOneService.listAccelerationDomains(zoneId);
            } else if ("dns".equals(type)) {
                records = edgeOneService.listDnsRecords(zoneId);
            } else {
                return ApiResponse.error("记录类型参数无效");
            }
            return ApiResponse.success(records);
        } catch (Exception e) {
            log.error("获取EdgeOne记录失败: {}", e.getMessage(), e);
            return ApiResponse.error("获取记录失败: " + e.getMessage());
        }
    }

    /**
     * 添加DNS记录
     */
    @PostMapping("/api/records")
    @ResponseBody
    public ApiResponse addDnsRecord(@RequestBody Map<String, Object> request) {
        try {
            String zoneId = (String) request.get("zoneId");
            String type = (String) request.get("type");
            String name = (String) request.get("name");
            String content = (String) request.get("content");
            Integer ttl = (Integer) request.get("ttl");
            Integer priority = (Integer) request.get("priority");

            boolean success = edgeOneService.addDnsRecord(zoneId, type, name, content, ttl, priority);

            if (success) {
                return ApiResponse.success("DNS记录添加成功");
            } else {
                return ApiResponse.error("DNS记录添加失败");
            }
        } catch (Exception e) {
            log.error("添加EdgeOne DNS记录失败: {}", e.getMessage(), e);
            return ApiResponse.error("添加DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 更新DNS记录
     */
    @PutMapping("/api/records/{recordId}")
    @ResponseBody
    public ApiResponse updateDnsRecord(
            @PathVariable String recordId,
            @RequestBody Map<String, Object> request) {
        try {
            String content = (String) request.get("content");
            String recordType = (String) request.get("recordType");
            String recordName = (String) request.get("recordName");
            Integer ttl = (Integer) request.get("ttl");
            String zoneId = (String) request.get("zoneId");
            Integer priority = (Integer) request.get("priority");

            boolean success = edgeOneService.updateDnsRecord(recordId, content, recordType, recordName, ttl, zoneId, priority);

            if (success) {
                return ApiResponse.success("DNS记录更新成功");
            } else {
                return ApiResponse.error("DNS记录更新失败");
            }
        } catch (Exception e) {
            log.error("更新EdgeOne DNS记录失败: {}", e.getMessage(), e);
            return ApiResponse.error("更新DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 删除DNS记录
     */
    @DeleteMapping("/api/records/{recordId}")
    @ResponseBody
    public ApiResponse deleteDnsRecord(@PathVariable String recordId,
                                      @RequestParam(required = false) String zoneId) {
        try {
            boolean success = edgeOneService.deleteDnsRecord(recordId, zoneId);

            if (success) {
                return ApiResponse.success("DNS记录删除成功");
            } else {
                return ApiResponse.error("DNS记录删除失败");
            }
        } catch (Exception e) {
            log.error("删除EdgeOne DNS记录失败: {}", e.getMessage(), e);
            return ApiResponse.error("删除DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 同步DNS记录
     */
    @PostMapping("/api/zones/{zoneId}/sync")
    @ResponseBody
    public ApiResponse syncDnsRecords(
            @PathVariable String zoneId,
            @RequestBody Map<String, String> request) {
        try {
            String domainName = request.get("domainName");
            int syncCount = edgeOneService.syncAllDnsRecords(zoneId, domainName);

            Map<String, Object> result = new HashMap<>();
            result.put("syncCount", syncCount);

            return ApiResponse.success("DNS记录同步成功，共处理 " + syncCount + " 条记录", result);
        } catch (Exception e) {
            log.error("同步EdgeOne DNS记录失败: {}", e.getMessage(), e);
            return ApiResponse.error("同步DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 获取加速域名列表
     */
    @GetMapping("/api/domains")
    @ResponseBody
    public ApiResponse getAccelerationDomains(@RequestParam String zoneId) {
        try {
            List<Map<String, Object>> domains = edgeOneService.listAccelerationDomains(zoneId);
            return ApiResponse.builder().data( domains).success(true).build();
        } catch (Exception e) {
            log.error("获取EdgeOne加速域名失败: {}", e.getMessage(), e);
            return ApiResponse.error("获取加速域名失败: " + e.getMessage());
        }
    }

    /**
     * 删除加速域名
     */
    @DeleteMapping("/api/domains/{domainId}")
    @ResponseBody
    public ApiResponse deleteAccelerationDomain(@PathVariable String domainId,
                                               @RequestParam(required = false) String zoneId,
                                               @RequestParam(required = false) String domainName) {
        try {
            boolean success = edgeOneService.deleteAccelerationDomain(domainId, zoneId, domainName);

            if (success) {
                return ApiResponse.success("加速域名删除成功");
            } else {
                return ApiResponse.error("加速域名删除失败");
            }
        } catch (Exception e) {
            log.error("删除EdgeOne加速域名失败: {}", e.getMessage(), e);
            return ApiResponse.error("删除加速域名失败: " + e.getMessage());
        }
    }

    /**
     * 同步加速域名
     */
    @PostMapping("/api/zones/{zoneId}/sync-domains")
    @ResponseBody
    public ApiResponse syncAccelerationDomains(
            @PathVariable String zoneId,
            @RequestBody Map<String, String> request) {
        try {
            String domainName = request.get("domainName");
            int syncCount = edgeOneService.syncAllAccelerationDomains(zoneId, domainName);

            Map<String, Object> result = new HashMap<>();
            result.put("syncCount", syncCount);

            return ApiResponse.success("加速域名同步成功，共处理 " + syncCount + " 个域名", result);
        } catch (Exception e) {
            log.error("同步EdgeOne加速域名失败: {}", e.getMessage(), e);
            return ApiResponse.error("同步加速域名失败: " + e.getMessage());
        }
    }
}
