package com.doubledimple.ociserver.controller.dns;

import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.request.CloudflareConfig;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.third.dns.CloudflareService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
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
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Controller
@RequestMapping("/dns/cloudflare")
@Slf4j
public class CloudflareController  extends BaseController {

    @Resource
    private CloudflareService cloudflareService;

    @Resource
    private SystemConfigService systemConfigService;

    /**
     * 显示Cloudflare DNS管理页面
     */
    @GetMapping("")
    public String index(@RequestParam(defaultValue = "20") int size,
                        @RequestParam(defaultValue = "0") int page,
                        @RequestParam(required = false) String zoneId,
                        @RequestParam(required = false) String searchName,     // 按名称搜索
                        @RequestParam(required = false) String searchContent,  // 按内容搜索
                        Model model) {

        List<Map<String, Object>> dnsRecords = new ArrayList<>();
        int totalPages = 0;
        int totalElements = 0;

        // 如果有选择的域名，获取DNS记录
        if (StringUtils.isNotEmpty(zoneId)) {
            if (zoneId.contains("?")) {
                String[] parts = zoneId.split("\\?", 2);
                zoneId = parts[0];
                final String[] kv = parts[1].split("=", 2);
                if (kv.length == 2) {
                    String key = kv[0];   // "page"
                    String value = kv[1]; // "0"

                    if ("page".equals(key)) {
                        try {
                            page = Integer.parseInt(value);
                        } catch (NumberFormatException e) {
                        }
                    }
                }
            }
            try {
                Map<String, Object> pageResult = cloudflareService.listDnsRecordsPage(zoneId, page + 1, size,searchName,searchContent); // Cloudflare API从1开始
                dnsRecords = (List<Map<String, Object>>) pageResult.get("content");
                totalPages = (Integer) pageResult.get("totalPages");
                totalElements = (Integer) pageResult.get("totalElements");
            } catch (Exception e) {
                log.error("获取DNS记录失败，zoneId: {}", zoneId, e);
            }
        }

        // 获取Cloudflare配置
        CloudflareConfig cloudflareConfig = systemConfigService.getCloudflareConfig();
        model.addAttribute("cloudflareConfig", cloudflareConfig);

        model.addAttribute("dnsRecords", dnsRecords);
        model.addAttribute("currentPage", page);
        model.addAttribute("totalPages", totalPages);
        model.addAttribute("totalElements", totalElements);
        model.addAttribute("size", size);
        model.addAttribute("selectedZoneId", zoneId);
        model.addAttribute("activePage", "cloudflare-servers");

        return "/cf_manage";
    }

    /**
     * API接口：获取所有域名列表
     */
    @GetMapping("/api/zones")
    @ResponseBody
    public ApiResponse getZones() {
        try {
            List<Map<String, Object>> zones = cloudflareService.listAllZones();
            return ApiResponse.builder()
                    .success(true)
                    .message("获取域名列表成功")
                    .data(zones)
                    .build();
        } catch (Exception e) {
            log.error("获取域名列表失败", e);
            return ApiResponse.error("获取域名列表失败: " + e.getMessage());
        }
    }

    /**
     * API接口：获取指定域名的DNS记录
     */
    /*@GetMapping("/api/zones/{zoneId}/records")
    @ResponseBody
    public ApiResponse getDnsRecords(@PathVariable String zoneId) {
        try {
            List<Map<String, Object>> records = cloudflareService.listDnsRecords(zoneId);
            return ApiResponse.builder()
                    .success(true)
                    .message("获取DNS记录成功")
                    .data(records)
                    .build();
        } catch (Exception e) {
            log.error("获取DNS记录失败，zoneId: {}", zoneId, e);
            return ApiResponse.error("获取DNS记录失败: " + e.getMessage());
        }
    }*/

