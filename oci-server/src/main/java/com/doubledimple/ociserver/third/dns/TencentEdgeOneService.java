package com.doubledimple.ociserver.third.dns;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.DnsRecord;
import com.doubledimple.dao.repository.DnsRecordRepository;
import com.doubledimple.ocicommon.enums.ProviderType;
import com.doubledimple.ocicommon.enums.RecordStatus;
import com.doubledimple.ocicommon.enums.RecordType;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.tencentcloudapi.common.Credential;
import com.tencentcloudapi.common.exception.TencentCloudSDKException;
import com.tencentcloudapi.common.profile.ClientProfile;
import com.tencentcloudapi.common.profile.HttpProfile;
import com.tencentcloudapi.teo.v20220901.TeoClient;

import com.tencentcloudapi.teo.v20220901.models.AccelerationDomain;
import com.tencentcloudapi.teo.v20220901.models.CreateAccelerationDomainRequest;
import com.tencentcloudapi.teo.v20220901.models.CreateAccelerationDomainResponse;
import com.tencentcloudapi.teo.v20220901.models.CreateDnsRecordRequest;
import com.tencentcloudapi.teo.v20220901.models.CreateDnsRecordResponse;
import com.tencentcloudapi.teo.v20220901.models.DeleteAccelerationDomainsRequest;
import com.tencentcloudapi.teo.v20220901.models.DeleteAccelerationDomainsResponse;
import com.tencentcloudapi.teo.v20220901.models.DeleteDnsRecordsRequest;
import com.tencentcloudapi.teo.v20220901.models.DeleteDnsRecordsResponse;
import com.tencentcloudapi.teo.v20220901.models.DescribeAccelerationDomainsRequest;
import com.tencentcloudapi.teo.v20220901.models.DescribeAccelerationDomainsResponse;
import com.tencentcloudapi.teo.v20220901.models.DescribeDnsRecordsRequest;
import com.tencentcloudapi.teo.v20220901.models.DescribeDnsRecordsResponse;
import com.tencentcloudapi.teo.v20220901.models.DescribeZonesRequest;
import com.tencentcloudapi.teo.v20220901.models.DescribeZonesResponse;
import com.tencentcloudapi.teo.v20220901.models.ModifyDnsRecordsRequest;
import com.tencentcloudapi.teo.v20220901.models.ModifyDnsRecordsResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName TencentEdgeOneService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-27 10:37
 */
@Service
@Slf4j
public class TencentEdgeOneService {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private DnsRecordRepository dnsRecordRepository;

    /**
     * 创建EdgeOne客户端
     */
    private TeoClient createTeoClient() {
        EdgeOneConfig config = systemConfigService.getEdgeOneConfig();

        if (!config.isEnabled() || StringUtils.isEmpty(config.getSecretId()) || StringUtils.isEmpty(config.getSecretKey())) {
            throw new IllegalStateException("腾讯云EdgeOne未配置或未启用");
        }

        try {
            Credential cred = new Credential(config.getSecretId(), config.getSecretKey());

            HttpProfile httpProfile = new HttpProfile();
            httpProfile.setEndpoint("teo.tencentcloudapi.com");

            ClientProfile clientProfile = new ClientProfile();
            clientProfile.setHttpProfile(httpProfile);

            // EdgeOne是全球服务，推荐使用以下region之一：
            // ap-beijing, ap-shanghai, ap-guangzhou, ap-singapore, na-ashburn, eu-frankfurt
            String region = StringUtils.isNotEmpty(config.getRegion()) ? config.getRegion() : "ap-beijing";

            return new TeoClient(cred, region, clientProfile);
        } catch (Exception e) {
            log.error("创建EdgeOne客户端失败: {}", e.getMessage(), e);
            throw new RuntimeException("创建EdgeOne客户端失败: " + e.getMessage());
        }
    }

    private String requireEdgeOneId(String value) {
        if (value == null || !value.matches("[A-Za-z0-9_-]+")) {
            throw new IllegalArgumentException("EdgeOne区域或记录标识无效");
        }
        return value;
    }

    private String requiredText(String value, String field) {
        if (StringUtils.isBlank(value)) throw new IllegalStateException("EdgeOne字段不完整: " + field);
        return value;
    }

    private Integer localNumber(Long value, int minimum, int maximum, String field) {
        if (value == null) return null;
        if (value < minimum || value > maximum) throw new IllegalStateException("EdgeOne数值字段无效: " + field);
        return value.intValue();
    }

    private long validatePage(Long total, long offset, int length, long limit, Long expectedTotal) {
        if (total == null || total < 0 || total > Integer.MAX_VALUE
                || (expectedTotal != null && !expectedTotal.equals(total))) {
            throw new IllegalStateException("EdgeOne分页总量无效或读取期间已变化，请重新读取");
        }
        long expectedLength = Math.max(0L, Math.min(limit, total - offset));
        if (length != expectedLength) {
            throw new IllegalStateException("EdgeOne分页记录不完整，未接受部分列表");
        }
        return total;
    }

    private RecordType requireDnsType(String value) {
        RecordType type = RecordType.fromValue(value);
        if (type == null || type == RecordType.SP_DOMAIN) {
            throw new IllegalArgumentException("本地DNS记录暂不支持此类型: " + value);
        }
        return type;
    }

