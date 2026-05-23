package com.doubledimple.ociserver.third.dns;

import com.doubledimple.dao.entity.DnsRecord;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TenantEmailConfig;
import com.doubledimple.dao.repository.DnsRecordRepository;
import com.doubledimple.ocicommon.enums.ProviderType;
import com.doubledimple.ocicommon.enums.RecordStatus;
import com.doubledimple.ocicommon.enums.RecordType;
import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.pojo.request.CloudflareConfig;
import com.doubledimple.ociserver.pojo.request.CloudflareConfigRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.utils.oracle.OciEmailUtils;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.common.net.InternetDomainName;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@Slf4j
public class CloudflareService {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private DnsRecordRepository dnsRecordRepository;

    private static final String CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4";

    /**
     * 获取DNS记录
     */
    public List<Map<String, Object>> listDnsRecords(String zoneId) {
        CloudflareConfig config = systemConfigService.getCloudflareConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            throw new IllegalStateException("Cloudflare未配置或未启用");
        }

        try {
            String url = CLOUDFLARE_API_BASE + "/zones/" + zoneId + "/dns_records";

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            List<Map<String, Object>> records = new ArrayList<>();

            if (jsonNode.get("success").asBoolean()) {
                JsonNode result = jsonNode.get("result");
                for (JsonNode record : result) {
                    Map<String, Object> recordInfo = new HashMap<>();
                    recordInfo.put("id", record.get("id").asText());
                    recordInfo.put("type", record.get("type").asText());
                    recordInfo.put("name", record.get("name").asText());
                    recordInfo.put("content", record.get("content").asText());
                    recordInfo.put("ttl", record.get("ttl").asInt());
                    recordInfo.put("proxied", record.has("proxied") ? record.get("proxied").asBoolean() : false);
                    records.add(recordInfo);
                }
            } else {
                handleCloudflareErrors(jsonNode);
            }

            return records;

        } catch (HttpClientErrorException e) {
            log.error("获取DNS记录失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("获取DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("获取DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取DNS记录失败: " + e.getMessage());
        }
    }

    public Map<String, Object> listDnsRecordsPage(String zoneId, int page, int pageSize, String searchName, String searchContent) {
        CloudflareConfig config = systemConfigService.getCloudflareConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            log.warn("Cloudflare未配置或未启用，返回空DNS记录列表");
            return createEmptyPageResult();
        }

