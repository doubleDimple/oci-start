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

    /**
     * 获取DNS记录
     */
    public List<Map<String, Object>> listDnsRecords(String zoneId) {
        log.debug("开始获取EdgeOne DNS记录，zoneId: {}", zoneId);

        try {
            TeoClient client = createTeoClient();

            //查询dns记录
            DescribeDnsRecordsRequest req = new DescribeDnsRecordsRequest();
            req.setZoneId(zoneId);
            req.setLimit(200L);
            DescribeDnsRecordsResponse resp = client.DescribeDnsRecords(req);

            List<Map<String, Object>> records = new ArrayList<>();

            if (resp.getDnsRecords() != null && resp.getDnsRecords().length > 0) {
                for (com.tencentcloudapi.teo.v20220901.models.DnsRecord record : resp.getDnsRecords()) {
                    Map<String, Object> recordInfo = new HashMap<>();
                    recordInfo.put("id", record.getRecordId());
                    recordInfo.put("type", record.getType());
                    recordInfo.put("name", record.getName());
                    recordInfo.put("content", record.getContent());
                    recordInfo.put("ttl", record.getTTL());
                    recordInfo.put("priority", record.getPriority());
                    recordInfo.put("weight", record.getWeight());
                    records.add(recordInfo);
                }
            }

            log.info("获取EdgeOne DNS记录成功，共 {} 条", records.size());
            return records;

        } catch (TencentCloudSDKException e) {
            log.error("获取EdgeOne DNS记录失败: {}", e.getMessage());
            throw new RuntimeException("获取DNS记录失败: " + e.getMessage());
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
            // 获取EdgeOne的所有DNS记录
            List<Map<String, Object>> edgeOneRecords = listDnsRecords(zoneId);

            // 获取数据库中已存在的记录
            List<DnsRecord> existingRecords = dnsRecordRepository.findByZoneIdAndProviderType(zoneId,
                    ProviderType.TENCENT);

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
            // 获取EdgeOne的所有加速域名
            List<Map<String, Object>> edgeOneDomains = listAccelerationDomains(zoneId);

            // 获取数据库中已存在的加速域名记录 (使用 ACCELERATION_DOMAIN 类型标识)
            List<DnsRecord> existingDomains = dnsRecordRepository.findByZoneIdAndProviderTypeAndRecordType(
                    zoneId, ProviderType.TENCENT, RecordType.SP_DOMAIN);

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
        log.info("开始删除EdgeOne DNS记录，recordId: {}", recordId);

        try {
            // 从数据库查找记录
            Optional<DnsRecord> optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
            if (!optionalRecord.isPresent()) {
                throw new IllegalArgumentException("未找到DNS记录: " + recordId);
            }

            DnsRecord dnsRecord = optionalRecord.get();
            TeoClient client = createTeoClient();

            // 调用EdgeOne API删除记录
            DeleteDnsRecordsRequest req = new DeleteDnsRecordsRequest();
            req.setZoneId(dnsRecord.getZoneId());
            req.setRecordIds(new String[]{recordId});

            DeleteDnsRecordsResponse resp = client.DeleteDnsRecords(req);

            if (resp != null) {
                // 删除成功，更新数据库记录状态
                dnsRecord.setStatus(RecordStatus.INACTIVE);
                dnsRecord.setRemark("已删除");
                dnsRecord.setUpdateTime(LocalDateTime.now());
                dnsRecordRepository.save(dnsRecord);

                log.info("删除EdgeOne DNS记录成功: {} -> {}", dnsRecord.getRecordName(), dnsRecord.getRecordValue());
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

            DescribeZonesRequest req = new DescribeZonesRequest();
            req.setLimit(100L); // 设置单次查询限制

            DescribeZonesResponse resp = client.DescribeZones(req);

            List<Map<String, Object>> zones = new ArrayList<>();

            if (resp.getZones() != null) {
                for (com.tencentcloudapi.teo.v20220901.models.Zone zone : resp.getZones()) {
                    Map<String, Object> zoneInfo = new HashMap<>();
                    zoneInfo.put("id", zone.getZoneId());
                    zoneInfo.put("name", zone.getZoneName());
                    zoneInfo.put("status", zone.getStatus());
                    zoneInfo.put("type", zone.getType());
                    zones.add(zoneInfo);
                }
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
            extraData.put("http", eoRecord.get("http"));
            extraData.put("https", eoRecord.get("https"));
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
            dnsRecord.setRecordType(RecordType.valueOf(type));

            dnsRecord.setRecordValue((String) eoRecord.get("content"));
            dnsRecord.setTtl((Integer) eoRecord.get("ttl"));
            dnsRecord.setPriority((Integer) eoRecord.get("priority"));
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
            String cname = (String) eoRecord.get("cname");
            dnsRecord.setRecordValue(cname != null ? cname : "");

            String status = (String) eoRecord.get("status");
            dnsRecord.setStatus("online".equals(status) ? RecordStatus.ACTIVE : RecordStatus.INACTIVE);

            // 更新extraData
            Map<String, Object> extraData = new HashMap<>();
            extraData.put("status", status);
            extraData.put("http", eoRecord.get("http"));
            extraData.put("https", eoRecord.get("https"));
            try {
                dnsRecord.setExtraData(JSON.toJSONString(extraData));
            } catch (Exception e) {
                // 忽略序列化错误
            }
        } else {
            // 更新DNS记录 - 原有逻辑
            dnsRecord.setRecordValue((String) eoRecord.get("content"));
            dnsRecord.setTtl((Integer) eoRecord.get("ttl"));
            dnsRecord.setPriority((Integer) eoRecord.get("priority"));
            dnsRecord.setStatus(RecordStatus.ACTIVE);
        }

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
            TeoClient client = createTeoClient();

            CreateDnsRecordRequest req = new CreateDnsRecordRequest();
            req.setZoneId(zoneId);

            // 构建DNS记录对象
            com.tencentcloudapi.teo.v20220901.models.DnsRecord[] dnsRecords =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord[1];

            com.tencentcloudapi.teo.v20220901.models.DnsRecord dnsRecord =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord();

            dnsRecord.setType(type);
            dnsRecord.setName(name);
            dnsRecord.setContent(content);
            dnsRecord.setTTL(ttl != null ? ttl.longValue() : 300L);

            // 设置优先级（仅MX记录需要）
            if ("MX".equals(type) && priority != null) {
                dnsRecord.setPriority(priority.longValue());
            }

            dnsRecords[0] = dnsRecord;

            CreateDnsRecordResponse resp = client.CreateDnsRecord(req);
            if (resp != null && resp.getRecordId() != null) {
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
        log.info("开始更新EdgeOne DNS记录，recordId: {}, content: {}", recordId, content);

        try {
            TeoClient client = createTeoClient();

            ModifyDnsRecordsRequest req = new ModifyDnsRecordsRequest();
            req.setZoneId(zoneId);

            // 构建DNS记录对象
            com.tencentcloudapi.teo.v20220901.models.DnsRecord[] dnsRecords =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord[1];

            com.tencentcloudapi.teo.v20220901.models.DnsRecord modifyRecord =
                    new com.tencentcloudapi.teo.v20220901.models.DnsRecord();

            modifyRecord.setRecordId(recordId);
            modifyRecord.setName(recordName);
            modifyRecord.setType(recordType);
            modifyRecord.setContent(content);
            modifyRecord.setTTL(ttl != null ? ttl.longValue() : 300L);

            // 设置优先级（仅MX记录需要）
            if ("MX".equals(recordType) && priority != null) {
                modifyRecord.setPriority(priority.longValue());
            }

            dnsRecords[0] = modifyRecord;
            req.setDnsRecords(dnsRecords);

            ModifyDnsRecordsResponse resp = client.ModifyDnsRecords(req);

            if (resp != null) {
                // 更新数据库中的记录
                Optional<DnsRecord> optionalRecord = dnsRecordRepository.findByProviderRecordId(recordId);
                if (optionalRecord.isPresent()) {
                    DnsRecord dnsRecord = optionalRecord.get();
                    dnsRecord.setRecordValue(content);
                    dnsRecord.setTtl(ttl);
                    dnsRecord.setPriority(priority);
                    dnsRecord.setUpdateTime(LocalDateTime.now());
                    dnsRecord.setLastSyncTime(LocalDateTime.now());
                    dnsRecordRepository.save(dnsRecord);
                }

                log.info("更新EdgeOne DNS记录成功: {} -> {}", recordName, content);
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
            TeoClient client = createTeoClient();

            DescribeAccelerationDomainsRequest req = new DescribeAccelerationDomainsRequest();
            req.setZoneId(zoneId);
            req.setLimit(100L);

            DescribeAccelerationDomainsResponse resp = client.DescribeAccelerationDomains(req);

            List<Map<String, Object>> domains = new ArrayList<>();

            if (resp.getAccelerationDomains() != null) {
                for (AccelerationDomain domain : resp.getAccelerationDomains()) {
                    Map<String, Object> domainInfo = new HashMap<>();
                    domainInfo.put("id", domain.getZoneId()+"_"+domain.getDomainName());
                    domainInfo.put("domainName", domain.getDomainName());
                    domainInfo.put("status", domain.getDomainStatus());
                    domainInfo.put("cname", domain.getCname());

                    // 获取协议信息
                    boolean http = false;
                    boolean https = false;

                    if (domain.getOriginDetail() != null) {
                        // 这里需要根据实际的API响应结构来解析协议信息
                        // 示例代码，实际需要根据腾讯云API文档调整
                        http = true; // 默认支持HTTP
                        https = true; // 默认支持HTTPS
                    }

                    domainInfo.put("http", http);
                    domainInfo.put("https", https);

                    domains.add(domainInfo);
                }
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
        log.info("开始删除EdgeOne加速域名，domainId: {}", domainId);

        try {
            TeoClient client = createTeoClient();

            DeleteAccelerationDomainsRequest req = new DeleteAccelerationDomainsRequest();
            req.setZoneId(domainId);

            DeleteAccelerationDomainsResponse resp = client.DeleteAccelerationDomains(req);

            if (resp != null) {
                log.info("删除EdgeOne加速域名成功: {}", domainId);
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
