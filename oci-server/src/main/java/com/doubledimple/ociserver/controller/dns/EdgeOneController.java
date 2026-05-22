package com.doubledimple.ociserver.controller.dns;

import com.doubledimple.dao.entity.DnsRecord;
import com.doubledimple.dao.repository.DnsRecordRepository;
import com.doubledimple.ocicommon.enums.ProviderType;
import com.doubledimple.ocicommon.enums.RecordType;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfig;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.third.dns.TencentEdgeOneService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
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
import javax.persistence.criteria.Predicate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ocicommon.enums.RecordStatus.getByName;

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
     * EdgeOne DNS管理页面
     */
    @GetMapping
    public String edgeOnePage(
            @RequestParam(value = "zoneId", required = false) String zoneId,
            @RequestParam(value = "searchName", required = false) String searchName,
            @RequestParam(value = "searchContent", required = false) String searchContent,
            @RequestParam(value = "page", defaultValue = "0") int page,
            @RequestParam(value = "size", defaultValue = "20") int size,
            @RequestParam(value = "type", defaultValue = "dns") String type,
            @RequestParam(value = "status", defaultValue = "pending") String status,
            Model model) {

        log.debug("访问EdgeOne DNS管理页面，zoneId: {}, searchName: {}, searchContent: {}, page: {}, size: {}, type: {}",
                zoneId, searchName, searchContent, page, size,type);

        try {
            // 添加搜索参数到模型
            model.addAttribute("searchName", searchName);
            model.addAttribute("searchContent", searchContent);
            model.addAttribute("selectedZoneId", zoneId);
            model.addAttribute("currentPage", page);
            model.addAttribute("size", size);

            // 如果选择了域名，查询DNS记录
            if (zoneId != null && !zoneId.trim().isEmpty()) {
                Pageable pageable = PageRequest.of(page, size, Sort.by("createTime").descending());

                // 构建查询条件
                Specification<DnsRecord> spec = (root, query, cb) -> {
                    List<Predicate> predicates = new ArrayList<>();

                    // 固定条件：zoneId 和 providerType
                    predicates.add(cb.equal(root.get("zoneId"), zoneId));
                    predicates.add(cb.equal(root.get("providerType"), ProviderType.TENCENT));
                    if (type != null && type.equals("domain")){
                        predicates.add(cb.equal(root.get("type"), 2));
                    } else if (type != null && type.equals("dns")) {
                        predicates.add(cb.equal(root.get("type"), 1));
                    }

                    predicates.add(cb.equal(root.get("status"), getByName(status)));

                    // 搜索条件
                    if (searchName != null && !searchName.trim().isEmpty()) {
                        predicates.add(cb.like(cb.lower(root.get("recordName")),
                                "%" + searchName.toLowerCase() + "%"));
                    }

                    if (searchContent != null && !searchContent.trim().isEmpty()) {
                        predicates.add(cb.like(cb.lower(root.get("recordValue")),
                                "%" + searchContent.toLowerCase() + "%"));
                    }

                    return cb.and(predicates.toArray(new Predicate[0]));
                };

                Page<DnsRecord> recordsPage = dnsRecordRepository.findAll(spec, pageable);

                // 转换为前端需要的格式
                List<Map<String, Object>> dnsRecords = new ArrayList<>();
                for (DnsRecord record : recordsPage.getContent()) {
                    Map<String, Object> recordMap = new HashMap<>();
                    recordMap.put("id", record.getProviderRecordId());
                    recordMap.put("type", record.getRecordType().name());
                    recordMap.put("name", record.getRecordName());
                    recordMap.put("content", record.getRecordValue());
                    recordMap.put("ttl", record.getTtl());
                    recordMap.put("priority", record.getPriority());
                    dnsRecords.add(recordMap);
                }

                model.addAttribute("dnsRecords", dnsRecords);
                model.addAttribute("totalElements", recordsPage.getTotalElements());
                model.addAttribute("totalPages", recordsPage.getTotalPages());
                model.addAttribute("recordType", type);
            }
            EdgeOneConfig edgeOneConfig = systemConfigService.getEdgeOneConfig();
            model.addAttribute("edgeOneConfig", edgeOneConfig);
            model.addAttribute("activePage", "edgeOne-servers");
        } catch (Exception e) {
            log.error("加载EdgeOne DNS管理页面失败: {}", e.getMessage(), e);
            model.addAttribute("error", "加载页面失败: " + e.getMessage());
        }

        return "eo_manage";
    }

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
            } else {
                records = edgeOneService.listDnsRecords(zoneId);
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
    public ApiResponse deleteDnsRecord(@PathVariable String recordId) {
        try {
            boolean success = edgeOneService.deleteDnsRecord(recordId);

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

            return ApiResponse.success("DNS记录同步成功，共处理 " + syncCount + " 条记录");
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
    public ApiResponse deleteAccelerationDomain(@PathVariable String domainId) {
        try {
            boolean success = edgeOneService.deleteAccelerationDomain(domainId);

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

            return ApiResponse.success("加速域名同步成功，共处理 " + syncCount + " 个域名");
        } catch (Exception e) {
            log.error("同步EdgeOne加速域名失败: {}", e.getMessage(), e);
            return ApiResponse.error("同步加速域名失败: " + e.getMessage());
        }
    }
}