        try {
            // 构建URL
            StringBuilder urlBuilder = new StringBuilder();
            urlBuilder.append(CLOUDFLARE_API_BASE)
                    .append("/zones/")
                    .append(zoneId)
                    .append("/dns_records?page=")
                    .append(page)
                    .append("&per_page=")
                    .append(pageSize);

            // 根据搜索条件添加参数
            boolean hasSearch = false;
            if (StringUtils.isNotEmpty(searchName)) {
                try {
                    String encodedSearch = URLEncoder.encode(searchName.trim(), "UTF-8");
                    urlBuilder.append("&name=").append(encodedSearch);
                    hasSearch = true;
                    log.info("使用name搜索参数: {}", searchName);
                } catch (UnsupportedEncodingException e) {
                    log.error("URL编码失败", e);
                }
            }

            if (StringUtils.isNotEmpty(searchContent)) {
                try {
                    String encodedSearch = URLEncoder.encode(searchContent.trim(), "UTF-8");
                    urlBuilder.append("&content=").append(encodedSearch);
                    hasSearch = true;
                    log.info("使用content搜索参数: {}", searchContent);
                } catch (UnsupportedEncodingException e) {
                    log.error("URL编码失败", e);
                }
            }

            String url = urlBuilder.toString();
            log.info("请求URL: {}", url);

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                JsonNode result = jsonNode.get("result");
                List<Map<String, Object>> records = new ArrayList<>();

                // 处理DNS记录
                for (JsonNode record : result) {
                    Map<String, Object> recordInfo = new HashMap<>();
                    recordInfo.put("id", record.get("id").asText());
                    recordInfo.put("type", record.get("type").asText());
                    recordInfo.put("name", record.get("name").asText());
                    recordInfo.put("content", record.get("content").asText());
                    recordInfo.put("ttl", record.get("ttl").asInt());
                    recordInfo.put("proxied", record.has("proxied") ? record.get("proxied").asBoolean() : false);

                    if (record.has("priority")) {
                        recordInfo.put("priority", record.get("priority").asInt());
                    }
                    if (record.has("comment")) {
                        recordInfo.put("comment", record.get("comment").asText());
                    }

                    records.add(recordInfo);
                }

                log.info("API返回 {} 条记录", records.size());

                // 使用API返回的分页信息
                JsonNode resultInfo = jsonNode.get("result_info");
                Map<String, Object> pageResult = new HashMap<>();
                pageResult.put("content", records);

                if (resultInfo != null) {
                    pageResult.put("totalPages", resultInfo.get("total_pages").asInt());
                    pageResult.put("totalElements", resultInfo.get("total_count").asInt());
                    pageResult.put("number", resultInfo.get("page").asInt() - 1);
                    pageResult.put("size", pageSize);
                    pageResult.put("first", resultInfo.get("page").asInt() == 1);
                    pageResult.put("last", resultInfo.get("page").asInt() == resultInfo.get("total_pages").asInt());
                } else {
                    pageResult.put("totalPages", 1);
                    pageResult.put("totalElements", records.size());
                    pageResult.put("number", page - 1);
                    pageResult.put("size", pageSize);
                    pageResult.put("first", true);
                    pageResult.put("last", true);
                }

                return pageResult;

            } else {
                log.error("获取DNS记录失败，Zone: {}, Cloudflare API返回错误", zoneId);
                handleCloudflareErrors(jsonNode);
                return createEmptyPageResult();
            }

        } catch (Exception e) {
            log.error("获取DNS记录失败，Zone: {}, 错误: {}", zoneId, e.getMessage(), e);
            return createEmptyPageResult();
        }
    }

    private Map<String, Object> createEmptyPageResult() {
        Map<String, Object> result = new HashMap<>();
        result.put("content", new ArrayList<>());
        result.put("totalPages", 0);
        result.put("totalElements", 0);
        result.put("number", 0);
        result.put("size", 20);
        result.put("first", true);
        result.put("last", true);
        return result;
    }

    /**
     * 同步所有DNS记录到数据库
     */
    @Transactional
    public int syncAllDnsRecords(String zoneId, String domainName) {
        log.info("开始同步Cloudflare DNS记录，zoneId: {}, domain: {}", zoneId, domainName);

        try {
            // 获取Cloudflare的所有DNS记录
            List<Map<String, Object>> cloudflareRecords = listDnsRecords(zoneId);

            // 获取数据库中已存在的记录
            List<DnsRecord> existingRecords = dnsRecordRepository.findByZoneIdAndProviderType(zoneId,
                    ProviderType.CLOUDFLARE);

            Map<String, DnsRecord> existingRecordsMap = existingRecords.stream()
                    .collect(Collectors.toMap(DnsRecord::getProviderRecordId, record -> record));

            int syncCount = 0;
            Set<String> currentRecordIds = new HashSet<>();

            // 处理从Cloudflare获取的记录
            for (Map<String, Object> cfRecord : cloudflareRecords) {
                String recordId = (String) cfRecord.get("id");
                currentRecordIds.add(recordId);

                DnsRecord dnsRecord = existingRecordsMap.get(recordId);

                if (dnsRecord == null) {
                    // 新记录，创建
                    dnsRecord = createDnsRecordFromCloudflare(cfRecord, zoneId, domainName);
                    dnsRecordRepository.save(dnsRecord);
                    log.info("新增DNS记录: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                } else {
                    // 已存在，更新
                    updateDnsRecordFromCloudflare(dnsRecord, cfRecord);
                    dnsRecordRepository.save(dnsRecord);
                    log.debug("更新DNS记录: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                }

                syncCount++;
            }

            // 处理已删除的记录（在数据库中存在但Cloudflare中不存在）
            for (DnsRecord existingRecord : existingRecords) {
                if (!currentRecordIds.contains(existingRecord.getProviderRecordId())) {
                    existingRecord.setStatus(RecordStatus.INACTIVE);
                    existingRecord.setRemark("记录已在Cloudflare中删除");
                    dnsRecordRepository.delete(existingRecord);
                    log.debug("标记删除的DNS记录: {} -> {}", existingRecord.getRecordName(), existingRecord.getRecordValue());
                }
            }

            log.info("同步完成，域名:{},共处理 {} 条记录",domainName, syncCount);
            return syncCount;

        } catch (Exception e) {
            log.error("同步DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("同步DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 删除DNS记录
     */
    @Transactional
    public boolean deleteDnsRecord(String recordId) {
        return deleteDnsRecord(recordId, null);
    }

    /**
     * 删除DNS记录
     */
    @Transactional
    public boolean deleteDnsRecord(String recordId, String zoneId) {
        log.info("开始删除DNS记录，recordId: {}", recordId);

        try {
            // 从数据库查找记录
            Optional<DnsRecord> optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
            DnsRecord dnsRecord = optionalRecord.orElse(null);
            String resolvedZoneId = dnsRecord != null ? dnsRecord.getZoneId() : zoneId;
            if (StringUtils.isBlank(resolvedZoneId)) {
                throw new IllegalArgumentException("缺少域名区域信息，请刷新页面后重试");
            }

            CloudflareConfig config = systemConfigService.getCloudflareConfig();

            if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
                throw new IllegalStateException("Cloudflare未配置或未启用");
            }

            // 调用Cloudflare API删除记录
            String url = CLOUDFLARE_API_BASE + "/zones/" + resolvedZoneId + "/dns_records/" + recordId;

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.DELETE, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                // 删除成功，更新数据库记录状态
                if (dnsRecord != null) {
                    dnsRecord.setStatus(RecordStatus.INACTIVE);
                    dnsRecord.setRemark("已删除");
                    dnsRecord.setUpdateTime(LocalDateTime.now());
                    dnsRecordRepository.save(dnsRecord);
                    log.info("删除DNS记录成功: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                } else {
                    log.info("删除Cloudflare DNS记录成功，本地未找到缓存记录，recordId: {}", recordId);
                }
                return true;
            } else {
                handleCloudflareErrors(jsonNode);
                return false;
            }

        } catch (HttpClientErrorException e) {
            log.error("删除DNS记录失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException(readableCloudflareDeleteError(e));
        } catch (Exception e) {
            log.error("删除DNS记录失败: {}", e.getMessage(), e);
            throw e instanceof RuntimeException ? (RuntimeException) e : new RuntimeException(e.getMessage());
        }
    }

    private String readableCloudflareDeleteError(HttpClientErrorException e) {
        try {
            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(e.getResponseBodyAsString());
            JsonNode errors = jsonNode.get("errors");
            if (errors != null && errors.isArray() && errors.size() > 0) {
                List<String> messages = new ArrayList<>();
                for (JsonNode error : errors) {
                    if (error.has("message")) {
                        messages.add(error.get("message").asText());
                    }
                }
                if (!messages.isEmpty()) {
                    return String.join("；", messages);
                }
            }
        } catch (Exception ignored) {
            // Fall back to the HTTP exception message below.
        }
        return "Cloudflare 删除失败，请刷新列表后重试";
    }

    /**
     * 修改DNS记录的IP地址
     */
    @Transactional
    public boolean updateDnsRecordIp(String recordId, String newIpAddress) {
        log.debug("开始更新DNS记录IP，recordId: {}, newIp: {}", recordId, newIpAddress);

        try {
            // 从数据库查找记录
            Optional<DnsRecord> optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
            if (!optionalRecord.isPresent()) {
                //从cloudflare再拉取一次
                syncAllDomainsRecords();
            }

            DnsRecord dnsRecord = optionalRecord.get();
            CloudflareConfig config = systemConfigService.getCloudflareConfig();

            if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
                throw new IllegalStateException("Cloudflare未配置或未启用");
            }

            // 准备更新数据
            /*Map<String, Object> updateData = new HashMap<>();
            updateData.put("content", newIpAddress);
            updateData.put("name", dnsRecord.getRecordName());
            updateData.put("type", dnsRecord.getRecordType().name());
            updateData.put("ttl", dnsRecord.getTtl() != null ? dnsRecord.getTtl() : 300);

            if (dnsRecord.getProxied() != null) {
                updateData.put("proxied", dnsRecord.getProxied());
            }

            if (dnsRecord.getPriority() != null) {
                updateData.put("priority", dnsRecord.getPriority());
            }

            // 调用Cloudflare API更新记录
            String url = CLOUDFLARE_API_BASE + "/zones/" + dnsRecord.getZoneId() + "/dns_records/" + recordId;

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(updateData, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.PUT, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());*/

            JsonNode jsonNode = updateRecords(dnsRecord, recordId, newIpAddress, config);

            if (jsonNode.get("success").asBoolean()) {
                // 更新成功，同步数据库记录
                String oldIp = dnsRecord.getRecordValue();
                dnsRecord.setRecordValue(newIpAddress);
                dnsRecord.setUpdateTime(LocalDateTime.now());
                dnsRecord.setLastSyncTime(LocalDateTime.now());
                dnsRecord.setRemark("IP已更新: " + oldIp + " -> " + newIpAddress);
                dnsRecordRepository.save(dnsRecord);

                log.info("更新DNS记录IP成功: {} {} -> {}", dnsRecord.getRecordName(), oldIp, newIpAddress);
                return true;
            } else {
                handleCloudflareErrors(jsonNode);
                return false;
            }

        } catch (HttpClientErrorException e) {
            log.error("更新DNS记录IP失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("更新DNS记录IP失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("更新DNS记录IP失败: {}", e.getMessage(), e);
            throw new RuntimeException("更新DNS记录IP失败: " + e.getMessage());
        }
    }

    public JsonNode updateRecords(DnsRecord dnsRecord, String recordId, String newIpAddress,CloudflareConfig config) throws JsonProcessingException {
        // 准备更新数据
        Map<String, Object> updateData = new HashMap<>();
        updateData.put("content", newIpAddress);
        updateData.put("name", dnsRecord.getRecordName());
        updateData.put("type", dnsRecord.getRecordType().name());
        updateData.put("ttl", dnsRecord.getTtl() != null ? dnsRecord.getTtl() : 300);

        if (dnsRecord.getProxied() != null) {
            updateData.put("proxied", dnsRecord.getProxied());
        }

        if (dnsRecord.getPriority() != null) {
            updateData.put("priority", dnsRecord.getPriority());
        }

        // 调用Cloudflare API更新记录
        String url = CLOUDFLARE_API_BASE + "/zones/" + dnsRecord.getZoneId() + "/dns_records/" + recordId;

        HttpHeaders headers = createHeaders(config.getApiToken());
        HttpEntity<Map<String, Object>> entity = new HttpEntity<>(updateData, headers);

        RestTemplate restTemplate = new RestTemplate();
        ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.PUT, entity, String.class);

        ObjectMapper mapper = new ObjectMapper();
        return mapper.readTree(response.getBody());
    }

    /*public List<Map<String, Object>> listAllZones() {
        CloudflareConfig config = systemConfigService.getCloudflareConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            log.warn("Cloudflare未配置或未启用，返回空DNS记录列表");
            return new ArrayList<>();
        }

        try {
            String url = CLOUDFLARE_API_BASE + "/zones";

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            List<Map<String, Object>> zones = new ArrayList<>();

            if (jsonNode.get("success").asBoolean()) {
                JsonNode result = jsonNode.get("result");
                for (JsonNode zone : result) {
                    Map<String, Object> zoneInfo = new HashMap<>();
                    zoneInfo.put("id", zone.get("id").asText());
                    zoneInfo.put("name", zone.get("name").asText());
                    zoneInfo.put("status", zone.get("status").asText());
                    zones.add(zoneInfo);
                }
            } else {
                handleCloudflareErrors(jsonNode);
            }

            return zones;

        } catch (HttpClientErrorException e) {
            log.error("获取Zone列表失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("获取Zone列表失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        }
    }*/

    public List<Map<String, Object>> listAllZones() {
        CloudflareConfig config = systemConfigService.getCloudflareConfig();
        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            return new ArrayList<>();
        }

        List<Map<String, Object>> allZones = new ArrayList<>();
        RestTemplate restTemplate = new RestTemplate();
        ObjectMapper mapper = new ObjectMapper();
        int page = 1;
        int perPage = 50;

        try {
            while (true) {
                String url = String.format("%s/zones?page=%d&per_page=%d", CLOUDFLARE_API_BASE, page, perPage);

                HttpHeaders headers = createHeaders(config.getApiToken());
                HttpEntity<Void> entity = new HttpEntity<>(null, headers);
                ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

                JsonNode jsonNode = mapper.readTree(response.getBody());

                if (jsonNode.get("success").asBoolean()) {
                    JsonNode result = jsonNode.get("result");
                    if (result == null || result.size() == 0) {
                        break;
                    }
                    for (JsonNode zone : result) {
                        Map<String, Object> zoneInfo = new HashMap<>();
                        zoneInfo.put("id", zone.get("id").asText());
                        zoneInfo.put("name", zone.get("name").asText());
                        zoneInfo.put("status", zone.get("status").asText());
                        allZones.add(zoneInfo);
                    }
                    JsonNode resultInfo = jsonNode.get("result_info");
                    int totalPages = resultInfo.get("total_pages").asInt();

                    if (page >= totalPages) {
                        break;
                    }
                    page++;
                } else {
                    handleCloudflareErrors(jsonNode);
                    break;
                }
            }
            return allZones;

        } catch (Exception e) {
            log.error("循环获取所有Zone失败: {}", e.getMessage());
            throw new RuntimeException("获取所有Zone失败: " + e.getMessage());
        }
    }

    /**
     * 获取所有域名的所有DNS记录
     */
    public Map<String, List<Map<String, Object>>> listAllDnsRecords() {
        log.info("开始获取所有域名的DNS记录");

        Map<String, List<Map<String, Object>>> allRecords = new HashMap<>();

        try {
            // 先获取所有Zone列表
            List<Map<String, Object>> zones = listAllZones();

            // 遍历每个Zone获取DNS记录
            for (Map<String, Object> zone : zones) {
                String zoneId = (String) zone.get("id");
                String zoneName = (String) zone.get("name");

                log.info("获取域名 {} 的DNS记录", zoneName);

                try {
                    List<Map<String, Object>> dnsRecords = listDnsRecords(zoneId);
                    allRecords.put(zoneName, dnsRecords);
                    log.info("域名 {} 共有 {} 条DNS记录", zoneName, dnsRecords.size());
                } catch (Exception e) {
                    log.error("获取域名 {} 的DNS记录失败: {}", zoneName, e.getMessage());
                    // 继续处理其他域名，不因为一个域名失败而中断
                    allRecords.put(zoneName, new ArrayList<>());
                }
            }

            log.info("获取所有DNS记录完成，共处理 {} 个域名", zones.size());
            return allRecords;

        } catch (Exception e) {
            log.error("获取所有DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取所有DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 获取指定页面的Zone列表（处理分页）
     */
    public List<Map<String, Object>> listAllZonesWithPagination() {
        CloudflareConfig config = systemConfigService.getCloudflareConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            throw new IllegalStateException("Cloudflare未配置或未启用");
        }

        List<Map<String, Object>> allZones = new ArrayList<>();
        int page = 1;
        int perPage = 50; // Cloudflare默认每页50条记录
        boolean hasMore = true;

        try {
            while (hasMore) {
                String url = CLOUDFLARE_API_BASE + "/zones?page=" + page + "&per_page=" + perPage;

                HttpHeaders headers = createHeaders(config.getApiToken());
                HttpEntity<Void> entity = new HttpEntity<>(null, headers);

                RestTemplate restTemplate = new RestTemplate();
                ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

                ObjectMapper mapper = new ObjectMapper();
                JsonNode jsonNode = mapper.readTree(response.getBody());

                if (jsonNode.get("success").asBoolean()) {
                    JsonNode result = jsonNode.get("result");

                    for (JsonNode zone : result) {
                        Map<String, Object> zoneInfo = new HashMap<>();
                        zoneInfo.put("id", zone.get("id").asText());
                        zoneInfo.put("name", zone.get("name").asText());
                        zoneInfo.put("status", zone.get("status").asText());
                        allZones.add(zoneInfo);
                    }

                    // 检查是否还有更多页面
                    JsonNode resultInfo = jsonNode.get("result_info");
                    int totalPages = resultInfo.get("total_pages").asInt();
                    hasMore = page < totalPages;
                    page++;

                } else {
                    handleCloudflareErrors(jsonNode);
                    break;
                }
            }

            log.info("获取Zone列表完成，共 {} 个域名", allZones.size());
            return allZones;

        } catch (HttpClientErrorException e) {
            log.error("获取Zone列表失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("获取Zone列表失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        }
    }

    /**
     * 同步所有域名的DNS记录到数据库
     */
    @Transactional
    public Map<String, Integer> syncAllDomainsRecords() {
        log.info("开始同步所有域名的DNS记录");

        Map<String, Integer> syncResults = new HashMap<>();

        try {
            // 先获取所有Zone列表
            List<Map<String, Object>> zones = listAllZones();

            // 遍历每个Zone同步DNS记录
            for (Map<String, Object> zone : zones) {
                String zoneId = (String) zone.get("id");
                String zoneName = (String) zone.get("name");

                log.info("同步域名 {} 的DNS记录", zoneName);

                try {
                    int syncCount = syncAllDnsRecords(zoneId, zoneName);
                    syncResults.put(zoneName, syncCount);
                    log.info("域名 {} 同步完成，共处理 {} 条记录", zoneName, syncCount);
                } catch (Exception e) {
                    log.error("同步域名 {} 的DNS记录失败: {}", zoneName, e.getMessage());
                    syncResults.put(zoneName, -1); // -1 表示同步失败
                }
            }

            log.info("所有域名DNS记录同步完成");
            return syncResults;

        } catch (Exception e) {
            log.error("同步所有域名DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("同步所有域名DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 从Cloudflare记录创建DnsRecord实体
     */
    private DnsRecord createDnsRecordFromCloudflare(Map<String, Object> cfRecord, String zoneId, String domainName) {
        DnsRecord dnsRecord = new DnsRecord();

        dnsRecord.setProviderType(ProviderType.CLOUDFLARE);
        dnsRecord.setProviderRecordId((String) cfRecord.get("id"));
        dnsRecord.setZoneId(zoneId);
        dnsRecord.setDomainName(domainName);

        // 处理记录名称
        String fullName = (String) cfRecord.get("name");
        String recordName = extractRecordName(fullName, domainName);
        dnsRecord.setRecordName(recordName);

        // 设置记录类型
        String type = (String) cfRecord.get("type");
        dnsRecord.setRecordType(RecordType.valueOf(type));

        dnsRecord.setRecordValue((String) cfRecord.get("content"));
        dnsRecord.setTtl((Integer) cfRecord.get("ttl"));
        dnsRecord.setProxied((Boolean) cfRecord.get("proxied"));
        dnsRecord.setStatus(RecordStatus.ACTIVE);
        dnsRecord.setLastSyncTime(LocalDateTime.now());

        return dnsRecord;
    }

    /**
     * 从Cloudflare记录更新DnsRecord实体
     */
    private void updateDnsRecordFromCloudflare(DnsRecord dnsRecord, Map<String, Object> cfRecord) {
        dnsRecord.setRecordValue((String) cfRecord.get("content"));
        dnsRecord.setTtl((Integer) cfRecord.get("ttl"));
        dnsRecord.setProxied((Boolean) cfRecord.get("proxied"));
        dnsRecord.setStatus(RecordStatus.ACTIVE);
        dnsRecord.setLastSyncTime(LocalDateTime.now());
        dnsRecord.setUpdateTime(LocalDateTime.now());
    }

    /**
     * 提取记录名称（去除域名后缀）
     */
    private String extractRecordName(String fullName, String domainName) {
        if (fullName.equals(domainName)) {
            return "@";
        }
        if (fullName.endsWith("." + domainName)) {
            return fullName.substring(0, fullName.length() - domainName.length() - 1);
        }
        return fullName;
    }

    /**
     * 创建HTTP请求头 - 关键修复
     */
    private HttpHeaders createHeaders(String apiKey) {
        CloudflareConfig config = systemConfigService.getCloudflareConfig();
        String email = config.getEmail();

        HttpHeaders headers = new HttpHeaders();
        // 使用API Key认证方式
        headers.set("X-Auth-Email", email);
        headers.set("X-Auth-Key", apiKey.trim());
        headers.set("Content-Type", "application/json");
        return headers;
    }

    /**
     * 处理Cloudflare API错误
     */
    private void handleCloudflareErrors(JsonNode jsonNode) {
        JsonNode errors = jsonNode.get("errors");
        if (errors != null && errors.isArray()) {
            StringBuilder errorMsg = new StringBuilder();
            for (JsonNode error : errors) {
                errorMsg.append(error.get("message").asText()).append("; ");
            }
            throw new RuntimeException("Cloudflare API错误: " + errorMsg.toString());
        }
    }

    /**
     * 创建DNS记录
     */
    @Transactional
    public ApiResponse createDnsRecord(String zoneId, String type, String name, String content, Integer ttl, Boolean proxied) {
        log.info("开始创建DNS记录，zoneId: {}, type: {}, name: {}, content: {}", zoneId, type, name, content);

        CloudflareConfig config = systemConfigService.getCloudflareConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            throw new IllegalStateException("Cloudflare未配置或未启用");
        }
        DnsRecordDetail dnsRecordDetail = new DnsRecordDetail();
        try {
            String url = CLOUDFLARE_API_BASE + "/zones/" + zoneId + "/dns_records";

            HttpHeaders headers = createHeaders(config.getApiToken());

            // 准备请求数据
            Map<String, Object> requestData = new HashMap<>();
            requestData.put("type", type);
            requestData.put("name", name);
            requestData.put("content", content);
            requestData.put("ttl", ttl != null ? ttl : 1); // 默认自动TTL

            // 只有A和AAAA记录支持代理
            if (("A".equals(type) || "AAAA".equals(type)) && proxied != null) {
                requestData.put("proxied", proxied);
            }

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestData, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.POST, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                log.info("创建DNS记录成功: {} -> {}", name, content);

                // 获取创建的记录信息并保存到数据库
                JsonNode result = jsonNode.get("result");
                if (result != null) {
                    saveDnsRecordToDatabase(result, zoneId, extractDomainFromZone(zoneId));
                }
                dnsRecordDetail.setDnsId(result.get("id").asText());
                dnsRecordDetail.setFlag(1);
                return ApiResponse.success(dnsRecordDetail);
            } else {
                handleCloudflareErrors(jsonNode);
                dnsRecordDetail.setFlag(0);
                return ApiResponse.success(dnsRecordDetail);
            }

        } catch (HttpClientErrorException e) {
            log.error("创建DNS记录失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("创建DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("创建DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("创建DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 更新DNS记录
     */
    @Transactional
    public boolean updateDnsRecord(String recordId, String content, Integer ttl, Boolean proxied,String recordTypeStr,String recordName,String zoneId) {
        log.info("开始更新DNS记录，recordId: {}, content: {}", recordId, content);

        try {
            // 从数据库查找记录信息
            DnsRecord dnsRecord;
            Optional<DnsRecord> optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
            if (!optionalRecord.isPresent()) {
                log.warn("未找到DNS记录: {}", recordId);
                dnsRecord = new DnsRecord();
                dnsRecord.setTtl(ttl);
                dnsRecord.setProviderRecordId(recordId);
                dnsRecord.setRecordValue( content);
                dnsRecord.setRecordType(RecordType.fromValue(recordTypeStr));
                dnsRecord.setRecordName(recordName);
                dnsRecord.setZoneId(zoneId);
                dnsRecord.setDomainName(recordName);
                dnsRecord.setProviderType(ProviderType.CLOUDFLARE);
            }else {
                dnsRecord = optionalRecord.get();
            }

            CloudflareConfig config = systemConfigService.getCloudflareConfig();

            if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
                throw new IllegalStateException("Cloudflare未配置或未启用");
            }

            // 准备更新数据
            Map<String, Object> updateData = new HashMap<>();
            updateData.put("content", content);
            updateData.put("name", dnsRecord.getRecordName());
            updateData.put("type", dnsRecord.getRecordType().name());
            updateData.put("ttl", ttl != null ? ttl : (dnsRecord.getTtl() != null ? dnsRecord.getTtl() : 1));

            // 只有A和AAAA记录支持代理
            RecordType recordType = dnsRecord.getRecordType();
            if ((recordType == RecordType.A || recordType == RecordType.AAAA) && proxied != null) {
                updateData.put("proxied", proxied);
            } else if (dnsRecord.getProxied() != null) {
                updateData.put("proxied", dnsRecord.getProxied());
            }

            // 调用Cloudflare API更新记录
            String url = CLOUDFLARE_API_BASE + "/zones/" + dnsRecord.getZoneId() + "/dns_records/" + recordId;

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(updateData, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.PUT, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                // 更新成功，同步数据库记录
                String oldValue = dnsRecord.getRecordValue();
                dnsRecord.setRecordValue(content);
                if (ttl != null) {
                    dnsRecord.setTtl(ttl);
                }
                if (proxied != null && (recordType == RecordType.A || recordType == RecordType.AAAA)) {
                    dnsRecord.setProxied(proxied);
                }
                dnsRecord.setUpdateTime(LocalDateTime.now());
                dnsRecord.setLastSyncTime(LocalDateTime.now());
                dnsRecord.setRemark("记录已更新: " + oldValue + " -> " + content);
                dnsRecordRepository.save(dnsRecord);

                log.info("更新DNS记录成功: {} {} -> {}", dnsRecord.getRecordName(), oldValue, content);
                return true;
            } else {
                handleCloudflareErrors(jsonNode);
                return false;
            }

        } catch (HttpClientErrorException e) {
            log.error("更新DNS记录失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("更新DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("更新DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("更新DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 将Cloudflare记录保存到数据库
     */
    private void saveDnsRecordToDatabase(JsonNode recordNode, String zoneId, String domainName) {
        try {
            DnsRecord dnsRecord = new DnsRecord();
            dnsRecord.setProviderType(ProviderType.CLOUDFLARE);
            dnsRecord.setProviderRecordId(recordNode.get("id").asText());
            dnsRecord.setZoneId(zoneId);
            dnsRecord.setDomainName(domainName);

            // 处理记录名称
            String fullName = recordNode.get("name").asText();
            String recordName = extractRecordName(fullName, domainName);
            dnsRecord.setRecordName(recordName);

            // 设置记录类型
            String type = recordNode.get("type").asText();
            dnsRecord.setRecordType(RecordType.valueOf(type));

            dnsRecord.setRecordValue(recordNode.get("content").asText());
            dnsRecord.setTtl(recordNode.get("ttl").asInt());

            if (recordNode.has("proxied")) {
                dnsRecord.setProxied(recordNode.get("proxied").asBoolean());
            }

            dnsRecord.setStatus(RecordStatus.ACTIVE);
            dnsRecord.setCreateTime(LocalDateTime.now());
            dnsRecord.setLastSyncTime(LocalDateTime.now());
            dnsRecord.setRemark("通过API创建");

            dnsRecordRepository.save(dnsRecord);

        } catch (Exception e) {
            log.error("保存DNS记录到数据库失败", e);
            // 不抛出异常，避免影响主流程
        }
    }

    /**
     * 从Zone ID提取域名（这是一个简化实现，实际可能需要调用API获取）
     */
    private String extractDomainFromZone(String zoneId) {
        try {
            // 如果有缓存或者数据库中有zone信息，优先使用
            // 这里简化处理，实际使用时可能需要调用API获取zone详情
            CloudflareConfig config = systemConfigService.getCloudflareConfig();
            String url = CLOUDFLARE_API_BASE + "/zones/" + zoneId;

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                return jsonNode.get("result").get("name").asText();
            }
        } catch (Exception e) {
            log.warn("获取域名失败，使用zoneId作为域名: {}", zoneId);
        }

        return zoneId;
    }

    public Map<String, Object> testCloudflareConnection(CloudflareConfigRequest request) {
        Map<String, Object> result = new HashMap<>();

        try {
            // 验证API Key和邮箱
            if (StringUtils.isEmpty(request.getApiToken())) {
                throw new IllegalArgumentException("API Key不能为空");
            }
            if (StringUtils.isEmpty(request.getEmail())) {
                throw new IllegalArgumentException("邮箱地址不能为空");
            }

            String apiKey = request.getApiToken().trim();

            // 检查API Key基本格式
            if (apiKey.length() < 32) {
                result.put("success", false);
                result.put("message", "API Key格式不正确，请检查是否为有效的Cloudflare Global API Key");
                return result;
            }

            log.info("开始测试Cloudflare连接，API Key长度: {}, 邮箱: {}", apiKey.length(), request.getEmail());

            // 临时保存邮箱到配置中供验证使用
            //saveOrUpdateConfig("cloudflare.email", request.getEmail());

            // 调用Cloudflare API验证连接
            boolean isValid = validateCloudflareApiToken(apiKey, request.getEmail());

            if (isValid) {
                result.put("success", true);
                result.put("message", "Cloudflare API连接成功");

                log.info("Cloudflare连接测试成功");
            } else {
                result.put("success", false);
                result.put("message", "API Key或邮箱验证失败，请检查是否正确");
                log.warn("Cloudflare API Key验证失败");
            }

        } catch (IllegalArgumentException e) {
            result.put("success", false);
            result.put("message", e.getMessage());
            log.warn("Cloudflare连接测试参数错误: {}", e.getMessage());
        } catch (Exception e) {
            log.error("测试Cloudflare连接失败: {}", e.getMessage(), e);
            result.put("success", false);
            result.put("message", "连接失败: " + e.getMessage());
        }

        return result;
    }


    public boolean validateCloudflareApiToken(String apiKey, String email) {
        try {
            // 检查API Key格式 - Cloudflare Global API Key通常是32-40字符
            if (apiKey.length() < 32 || apiKey.contains(" ")) {
                log.error("API Key格式不正确，长度: {}", apiKey.length());
                return false;
            }

            if (StringUtils.isEmpty(email)) {
                log.error("使用API Key时必须配置邮箱地址");
                return false;
            }

            String url = "https://api.cloudflare.com/client/v4/user";

            // 创建请求头 - 使用API Key认证方式
            HttpHeaders headers = new HttpHeaders();
            headers.set("X-Auth-Email", email.trim());
            headers.set("X-Auth-Key", apiKey.trim());
            headers.set("Content-Type", "application/json");

            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();

            try {
                ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

                log.info("Cloudflare API响应状态: {}, 响应体: {}", response.getStatusCode(), response.getBody());

                // 解析响应
                ObjectMapper mapper = new ObjectMapper();
                JsonNode jsonNode = mapper.readTree(response.getBody());

                boolean success = jsonNode.get("success").asBoolean();

                if (success) {
                    log.info("API Key验证成功");
                    return true;
                } else {
                    // 记录错误信息
                    JsonNode errors = jsonNode.get("errors");
                    if (errors != null && errors.isArray()) {
                        for (JsonNode error : errors) {
                            log.error("Cloudflare API错误: 代码={}, 消息={}",
                                    error.get("code").asText(),
                                    error.get("message").asText());
                        }
                    }
                    return false;
                }

            } catch (org.springframework.web.client.HttpClientErrorException e) {
                log.error("Cloudflare API请求失败 - 状态码: {}, 响应: {}", e.getStatusCode(), e.getResponseBodyAsString());
                return false;
            }

        } catch (Exception e) {
            log.error("验证Cloudflare API Key失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
     * 为ACME证书申请添加DNS TXT记录
     */
    @Transactional
    public String addAcmeTxtRecord(String domain, String recordName, String recordValue) {
        log.info("为ACME挑战添加DNS TXT记录: {} = {}", recordName, recordValue);

        CloudflareConfig config = systemConfigService.getCloudflareConfig();
        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            throw new IllegalStateException("Cloudflare未配置或未启用");
        }

        try {
            // 获取域名的Zone ID
            String zoneId = getZoneIdByDomain(domain);

            String url = CLOUDFLARE_API_BASE + "/zones/" + zoneId + "/dns_records";

            HttpHeaders headers = createHeaders(config.getApiToken());

            // 准备请求数据
            Map<String, Object> requestData = new HashMap<>();
            requestData.put("type", "TXT");
            requestData.put("name", recordName);
            requestData.put("content", recordValue);
            requestData.put("ttl", 60); // 最短TTL，加快传播

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestData, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.POST, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                String recordId = jsonNode.get("result").get("id").asText();
                log.info("ACME DNS记录添加成功: {} -> {}, recordId: {}", recordName, recordValue, recordId);
                return recordId;
            } else {
                handleCloudflareErrors(jsonNode);
                throw new RuntimeException("添加ACME DNS记录失败");
            }

        } catch (HttpClientErrorException e) {
            log.error("添加ACME DNS记录失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("添加ACME DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("添加ACME DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("添加ACME DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 删除ACME DNS TXT记录
     */
    @Transactional
    public void removeAcmeTxtRecord(String domain, String recordId) {
        log.info("删除ACME DNS记录: domain={}, recordId={}", domain, recordId);

        if (StringUtils.isEmpty(recordId)) {
            log.warn("recordId为空，跳过删除");
            return;
        }

        CloudflareConfig config = systemConfigService.getCloudflareConfig();
        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            log.warn("Cloudflare未配置，跳过DNS记录删除");
            return;
        }

        try {
            String zoneId = getZoneIdByDomain(domain);
            String url = CLOUDFLARE_API_BASE + "/zones/" + zoneId + "/dns_records/" + recordId;

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<String> request = new HttpEntity<>(headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.DELETE, request, String.class);

            if (response.getStatusCode().is2xxSuccessful()) {
                log.info("ACME DNS记录删除成功: {}", recordId);
            } else {
                log.warn("ACME DNS记录删除失败: HTTP {}", response.getStatusCode());
            }

        } catch (Exception e) {
            log.warn("删除ACME DNS记录失败，但不影响证书申请: {} - {}", recordId, e.getMessage());
            // 不抛出异常，避免影响证书申请流程
        }
    }

    /**
     * 根据域名获取Zone ID
     */
    public String getZoneIdByDomain(String domain) {
        // 提取根域名
        String rootDomain = extractRootDomain(domain);

        CloudflareConfig config = systemConfigService.getCloudflareConfig();
        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            throw new IllegalStateException("Cloudflare未配置或未启用");
        }

        try {
            String url = CLOUDFLARE_API_BASE + "/zones?name=" + rootDomain;

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<String> request = new HttpEntity<>(headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, request, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                JsonNode result = jsonNode.get("result");
                if (result.isArray() && result.size() > 0) {
                    String zoneId = result.get(0).get("id").asText();
                    log.debug("找到Zone ID: {} -> {}", rootDomain, zoneId);
                    return zoneId;
                }
            } else {
                handleCloudflareErrors(jsonNode);
            }

            throw new RuntimeException("找不到域名对应的Cloudflare Zone: " + rootDomain);

        } catch (Exception e) {
            log.error("获取Zone ID失败: {} - {}", rootDomain, e.getMessage());
            throw new RuntimeException("获取Zone ID失败: " + e.getMessage());
        }
    }

    /**
     * 提取根域名
     */
    private String extractRootDomain(String domain) {
        if (StringUtils.isEmpty(domain)) {
            return domain;
        }

        // 处理通配符域名
        if (domain.startsWith("*.")) {
            domain = domain.substring(2);
        }

        // 简单的根域名提取逻辑
        String[] parts = domain.split("\\.");
        if (parts.length >= 2) {
            return parts[parts.length - 2] + "." + parts[parts.length - 1];
        }

        return domain;
    }

    /**
     * 验证Cloudflare API连接状态
     */
    public boolean isCloudflareConfigValid() {
        try {
            CloudflareConfig config = systemConfigService.getCloudflareConfig();
            if (config == null || !config.isEnabled()) {
                return false;
            }

            return validateCloudflareApiToken(config.getApiToken(), config.getEmail());
        } catch (Exception e) {
            log.warn("验证Cloudflare配置失败: {}", e.getMessage());
            return false;
        }
    }

    /**
     * 为邮件服务添加必要的DNS记录
     */
    public ApiResponse addOracleEmailDnsRecords(String emailDomainName, TenantEmailConfig tenantEmailConfig) {
        try {
            // 获取域名的Zone ID
            String zoneId = getZoneIdByDomain(emailDomainName);

            // 先检查现有DNS记录
            List<Map<String, Object>> existingRecords = listDnsRecords(zoneId);

            List<String> addedRecords = new ArrayList<>();
            List<String> skippedRecords = new ArrayList<>();

            // 1. 检查并添加SPF记录
            if (!spfRecordExists(existingRecords, emailDomainName)) {
                ApiResponse apiResponse = null;
                try {
                    apiResponse = createDnsRecord(zoneId, "TXT", emailDomainName,
                           "v=spf1 include:emaildelivery.oracle.com ~all",
                           600,
                           false
                   );
                    DnsRecordDetail dnsRecordDetail = (DnsRecordDetail) apiResponse.getData();
                    if (dnsRecordDetail.getFlag() == 1) {
                        addedRecords.add(dnsRecordDetail.getDnsId());
                        log.info("SPF记录添加成功: {}", emailDomainName);
                    }
                } catch (Exception e) {
                    log.warn("添加SPF记录失败: {}", emailDomainName);
                }
            } else {
                skippedRecords.add("SPF记录已存在");
                log.info("SPF记录已存在，跳过添加: {}", emailDomainName);
            }

            // 2. 检查并添加DKIM CNAME记录
            String cnameRecordValue = tenantEmailConfig.getCnameRecordValue();
            if (StringUtils.isNotBlank(cnameRecordValue)) {
                String dkimName = extractDkimName(cnameRecordValue);
                String dkimTarget = extractDkimTarget(cnameRecordValue);

                if (!dkimRecordExists(existingRecords, dkimName)) {
                    ApiResponse cname = null;
                    try {
                        cname = createDnsRecord(zoneId, "CNAME", dkimName, dkimTarget, 600, false
                        );
                        DnsRecordDetail dnsRecordDetail = (DnsRecordDetail) cname.getData();
                        if (dnsRecordDetail.getFlag() == 1) {
                            addedRecords.add(dnsRecordDetail.getDnsId());
                            log.info("DKIM记录添加成功: {} -> {}", dkimName, dkimTarget);
                        }
                    } catch (Exception e) {
                        log.warn("添加DKIM CNAME记录失败: {}", dkimName);
                    }
                } else {
                    skippedRecords.add("DKIM记录已存在");
                    log.info("DKIM记录已存在，跳过添加: {}", dkimName);
                }
            }

            Map<String, Object> result = new HashMap<>();
            result.put("addedRecords", addedRecords);
            result.put("skippedRecords", skippedRecords);
            result.put("addedCount", addedRecords.size());
            result.put("skippedCount", skippedRecords.size());

            String message = String.format("DNS记录处理完成。新增: %d条, 跳过: %d条",
                    addedRecords.size(), skippedRecords.size());
            return ApiResponse.success(result);

        } catch (Exception e) {
            log.error("添加邮件DNS记录失败", e);
            return ApiResponse.error("添加DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 检查SPF记录是否已存在
     */
    private boolean spfRecordExists(List<Map<String, Object>> records, String domainName) {
        for (Map<String, Object> record : records) {
            String type = (String) record.get("type");
            String name = (String) record.get("name");
            String content = (String) record.get("content");

            if ("TXT".equals(type) &&
                    (domainName.equals(name) || "@".equals(name)) &&
                    content != null && content.contains("include:emaildelivery.oracle.com")) {
                return true;
            }
        }
        return false;
    }

    /**
     * 检查DKIM记录是否已存在
     */
    private boolean dkimRecordExists(List<Map<String, Object>> records, String dkimName) {
        for (Map<String, Object> record : records) {
            String type = (String) record.get("type");
            String name = (String) record.get("name");

            if ("CNAME".equals(type) && dkimName.equals(name)) {
                return true;
            }
        }
        return false;
    }

    /**
     * 从DKIM CNAME记录值中提取记录名称
     */
    private String extractDkimName(String cnameRecordValue) {
        // OCI返回的DKIM记录通常格式为：selector1._domainkey.domain.com
        // 需要根据实际返回格式调整
        if (cnameRecordValue.contains("._domainkey.")) {
            return cnameRecordValue.split(" ")[0];
        }
        return "selector1._domainkey";
    }

    /**
     * 从DKIM CNAME记录值中提取目标值
     */
    private String extractDkimTarget(String cnameRecordValue) {
        // 需要根据OCI实际返回的DKIM记录格式调整
        // 通常格式为：selector1.domain._domainkey.emaildelivery.oracle.com
        if (cnameRecordValue.contains(" ")) {
            return cnameRecordValue.split(" ")[1]; // 取第二部分作为目标
        }
        return cnameRecordValue;
    }

    /**
    * 添加A记录
    */
    public void createSimpleARecord(String globalDomain) {
        log.info("添加A记录: {}", globalDomain);
        InternetDomainName name = InternetDomainName.from(globalDomain);
        InternetDomainName topPrivate = name.topPrivateDomain();
        String rootDomain = topPrivate.toString();
        String prefix = globalDomain.replace("." + rootDomain, "");
        log.info("rootDomain: {}", rootDomain);
        log.info("前缀: {}", prefix);
        String publicIp = IpUtils.getPublicIp();
        String zoneId = getZoneIdByDomain(rootDomain);
        //查询是否存在根域名的记录和前缀域名的记录
        log.info("开始查询根域名是否存在");
        try {
            Map<String, Object> rootRecord = getDnsRecordIdIfExists(zoneId, rootDomain, RecordType.A.getValue());
            Map<String, Object> newPrefixRecord = getDnsRecordIdIfExists(zoneId, globalDomain, RecordType.A.getValue());
            CloudflareConfig config = systemConfigService.getCloudflareConfig();
            DnsRecord dnsRecord = new DnsRecord();
            dnsRecord.setRecordName(rootDomain);
            dnsRecord.setRecordType(RecordType.A);
            dnsRecord.setTtl(null);

            if (rootRecord == null){
                log.info("开始添加根域名的记录");
                createDnsRecord(zoneId, RecordType.A.getValue(), rootDomain, publicIp, null, false);
                createDnsRecord(zoneId, RecordType.A.getValue(), "www", publicIp, null, false);
            }else {
                String rootRecordId = (String)rootRecord.get("id");
                String content = (String)rootRecord.get("content");
                if (!content.equals(publicIp)){
                    updateRecords(dnsRecord, rootRecordId,publicIp, config);
                }
            }

            if (newPrefixRecord == null){
                log.info("开始添加前缀域名的记录");
                createDnsRecord(zoneId, RecordType.A.getValue(), prefix, publicIp, null, false);
            }else{
                String newPrefixRecordId = (String)rootRecord.get("id");
                String content = (String)rootRecord.get("content");
                if (!content.equals(publicIp)){
                    updateRecords(dnsRecord, newPrefixRecordId,publicIp, config);
                }
            }
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }

    }

    @Data
    public static class DnsRecordDetail {
        private String dnsId;
        private Integer flag;
    }

    /**
     * 根据 name + type 判断 DNS 记录是否存在，并返回 recordId
     * @param zoneId Zone ID
     * @param recordName 域名
     * @param type 记录类型，例如 "A"、"TXT"、"CNAME"
     * @return 存在则返回 recordId，不存在返回 null
     */
    public Map<String, Object> getDnsRecordIdIfExists(String zoneId, String recordName, String type) {
        Map<String, Object> recordInfo = new HashMap<>();
        CloudflareConfig config = systemConfigService.getCloudflareConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getApiToken())) {
            throw new IllegalStateException("Cloudflare未配置或未启用");
        }

        try {
            String url = CLOUDFLARE_API_BASE + "/zones/" + zoneId + "/dns_records?name="
                    + URLEncoder.encode(recordName, "UTF-8")
                    + "&type=" + URLEncoder.encode(type, "UTF-8");

            HttpHeaders headers = createHeaders(config.getApiToken());
            HttpEntity<Void> entity = new HttpEntity<>(null, headers);

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);

            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(response.getBody());

            if (jsonNode.get("success").asBoolean()) {
                JsonNode result = jsonNode.get("result");
                if (result.isArray() && result.size() > 0) {
                    // 正常情况下，name + type 唯一，所以只取第一条
                    //return result.get(0).get("id").asText();
                    JsonNode record = result.get(0);
                    recordInfo.put("id", record.get("id").asText());
                    recordInfo.put("type", record.get("type").asText());
                    recordInfo.put("name", record.get("name").asText());
                    recordInfo.put("content", record.get("content").asText());
                    recordInfo.put("ttl", record.get("ttl").asInt());
                    recordInfo.put("proxied", record.has("proxied") ? record.get("proxied").asBoolean() : false);
                    return recordInfo;
                }
                return null;
            } else {
                handleCloudflareErrors(jsonNode);
                return null;
            }

        } catch (HttpClientErrorException e) {
            log.error("检查DNS记录是否存在失败: {}", e.getResponseBodyAsString());
            throw new RuntimeException("检查DNS记录是否存在失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("检查DNS记录是否存在失败: {}", e.getMessage(), e);
            throw new RuntimeException("检查DNS记录是否存在失败: " + e.getMessage());
        }
    }


}