    private boolean matchesCacheType(DnsRecord record, int type) {
        return Integer.valueOf(type).equals(record.getType())
                && (type == 2 ? record.getRecordType() == RecordType.SP_DOMAIN
                : record.getRecordType() != RecordType.SP_DOMAIN);
    }

    private List<DnsRecord> scopedCache(String zoneId, int type) {
        return dnsRecordRepository.findByZoneIdAndProviderType(zoneId, ProviderType.TENCENT).stream()
                .filter(record -> matchesCacheType(record, type)).collect(Collectors.toList());
    }

    private DnsRecord findCachedRecord(String zoneId, String recordId, int type) {
        DnsRecord match = null;
        for (DnsRecord record : scopedCache(zoneId, type)) {
            if (!recordId.equals(record.getProviderRecordId())) continue;
            if (match != null) throw new IllegalStateException("当前区域存在重复本地记录，请先核对缓存");
            match = record;
        }
        return match;
    }

    private String resolveDnsZone(String recordId, String zoneId) {
        requireEdgeOneId(recordId);
        if (StringUtils.isNotBlank(zoneId)) return requireEdgeOneId(zoneId);
        // Legacy callers may omit the zone; never use another provider or an acceleration domain.
        DnsRecord match = null;
        for (DnsRecord record : dnsRecordRepository.findByProviderType(ProviderType.TENCENT)) {
            if (!matchesCacheType(record, 1) || !recordId.equals(record.getProviderRecordId())) continue;
            if (match != null) throw new IllegalStateException("本地记录标识不唯一，请明确指定区域");
            match = record;
        }
        if (match == null) throw new IllegalArgumentException("未找到当前服务商的DNS缓存，请指定区域并刷新");
        return requireEdgeOneId(match.getZoneId());
    }

    private Map<String, Object> dnsRecordInfo(com.tencentcloudapi.teo.v20220901.models.DnsRecord record,
                                               String zoneId) {
        if (record == null) throw new IllegalStateException("EdgeOne DNS记录为空");
        if (record.getZoneId() != null && !zoneId.equals(record.getZoneId())) {
            throw new IllegalStateException("EdgeOne DNS记录不属于当前区域");
        }
        Map<String, Object> item = new HashMap<>();
        item.put("id", requireEdgeOneId(record.getRecordId()));
        item.put("type", requiredText(record.getType(), "type"));
        item.put("name", requiredText(record.getName(), "name"));
        if (record.getContent() == null) throw new IllegalStateException("EdgeOne DNS记录值缺失");
        item.put("content", record.getContent());
        item.put("ttl", localNumber(record.getTTL(), 1, Integer.MAX_VALUE, "ttl"));
        item.put("priority", localNumber(record.getPriority(), 0, 65535, "priority"));
        item.put("weight", localNumber(record.getWeight(), 0, Integer.MAX_VALUE, "weight"));
        item.put("status", record.getStatus());
        item.put("location", record.getLocation());
        return item;
    }

    private List<com.tencentcloudapi.teo.v20220901.models.DnsRecord> readDnsSnapshot(String zoneId) {
        requireEdgeOneId(zoneId);
        TeoClient client = createTeoClient();
        List<com.tencentcloudapi.teo.v20220901.models.DnsRecord> records = new ArrayList<>();
        Set<String> ids = new HashSet<>();
        Long expectedTotal = null;
        long limit = 100L;
        try {
            for (long offset = 0L; ; offset += limit) {
                DescribeDnsRecordsRequest request = new DescribeDnsRecordsRequest();
                request.setZoneId(zoneId);
                request.setOffset(offset);
                request.setLimit(limit);
                DescribeDnsRecordsResponse response = client.DescribeDnsRecords(request);
                if (response == null) throw new IllegalStateException("EdgeOne未返回DNS列表");
                com.tencentcloudapi.teo.v20220901.models.DnsRecord[] page = response.getDnsRecords();
                int count = page == null ? 0 : page.length;
                long total = validatePage(response.getTotalCount(), offset, count, limit, expectedTotal);
                expectedTotal = total;
                if (page != null) for (com.tencentcloudapi.teo.v20220901.models.DnsRecord record : page) {
                    Map<String, Object> item = dnsRecordInfo(record, zoneId);
                    if (!ids.add((String) item.get("id"))) throw new IllegalStateException("EdgeOne DNS分页包含重复记录");
                    records.add(record);
                }
                if (offset + count >= total) break;
            }
            return records;
        } catch (TencentCloudSDKException e) {
            throw new IllegalStateException("读取EdgeOne完整DNS列表失败: " + e.getMessage(), e);
        }
    }

    private com.tencentcloudapi.teo.v20220901.models.DnsRecord requireCloudDnsRecord(String zoneId, String recordId) {
        for (com.tencentcloudapi.teo.v20220901.models.DnsRecord record : readDnsSnapshot(zoneId)) {
            if (recordId.equals(record.getRecordId())) return record;
        }
        throw new IllegalArgumentException("当前EdgeOne区域未找到此DNS记录，请刷新列表");
    }