    /**
     * API接口：获取指定域名的DNS记录（分页）
     */
    @GetMapping("/api/zones/{zoneId}/records")
    @ResponseBody
    public ApiResponse getDnsRecords(@PathVariable String zoneId,
                                     @RequestParam(defaultValue = "20") int size,
                                     @RequestParam(defaultValue = "1") int page) {
        try {
            // 直接调用service的分页方法
            Map<String, Object> stringObjectMap = cloudflareService.listDnsRecordsPage(zoneId, page, size,null,null);

            return ApiResponse.builder()
                    .success(true)
                    .message("获取DNS记录成功")
                    .data(stringObjectMap)
                    .build();
        } catch (Exception e) {
            log.error("获取DNS记录失败，zoneId: {}", zoneId, e);
            return ApiResponse.error("获取DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * API接口：添加DNS记录
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
            Boolean proxied = (Boolean) request.get("proxied");

            // 验证必填参数
            if (zoneId == null || type == null || name == null || content == null) {
                return ApiResponse.error("缺少必填参数");
            }

            // 调用Service创建DNS记录
            ApiResponse dnsRecord = cloudflareService.createDnsRecord(zoneId, type, name, content, ttl, proxied);
            CloudflareService.DnsRecordDetail data = (CloudflareService.DnsRecordDetail) dnsRecord.getData();
            if (data.getFlag() == 1) {
                return ApiResponse.success("DNS记录创建成功");
            } else {
                return ApiResponse.error("DNS记录创建失败");
            }

        } catch (Exception e) {
            log.error("创建DNS记录失败", e);
            return ApiResponse.error("创建DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * API接口：更新DNS记录
     */
    @PutMapping("/api/records/{recordId}")
    @ResponseBody
    public ApiResponse updateDnsRecord(
            @PathVariable String recordId,
            @RequestBody Map<String, Object> request) {

        try {
            String content = (String) request.get("content");
            Integer ttl = (Integer) request.get("ttl");
            Boolean proxied = (Boolean) request.get("proxied");
            String recordType = (String) request.get("recordType");
            String recordName = (String) request.get("recordName");
            String zoneId = (String) request.get("zoneId");

            // 验证必填参数
            if (content == null || content.trim().isEmpty()) {
                return ApiResponse.error("记录值不能为空");
            }

            // 调用Service更新DNS记录
            boolean success = cloudflareService.updateDnsRecord(recordId, content, ttl, proxied,recordType,recordName,zoneId);

            if (success) {
                return ApiResponse.success("DNS记录更新成功");
            } else {
                return ApiResponse.error("DNS记录更新失败");
            }

        } catch (Exception e) {
            log.error("更新DNS记录失败，recordId: {}", recordId, e);
            return ApiResponse.error("更新DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * API接口：删除DNS记录
     */
    @DeleteMapping("/api/records/{recordId}")
    @ResponseBody
    public ApiResponse deleteDnsRecord(@PathVariable String recordId,
                                       @RequestParam(required = false) String zoneId) {
        try {
            boolean success = cloudflareService.deleteDnsRecord(recordId, zoneId);

            if (success) {
                return ApiResponse.success("DNS记录删除成功");
            } else {
                return ApiResponse.error("DNS记录删除失败");
            }

        } catch (Exception e) {
            log.error("删除DNS记录失败，recordId: {}", recordId, e);
            return ApiResponse.error(e.getMessage());
        }
    }

    /**
     * API接口：同步DNS记录到数据库
     */
    @PostMapping("/api/zones/{zoneId}/sync")
    @ResponseBody
    public ApiResponse syncDnsRecords(
            @PathVariable String zoneId,
            @RequestBody Map<String, Object> request) {

        try {
            String domainName = (String) request.get("domainName");

            if (domainName == null || domainName.trim().isEmpty()) {
                return ApiResponse.error("域名参数不能为空");
            }

            int syncCount = cloudflareService.syncAllDnsRecords(zoneId, domainName);

            Map<String, String> result = new HashMap<>();
            result.put("syncCount", String.valueOf(syncCount));
            return ApiResponse.builder()
                    .success(true)
                    .message("同步完成，共处理 " + syncCount + " 条记录")
                    .data(result)
                    .build();

        } catch (Exception e) {
            log.error("同步DNS记录失败，zoneId: {}", zoneId, e);
            return ApiResponse.error("同步DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * API接口：获取所有域名的DNS记录
     */
    @GetMapping("/api/records/all")
    @ResponseBody
    public ApiResponse getAllDnsRecords() {
        try {
            Map<String, List<Map<String, Object>>> allRecords = cloudflareService.listAllDnsRecords();
            return ApiResponse.builder()
                    .success(true)
                    .message("获取所有DNS记录成功")
                    .data(allRecords)
                    .build();
        } catch (Exception e) {
            log.error("获取所有DNS记录失败", e);
            return ApiResponse.error("获取所有DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * API接口：同步所有域名的DNS记录
     */
    @PostMapping("/api/sync/all")
    @ResponseBody
    public ApiResponse syncAllDomainsRecords() {
        try {
            Map<String, Integer> syncResults = cloudflareService.syncAllDomainsRecords();

            return ApiResponse.builder()
                    .success(true)
                    .message("批量同步完成")
                    .data(syncResults)
                    .build();

        } catch (Exception e) {
            log.error("批量同步DNS记录失败", e);
            return ApiResponse.error("批量同步失败: " + e.getMessage());
        }
    }
}
