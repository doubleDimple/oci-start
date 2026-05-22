package com.doubledimple.ociserver.service.impl;

import com.doubledimple.ociserver.pojo.response.OciIpRange;
import com.doubledimple.ociserver.service.OciIpRangeService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.cache.CacheConstants.ALL_IP_RANGES_KEY;
import static com.doubledimple.ocicommon.cache.CacheConstants.OCI_IP_RANGES_CACHE;

/**
 * @author doubleDimple
 * @date 2024:11:16日 20:04
 */
@Service
@Slf4j
public class OciIpRangeServiceImpl implements OciIpRangeService {

    @Resource
    private RestTemplate restTemplate;

    @Resource
    private CacheManager cacheManager;

    private static final String OCI_IP_URL = "https://docs.oracle.com/en-us/iaas/tools/public_ip_ranges.json";

    /**
     * 从远程API获取并更新IP范围数据，更新数据库和缓存
     */
    @Override
    @Transactional
    public List<OciIpRange> updateIpRangesFromRemote() {
        log.info("从远程API获取OCI IP范围数据");
        try {
            String jsonResponse = restTemplate.getForObject(OCI_IP_URL, String.class);
            List<OciIpRange> ipRanges = parseIpRanges(jsonResponse);

            // 更新缓存
            //updateCache(ipRanges);

            return ipRanges;
        } catch (Exception e) {
            log.error("获取远程API IP范围数据失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 解析JSON响应为IP范围对象列表
     */
    private List<OciIpRange> parseIpRanges(String jsonResponse) throws JsonProcessingException {
        ObjectMapper mapper = new ObjectMapper();
        JsonNode root = mapper.readTree(jsonResponse);
        List<OciIpRange> ipRanges = new ArrayList<>();

        // 遍历regions数组
        root.get("regions").forEach(region -> {
            String regionName = region.get("region").asText();

            // 只处理包含"OCI"标签的记录
            region.get("cidrs").forEach(cidr -> {
                if (cidr.has("tags") && cidr.get("tags").toString().contains("OCI")) {
                    OciIpRange ipRange = new OciIpRange();
                    ipRange.setRegion(regionName);
                    ipRange.setCidr(cidr.get("cidr").asText());
                    ipRange.setLastUpdated(LocalDateTime.now());
                    ipRanges.add(ipRange);
                }
            });
        });

        return ipRanges;
    }

    /**
     * 获取所有IP范围，三级查询：
     * 1. 首先从缓存获取
     * 2. 缓存没有，从数据库获取并更新缓存
     * 3. 数据库没有，从远程API获取，更新数据库和缓存
     */
    @Override
    public List<OciIpRange> getAllIpRanges() {
        // 1. 尝试从缓存获取
       /* List<OciIpRange> cachedIpRanges = getFromCache();
        if (cachedIpRanges != null && !cachedIpRanges.isEmpty()) {
            log.debug("从缓存获取到OCI IP范围数据，共{}条记录", cachedIpRanges.size());
            return cachedIpRanges;
        }*/

        // 2. 缓存没有，从数据库获取
        /*List<OciIpRange> dbIpRanges = repository.findAll();
        if (!dbIpRanges.isEmpty()) {
            log.debug("从数据库获取到OCI IP范围数据，共{}条记录", dbIpRanges.size());
            // 更新缓存
            updateCache(dbIpRanges);
            return dbIpRanges;
        }*/

        // 3. 数据库没有，从远程API获取
        log.info("缓存和数据库都没有OCI IP范围数据，从远程API获取");
        return updateIpRangesFromRemote();
    }

    /**
     * 从缓存获取数据
     */
    private List<OciIpRange> getFromCache() {
        Cache cache = cacheManager.getCache(OCI_IP_RANGES_CACHE);
        if (cache != null) {
            Cache.ValueWrapper valueWrapper = cache.get(ALL_IP_RANGES_KEY);
            if (valueWrapper != null) {
                return (List<OciIpRange>) valueWrapper.get();
            }
        }
        return null;
    }

    /**
     * 更新缓存
     */
    /*private void updateCache(List<OciIpRange> ipRanges) {
        Cache cache = cacheManager.getCache(OCI_IP_RANGES_CACHE);
        if (cache != null) {
            cache.put(ALL_IP_RANGES_KEY, ipRanges);
            log.debug("已更新OCI IP范围数据到缓存");
        }
    }*/

    /**
     * 清除缓存
     */
    @Override
    public void clearCache() {
        Cache cache = cacheManager.getCache(OCI_IP_RANGES_CACHE);
        if (cache != null) {
            cache.clear();
            log.info("已清除OCI IP范围缓存");
        }
    }

    @Override
    public List<String> findCidrsByRegionAndCidrIn(String region, List<String> cidrList) {
        try {
            List<OciIpRange> allIpRanges = getAllIpRanges();
            if (!CollectionUtils.isEmpty(allIpRanges )){
                return allIpRanges.stream()
                        .filter(ipRange -> region.equals(ipRange.getRegion())) // 匹配 region
                        .map(OciIpRange::getCidr) // 获取 cidr
                        .filter(cidrList::contains) // 筛选在 cidrList 里的 cidr
                        .collect(Collectors.toList()); // 收集结果为 List
            }else{
                return new ArrayList<>();
            }
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }
}