    private String requireZoneName(String zoneId, String requestedName) {
        requireEdgeOneId(zoneId);
        for (Map<String, Object> zone : listAllZones()) {
            if (!zoneId.equals(zone.get("id"))) continue;
            String actualName = (String) zone.get("name");
            if (requestedName != null && !actualName.equalsIgnoreCase(requestedName.trim())) {
                throw new IllegalArgumentException("域名与当前EdgeOne区域不匹配，请刷新区域列表");
            }
            return actualName;
        }
        throw new IllegalArgumentException("当前账号未找到此EdgeOne区域，请刷新区域列表");
    }

    /**
     * 获取DNS记录
     */
    public List<Map<String, Object>> listDnsRecords(String zoneId) {
        log.debug("开始获取EdgeOne DNS记录，zoneId: {}", zoneId);

        try {
            List<Map<String, Object>> records = new ArrayList<>();
            for (com.tencentcloudapi.teo.v20220901.models.DnsRecord record : readDnsSnapshot(zoneId)) {
                records.add(dnsRecordInfo(record, zoneId));
            }

            log.info("获取EdgeOne DNS记录成功，共 {} 条", records.size());
            return records;

        } catch (Exception e) {
            log.error("获取EdgeOne DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取DNS记录失败: " + e.getMessage());
        }
    }


    /**
     * 同步所有DNS记录到数据库
     */
    @Transactional
    public int syncAllDnsRecords(String zoneId, String domainName) {
        log.info("开始同步EdgeOne DNS记录，zoneId: {}, domain: {}", zoneId, domainName);
        int type = 1;
        try {
            domainName = requireZoneName(zoneId, domainName);
            // 获取EdgeOne的所有DNS记录
            List<Map<String, Object>> edgeOneRecords = listDnsRecords(zoneId);
            // Validate every type before the first managed entity can be changed.
            for (Map<String, Object> record : edgeOneRecords) requireDnsType((String) record.get("type"));

            // 获取数据库中已存在的记录
            List<DnsRecord> existingRecords = scopedCache(zoneId, type);

            Map<String, DnsRecord> existingRecordsMap = existingRecords.stream()
                    .collect(Collectors.toMap(DnsRecord::getProviderRecordId, record -> record));

            int syncCount = 0;
            Set<String> currentRecordIds = new HashSet<>();

            // 处理从EdgeOne获取的记录
            for (Map<String, Object> eoRecord : edgeOneRecords) {
                String recordId = (String) eoRecord.get("id");
                currentRecordIds.add(recordId);

                DnsRecord dnsRecord = existingRecordsMap.get(recordId);

                if (dnsRecord == null) {
                    // 新记录，创建
                    dnsRecord = createDnsRecordFromEdgeOne(eoRecord, zoneId, domainName,type);
                    dnsRecordRepository.save(dnsRecord);
                    log.info("新增DNS记录: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                } else {
                    // 已存在，更新
                    dnsRecord.setDomainName(domainName);
                    updateDnsRecordFromEdgeOne(dnsRecord, eoRecord,type);
                    dnsRecordRepository.save(dnsRecord);
                    log.debug("更新DNS记录: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                }

                syncCount++;
            }

            // 处理已删除的记录（在数据库中存在但EdgeOne中不存在）
            for (DnsRecord existingRecord : existingRecords) {
                if (!currentRecordIds.contains(existingRecord.getProviderRecordId())) {
                    existingRecord.setStatus(RecordStatus.INACTIVE);
                    existingRecord.setRemark("记录已在EdgeOne中删除");
                    dnsRecordRepository.delete(existingRecord);
                    log.debug("标记删除的DNS记录: {} -> {}", existingRecord.getRecordName(), existingRecord.getRecordValue());
                }
            }

            log.info("同步完成，域名:{}, 共处理 {} 条记录", domainName, syncCount);
            return syncCount;

        } catch (Exception e) {
            log.error("同步DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("同步DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 同步所有加速域名到数据库
     */
    @Transactional
    public int syncAllAccelerationDomains(String zoneId, String zoneName) {
        log.info("开始同步EdgeOne加速域名，zoneId: {}, zoneName: {}", zoneId, zoneName);
        int type = 2;
        try {
            zoneName = requireZoneName(zoneId, zoneName);
            // 获取EdgeOne的所有加速域名
            List<Map<String, Object>> edgeOneDomains = listAccelerationDomains(zoneId);

            List<DnsRecord> existingDomains = scopedCache(zoneId, type);

            Map<String, DnsRecord> existingDomainsMap = existingDomains.stream()
                    .collect(Collectors.toMap(DnsRecord::getProviderRecordId, record -> record));

            int syncCount = 0;
            Set<String> currentDomainIds = new HashSet<>();

            // 处理从EdgeOne获取的加速域名
            for (Map<String, Object> eoDomain : edgeOneDomains) {
                String domainId = (String) eoDomain.get("id");
                currentDomainIds.add(domainId);

                DnsRecord dnsRecord = existingDomainsMap.get(domainId);

                if (dnsRecord == null) {
                    // 新记录，创建 - 复用现有方法，但传入加速域名数据
                    dnsRecord = createDnsRecordFromEdgeOne(eoDomain, zoneId, zoneName,type);
                    // 手动设置为加速域名类型
                    dnsRecord.setRecordType(RecordType.SP_DOMAIN);
                    dnsRecordRepository.save(dnsRecord);
                    log.info("新增加速域名: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                } else {
                    // 已存在，更新 - 复用现有方法
                    updateDnsRecordFromEdgeOne(dnsRecord, eoDomain,type);
                    dnsRecordRepository.save(dnsRecord);
                    log.debug("更新加速域名: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
                }

                syncCount++;
            }

            // 处理已删除的记录（在数据库中存在但EdgeOne中不存在）
            for (DnsRecord existingDomain : existingDomains) {
                if (!currentDomainIds.contains(existingDomain.getProviderRecordId())) {
                    existingDomain.setStatus(RecordStatus.INACTIVE);
                    existingDomain.setRemark("加速域名已在EdgeOne中删除");
                    dnsRecordRepository.delete(existingDomain);
                    log.debug("标记删除的加速域名: {} -> {}", existingDomain.getRecordName(), existingDomain.getRecordValue());
                }
            }

            log.info("同步完成，域名:{}, 共处理 {} 个加速域名", zoneName, syncCount);
            return syncCount;

        } catch (Exception e) {
            log.error("同步加速域名失败: {}", e.getMessage(), e);
            throw new RuntimeException("同步加速域名失败: " + e.getMessage());
        }
    }

    /**
     * 删除DNS记录
     */
    @Transactional
    public boolean deleteDnsRecord(String recordId) {
        return deleteDnsRecord(recordId, null);
    }

    @Transactional
    public boolean deleteDnsRecord(String recordId, String zoneId) {
        log.info("开始删除EdgeOne DNS记录，recordId: {}", recordId);

        try {
            String resolvedZone = resolveDnsZone(recordId, zoneId);
            DnsRecord dnsRecord = findCachedRecord(resolvedZone, recordId, 1);
            requireCloudDnsRecord(resolvedZone, recordId);
            TeoClient client = createTeoClient();

            // 调用EdgeOne API删除记录
            DeleteDnsRecordsRequest req = new DeleteDnsRecordsRequest();
            req.setZoneId(resolvedZone);
            req.setRecordIds(new String[]{recordId});

            DeleteDnsRecordsResponse resp = client.DeleteDnsRecords(req);

            if (resp != null && StringUtils.isNotBlank(resp.getRequestId())) {
                // 删除成功，更新数据库记录状态
                if (dnsRecord != null) {
                    dnsRecord.setStatus(RecordStatus.INACTIVE);
                    dnsRecord.setRemark("已删除");
                    dnsRecord.setUpdateTime(LocalDateTime.now());
                    dnsRecordRepository.save(dnsRecord);
                }
                log.info("EdgeOne已接受DNS记录删除，recordId: {}", recordId);
                return true;
            }

            return false;

        } catch (TencentCloudSDKException e) {
            log.error("删除EdgeOne DNS记录失败: {}", e.getMessage());
            throw new RuntimeException("删除DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("删除EdgeOne DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("删除DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 修改DNS记录的IP地址
     */
    /**
     * 修改DNS记录的IP地址
     */
    @Transactional
    public boolean updateDnsRecordIp(String recordId, String newIpAddress) {
        log.debug("开始更新EdgeOne DNS记录IP，recordId: {}, newIp: {}", recordId, newIpAddress);

        try {
            // 从数据库查找记录
            Optional<DnsRecord> optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
            if (!optionalRecord.isPresent()) {
                //从EdgeOne再拉取一次
                syncAllDomainsRecords();
                optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
                if (!optionalRecord.isPresent()) {
                    throw new IllegalArgumentException("未找到DNS记录: " + recordId);
                }
            }

            DnsRecord dnsRecord = optionalRecord.get();
            TeoClient client = createTeoClient();

            // EdgeOne使用ModifyDnsRecords接口来修改DNS记录
            ModifyDnsRecordsRequest req = new ModifyDnsRecordsRequest();
            req.setZoneId(dnsRecord.getZoneId());

            // 构建DNS记录对象
            com.tencentcloudapi.teo.v20220901.models.DnsRecord[] dnsRecords =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord[1];

            com.tencentcloudapi.teo.v20220901.models.DnsRecord modifyRecord =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord();

            modifyRecord.setRecordId(recordId);
            modifyRecord.setName(dnsRecord.getRecordName());
            modifyRecord.setType(dnsRecord.getRecordType().name());
            modifyRecord.setContent(newIpAddress);
            modifyRecord.setTTL(dnsRecord.getTtl() != null ? dnsRecord.getTtl().longValue() : 300L);

            if (dnsRecord.getPriority() != null) {
                modifyRecord.setPriority(dnsRecord.getPriority().longValue());
            }
            if (dnsRecord.getWeight() != null) {
                modifyRecord.setWeight(dnsRecord.getWeight().longValue());
            }

            dnsRecords[0] = modifyRecord;
            req.setDnsRecords(dnsRecords);

            // 调用EdgeOne API更新记录
            ModifyDnsRecordsResponse resp = client.ModifyDnsRecords(req);

            if (resp != null) {
                // 更新成功，同步数据库记录
                String oldIp = dnsRecord.getRecordValue();
                dnsRecord.setRecordValue(newIpAddress);
                dnsRecord.setUpdateTime(LocalDateTime.now());
                dnsRecord.setLastSyncTime(LocalDateTime.now());
                dnsRecord.setRemark("IP已更新: " + oldIp + " -> " + newIpAddress);
                dnsRecordRepository.save(dnsRecord);

                log.info("更新EdgeOne DNS记录IP成功: {} {} -> {}", dnsRecord.getRecordName(), oldIp, newIpAddress);
                return true;
            }

            return false;

        } catch (TencentCloudSDKException e) {
            log.error("更新EdgeOne DNS记录IP失败: {}", e.getMessage());
            throw new RuntimeException("更新DNS记录IP失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("更新EdgeOne DNS记录IP失败: {}", e.getMessage(), e);
            throw new RuntimeException("更新DNS记录IP失败: " + e.getMessage());
        }
    }


    /**
     * 获取所有Zone列表
     */
    public List<Map<String, Object>> listAllZones() {
        log.debug("开始获取EdgeOne Zone列表");

        try {
            TeoClient client = createTeoClient();

            List<Map<String, Object>> zones = new ArrayList<>();
            Set<String> ids = new HashSet<>();
            Long expectedTotal = null;
            long limit = 100L;
            for (long offset = 0L; ; offset += limit) {
                DescribeZonesRequest req = new DescribeZonesRequest();
                req.setOffset(offset);
                req.setLimit(limit);
                DescribeZonesResponse resp = client.DescribeZones(req);
                if (resp == null) throw new IllegalStateException("EdgeOne未返回区域列表");
                com.tencentcloudapi.teo.v20220901.models.Zone[] page = resp.getZones();
                int count = page == null ? 0 : page.length;
                long total = validatePage(resp.getTotalCount(), offset, count, limit, expectedTotal);
                expectedTotal = total;
                if (page != null) for (com.tencentcloudapi.teo.v20220901.models.Zone zone : page) {
                    if (zone == null) throw new IllegalStateException("EdgeOne区域记录为空");
                    String id = requireEdgeOneId(zone.getZoneId());
                    if (!ids.add(id)) throw new IllegalStateException("EdgeOne区域分页包含重复标识");
                    Map<String, Object> zoneInfo = new HashMap<>();
                    zoneInfo.put("id", id);
                    zoneInfo.put("name", requiredText(zone.getZoneName(), "zoneName"));
                    zoneInfo.put("status", zone.getStatus());
                    zoneInfo.put("type", zone.getType());
                    zones.add(zoneInfo);
                }
                if (offset + count >= total) break;
            }

            log.debug("获取EdgeOne Zone列表成功，共 {} 个域名", zones.size());
            return zones;

        } catch (TencentCloudSDKException e) {
            log.warn("获取EdgeOne Zone列表失败: {}", e.getMessage());
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        } catch (Exception e) {
            log.warn("获取EdgeOne Zone列表失败: {}", e.getMessage());
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        }
    }

    /**
     * 获取所有域名的所有DNS记录
     */
    public Map<String, List<Map<String, Object>>> listAllDnsRecords() {
        log.info("开始获取所有域名的EdgeOne DNS记录");

        Map<String, List<Map<String, Object>>> allRecords = new HashMap<>();

        try {
            // 先获取所有Zone列表
            List<Map<String, Object>> zones = listAllZones();

            // 遍历每个Zone获取DNS记录
            for (Map<String, Object> zone : zones) {
                String zoneId = (String) zone.get("id");
                String zoneName = (String) zone.get("name");

                log.info("获取域名 {} 的EdgeOne DNS记录", zoneName);

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
        log.debug("开始获取EdgeOne Zone列表（分页）");

        List<Map<String, Object>> allZones = new ArrayList<>();
        Long offset = 0L;
        Long limit = 20L;
        boolean hasMore = true;

        try {
            TeoClient client = createTeoClient();

            while (hasMore) {
                DescribeZonesRequest req = new DescribeZonesRequest();
                req.setOffset(offset);
                req.setLimit(limit);

                DescribeZonesResponse resp = client.DescribeZones(req);

                if (resp.getZones() != null && resp.getZones().length > 0) {
                    for (com.tencentcloudapi.teo.v20220901.models.Zone zone : resp.getZones()) {
                        Map<String, Object> zoneInfo = new HashMap<>();
                        zoneInfo.put("id", zone.getZoneId());
                        zoneInfo.put("name", zone.getZoneName());
                        zoneInfo.put("status", zone.getStatus());
                        zoneInfo.put("type", zone.getType());
                        allZones.add(zoneInfo);
                    }

                    // 检查是否还有更多页面
                    hasMore = resp.getZones().length == limit;
                    offset += limit;
                } else {
                    hasMore = false;
                }
            }

            log.info("获取EdgeOne Zone列表完成，共 {} 个域名", allZones.size());
            return allZones;

        } catch (TencentCloudSDKException e) {
            log.warn("获取EdgeOne Zone列表失败: {}", e.getMessage());
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        } catch (Exception e) {
            log.warn("获取EdgeOne Zone列表失败: {}", e.getMessage());
            throw new RuntimeException("获取Zone列表失败: " + e.getMessage());
        }
    }

    /**
     * 同步所有域名的DNS记录到数据库
     */
    @Transactional
    public Map<String, Integer> syncAllDomainsRecords() {
        log.info("开始同步所有域名的EdgeOne DNS记录");

        Map<String, Integer> syncResults = new HashMap<>();

        try {
            // 先获取所有Zone列表
            List<Map<String, Object>> zones = listAllZones();

            // 遍历每个Zone同步DNS记录
            for (Map<String, Object> zone : zones) {
                String zoneId = (String) zone.get("id");
                String zoneName = (String) zone.get("name");

                log.info("同步域名 {} 的EdgeOne DNS记录", zoneName);

                try {
                    int syncCount = syncAllDnsRecords(zoneId, zoneName);
                    syncResults.put(zoneName, syncCount);
                    log.info("域名 {} 同步完成，共处理 {} 条记录", zoneName, syncCount);
                } catch (Exception e) {
                    log.error("同步域名 {} 的DNS记录失败: {}", zoneName, e.getMessage());
                    syncResults.put(zoneName, -1); // -1 表示同步失败
                }
            }

            log.info("所有域名EdgeOne DNS记录同步完成");
            return syncResults;

        } catch (Exception e) {
            log.error("同步所有域名EdgeOne DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("同步所有域名DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 从EdgeOne记录创建DnsRecord实体
     */
    private DnsRecord createDnsRecordFromEdgeOne(Map<String, Object> eoRecord, String zoneId, String domainName,int defaultType) {
        DnsRecord dnsRecord = new DnsRecord();

        dnsRecord.setProviderType(ProviderType.TENCENT);
        dnsRecord.setProviderRecordId((String) eoRecord.get("id"));
        dnsRecord.setZoneId(zoneId);
        dnsRecord.setDomainName(domainName);

        // 判断是DNS记录还是加速域名
        if (defaultType == 2 ) {
            // 这是加速域名
            String accelerationDomain = (String) eoRecord.get("domainName");
            dnsRecord.setRecordName(accelerationDomain);
            dnsRecord.setRecordType(RecordType.SP_DOMAIN);
            dnsRecord.setType(defaultType);
            // CNAME作为记录值
            String cname = (String) eoRecord.get("cname");
            dnsRecord.setRecordValue(cname != null ? cname : "");
            dnsRecord.setDomainName(accelerationDomain);
            // 状态处理
            String status = (String) eoRecord.get("status");
            dnsRecord.setStatus("online".equals(status) ? RecordStatus.ACTIVE : RecordStatus.INACTIVE);

            // 将协议信息等存储到extraData
            Map<String, Object> extraData = new HashMap<>();
            extraData.put("status", status);
            extraData.put("originProtocol", eoRecord.get("originProtocol"));
            try {
                dnsRecord.setExtraData(JSON.toJSONString(extraData));
            } catch (Exception e) {
                dnsRecord.setExtraData("{}");
            }
            dnsRecord.setRemark("EdgeOne加速域名");
        } else {
            // 这是DNS记录 - 原有逻辑
            String fullName = (String) eoRecord.get("name");
            String recordName = extractRecordName(fullName, domainName);
            dnsRecord.setRecordName(recordName);

            String type = (String) eoRecord.get("type");
            dnsRecord.setRecordType(requireDnsType(type));

            dnsRecord.setRecordValue((String) eoRecord.get("content"));
            dnsRecord.setTtl((Integer) eoRecord.get("ttl"));
            dnsRecord.setPriority((Integer) eoRecord.get("priority"));
            dnsRecord.setWeight((Integer) eoRecord.get("weight"));
            dnsRecord.setStatus(RecordStatus.ACTIVE);
            dnsRecord.setType(defaultType);
        }

        dnsRecord.setLastSyncTime(LocalDateTime.now());
        return dnsRecord;
    }

    /**
     * 从EdgeOne记录更新DnsRecord实体
     */
    private void updateDnsRecordFromEdgeOne(DnsRecord dnsRecord, Map<String, Object> eoRecord,int type) {
        if (type == 2) {
            // 更新加速域名
            dnsRecord.setRecordName((String) eoRecord.get("domainName"));
            dnsRecord.setDomainName((String) eoRecord.get("domainName"));
            String cname = (String) eoRecord.get("cname");
            dnsRecord.setRecordValue(cname != null ? cname : "");

            String status = (String) eoRecord.get("status");
            dnsRecord.setStatus("online".equals(status) ? RecordStatus.ACTIVE : RecordStatus.INACTIVE);

            // 更新extraData
            Map<String, Object> extraData = new HashMap<>();
            extraData.put("status", status);
            extraData.put("originProtocol", eoRecord.get("originProtocol"));
            try {
                dnsRecord.setExtraData(JSON.toJSONString(extraData));
            } catch (Exception e) {
                // 忽略序列化错误
            }
        } else {
            // 更新DNS记录 - 原有逻辑
            dnsRecord.setRecordName(extractRecordName((String) eoRecord.get("name"), dnsRecord.getDomainName()));
            dnsRecord.setRecordType(requireDnsType((String) eoRecord.get("type")));
            dnsRecord.setRecordValue((String) eoRecord.get("content"));
            dnsRecord.setTtl((Integer) eoRecord.get("ttl"));
            dnsRecord.setPriority((Integer) eoRecord.get("priority"));
            dnsRecord.setWeight((Integer) eoRecord.get("weight"));
            dnsRecord.setStatus(RecordStatus.ACTIVE);
        }

        dnsRecord.setType(type);
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
     * 添加DNS记录
     */
    @Transactional
    public boolean addDnsRecord(String zoneId, String type, String name, String content, Integer ttl, Integer priority) {
        log.info("开始添加EdgeOne DNS记录，zoneId: {}, type: {}, name: {}, content: {}", zoneId, type, name, content);

        try {
            requireEdgeOneId(zoneId);
            requireDnsType(type);
            if (StringUtils.isBlank(name) || StringUtils.isBlank(content) || (ttl != null && ttl < 1)
                    || (priority != null && (priority < 0 || priority > 65535))) {
                throw new IllegalArgumentException("DNS名称、记录值、TTL或优先级无效");
            }
            TeoClient client = createTeoClient();

            CreateDnsRecordRequest req = new CreateDnsRecordRequest();
            req.setZoneId(zoneId);
            // CreateDnsRecordRequest is flat; a detached DnsRecord array is never serialized.
            req.setType(type);
            req.setName(name);
            req.setContent(content);
            req.setTTL(ttl != null ? ttl.longValue() : 300L);

            // 设置优先级（仅MX记录需要）
            if ("MX".equals(type) && priority != null) {
                req.setPriority(priority.longValue());
            }

            CreateDnsRecordResponse resp = client.CreateDnsRecord(req);
            if (resp != null && StringUtils.isNotBlank(resp.getRequestId())
                    && StringUtils.isNotBlank(resp.getRecordId())) {
                requireEdgeOneId(resp.getRecordId());
                log.info("添加EdgeOne DNS记录成功: {} -> {}", name, content);
                return true;
            }

            return false;

        } catch (TencentCloudSDKException e) {
            log.error("添加EdgeOne DNS记录失败: {}", e.getMessage());
            throw new RuntimeException("添加DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("添加EdgeOne DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("添加DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 更新DNS记录
     */
    @Transactional
    public boolean updateDnsRecord(String recordId, String content, String recordType, String recordName,
                                   Integer ttl, String zoneId, Integer priority) {
        log.info("开始更新EdgeOne DNS记录，recordId: {}", recordId);

        try {
            if (StringUtils.isBlank(content) || (ttl != null && ttl < 1)
                    || (priority != null && (priority < 0 || priority > 65535))) {
                throw new IllegalArgumentException("DNS记录值、TTL或优先级无效");
            }
            String resolvedZone = resolveDnsZone(recordId, zoneId);
            DnsRecord cached = findCachedRecord(resolvedZone, recordId, 1);
            com.tencentcloudapi.teo.v20220901.models.DnsRecord original = requireCloudDnsRecord(resolvedZone, recordId);
            requireDnsType(original.getType());
            if (!original.getType().equals(recordType) || !original.getName().equals(recordName)) {
                throw new IllegalStateException("云端DNS记录名称或类型已变化，请刷新后重试");
            }
            String domainName = requireZoneName(resolvedZone, null);
            TeoClient client = createTeoClient();

            ModifyDnsRecordsRequest req = new ModifyDnsRecordsRequest();
            req.setZoneId(resolvedZone);

            // 构建DNS记录对象
            com.tencentcloudapi.teo.v20220901.models.DnsRecord[] dnsRecords =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord[1];

            // Preserve current Location, Weight, Status and other record fields. Response
            // timestamps are read-only; this API has no atomic compare-and-set contract.
            com.tencentcloudapi.teo.v20220901.models.DnsRecord modifyRecord =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord(original);
            modifyRecord.setCreatedOn(null);
            modifyRecord.setModifiedOn(null);
            modifyRecord.setContent(content);
            if (ttl != null) modifyRecord.setTTL(ttl.longValue());

            // 设置优先级（仅MX记录需要）
            if ("MX".equals(recordType) && priority != null) {
                modifyRecord.setPriority(priority.longValue());
            }

            dnsRecords[0] = modifyRecord;
            req.setDnsRecords(dnsRecords);

            ModifyDnsRecordsResponse resp = client.ModifyDnsRecords(req);

            if (resp != null && StringUtils.isNotBlank(resp.getRequestId())) {
                Map<String, Object> accepted = dnsRecordInfo(modifyRecord, resolvedZone);
                if (cached == null) {
                    cached = createDnsRecordFromEdgeOne(accepted, resolvedZone, domainName, 1);
                } else {
                    cached.setDomainName(domainName);
                    updateDnsRecordFromEdgeOne(cached, accepted, 1);
                }
                cached.setRemark("EdgeOne已接受更新，最终云端状态请刷新核对");
                dnsRecordRepository.save(cached);
                log.info("EdgeOne已接受DNS记录更新，recordId: {}", recordId);
                return true;
            }

            return false;

        } catch (TencentCloudSDKException e) {
            log.error("更新EdgeOne DNS记录失败: {}", e.getMessage());
            throw new RuntimeException("更新DNS记录失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("更新EdgeOne DNS记录失败: {}", e.getMessage(), e);
            throw new RuntimeException("更新DNS记录失败: " + e.getMessage());
        }
    }

    /**
     * 获取加速域名列表
     */
    public List<Map<String, Object>> listAccelerationDomains(String zoneId) {
        log.debug("开始获取EdgeOne加速域名，zoneId: {}", zoneId);

        try {
            requireEdgeOneId(zoneId);
            TeoClient client = createTeoClient();
            List<Map<String, Object>> domains = new ArrayList<>();
            Set<String> ids = new HashSet<>();
            Long expectedTotal = null;
            long limit = 100L;
            for (long offset = 0L; ; offset += limit) {
                DescribeAccelerationDomainsRequest req = new DescribeAccelerationDomainsRequest();
                req.setZoneId(zoneId);
                req.setOffset(offset);
                req.setLimit(limit);
                DescribeAccelerationDomainsResponse resp = client.DescribeAccelerationDomains(req);
                if (resp == null) throw new IllegalStateException("EdgeOne未返回加速域名列表");
                AccelerationDomain[] page = resp.getAccelerationDomains();
                int count = page == null ? 0 : page.length;
                long total = validatePage(resp.getTotalCount(), offset, count, limit, expectedTotal);
                expectedTotal = total;
                if (page != null) for (AccelerationDomain domain : page) {
                    if (domain == null || !zoneId.equals(domain.getZoneId())) {
                        throw new IllegalStateException("EdgeOne加速域名不属于当前区域");
                    }
                    String domainName = requiredText(domain.getDomainName(), "domainName");
                    String id = zoneId + "_" + domainName;
                    if (!ids.add(id)) throw new IllegalStateException("EdgeOne加速域名分页包含重复记录");
                    Map<String, Object> domainInfo = new HashMap<>();
                    domainInfo.put("id", id);
                    domainInfo.put("zoneId", zoneId);
                    domainInfo.put("domainName", domainName);
                    domainInfo.put("status", domain.getDomainStatus());
                    domainInfo.put("cname", domain.getCname());
                    domainInfo.put("originProtocol", domain.getOriginProtocol());
                    // Origin configuration cannot prove client-facing HTTP/HTTPS availability.
                    domainInfo.put("http", null);
                    domainInfo.put("https", null);
                    domains.add(domainInfo);
                }
                if (offset + count >= total) break;
            }

            log.debug("获取EdgeOne加速域名成功，共 {} 个", domains.size());
            return domains;

        } catch (TencentCloudSDKException e) {
            log.error("获取EdgeOne加速域名失败: {}", e.getMessage());
            throw new RuntimeException("获取加速域名失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("获取EdgeOne加速域名失败: {}", e.getMessage(), e);
            throw new RuntimeException("获取加速域名失败: " + e.getMessage());
        }
    }


    /**
     * 删除加速域名
     */
    @Transactional
    public boolean deleteAccelerationDomain(String domainId) {
        return deleteAccelerationDomain(domainId, null, null);
    }

    @Transactional
    public boolean deleteAccelerationDomain(String domainId, String zoneId, String domainName) {
        log.info("开始删除EdgeOne加速域名，domainId: {}", domainId);

        try {
            if (StringUtils.isBlank(domainId)) throw new IllegalArgumentException("加速域名标识不能为空");
            if (StringUtils.isBlank(zoneId) && StringUtils.isBlank(domainName)) {
                DnsRecord match = null;
                for (DnsRecord record : dnsRecordRepository.findByProviderType(ProviderType.TENCENT)) {
                    if (!matchesCacheType(record, 2) || !domainId.equals(record.getProviderRecordId())) continue;
                    if (match != null) throw new IllegalStateException("加速域名缓存不唯一，请明确指定区域和域名");
                    match = record;
                }
                if (match == null) throw new IllegalArgumentException("未找到加速域名缓存，请指定区域和域名");
                zoneId = match.getZoneId();
                domainName = match.getRecordName();
            }
            requireEdgeOneId(zoneId);
            requiredText(domainName, "domainName");
            if (!domainId.equals(zoneId + "_" + domainName)) {
                throw new IllegalArgumentException("加速域名标识与当前区域或域名不匹配");
            }
            DnsRecord cached = findCachedRecord(zoneId, domainId, 2);
            boolean found = false;
            for (Map<String, Object> domain : listAccelerationDomains(zoneId)) {
                if (domainId.equals(domain.get("id")) && domainName.equals(domain.get("domainName"))) {
                    found = true;
                    break;
                }
            }
            if (!found) throw new IllegalArgumentException("当前区域未找到此加速域名，请刷新列表");
            TeoClient client = createTeoClient();

            DeleteAccelerationDomainsRequest req = new DeleteAccelerationDomainsRequest();
            req.setZoneId(zoneId);
            req.setDomainNames(new String[]{domainName});

            DeleteAccelerationDomainsResponse resp = client.DeleteAccelerationDomains(req);

            if (resp != null && StringUtils.isNotBlank(resp.getRequestId())) {
                if (cached != null) {
                    cached.setStatus(RecordStatus.INACTIVE);
                    cached.setRemark("EdgeOne已接受加速域名删除，最终状态请刷新核对");
                    dnsRecordRepository.save(cached);
                }
                log.info("EdgeOne已接受加速域名删除: {}", domainId);
                return true;
            }

            return false;

        } catch (TencentCloudSDKException e) {
            log.error("删除EdgeOne加速域名失败: {}", e.getMessage());
            throw new RuntimeException("删除加速域名失败: " + e.getMessage());
        } catch (Exception e) {
            log.error("删除EdgeOne加速域名失败: {}", e.getMessage(), e);
            throw new RuntimeException("删除加速域名失败: " + e.getMessage());
        }
    }

}
