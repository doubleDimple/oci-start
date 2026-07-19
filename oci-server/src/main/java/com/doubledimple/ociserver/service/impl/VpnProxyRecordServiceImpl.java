package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import com.doubledimple.ociserver.service.VpnProxyRecordService;
import com.doubledimple.ociserver.utils.PageUtils;
import com.doubledimple.ociserver.utils.SocksProxyUtils;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import javax.persistence.criteria.Predicate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * VPN 代理：支持父租户绑定（tenantId null = 全局共享）。
 */
@Slf4j
@Service
public class VpnProxyRecordServiceImpl implements VpnProxyRecordService {

    @Resource
    VpnProxyRecordRepository vpnProxyRecordRepository;

    @Resource
    TenantRepository tenantRepository;

    @Override
    public Page<VpnProxyRecord> listPage(VpnProxyRecordRequest request) {
        Specification<VpnProxyRecord> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            if (request.getTenantId() != null) {
                predicates.add(criteriaBuilder.equal(root.get("tenantId"), request.getTenantId()));
            }
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        Page<VpnProxyRecord> page = PageUtils.findWithSpec(vpnProxyRecordRepository, request, spec);
        for (VpnProxyRecord record : page.getContent()) {
            fillTenantName(record);
        }
        return page;
    }

    @Override
    @Transactional
    public void saveOrUpdate(VpnProxyRecordRequest request) {
        LocalDateTime now = LocalDateTime.now();
        VpnProxyRecord record = null;

        if (request.getId() != null) {
            record = vpnProxyRecordRepository.findById(request.getId()).orElse(null);
        }
        if (record == null && StringUtils.isNotBlank(request.getProxyHost())) {
            record = vpnProxyRecordRepository.findTopByProxyHost(request.getProxyHost());
        }
        if (record == null) {
            record = new VpnProxyRecord();
            record.setCreateTime(now);
        }

        record.setProxyType(request.getProxyType());
        record.setProxyHost(request.getProxyHost());
        record.setProxyPort(request.getProxyPort());
        // 用户名：请求显式带了才更新（null 表示未传，保留原值，避免切换强制代理时清空）
        if (request.getProxyUsername() != null) {
            record.setProxyUsername(request.getProxyUsername());
        }
        // 密码：null 未传则保留原密码；空串表示清空
        if (request.getProxyPassword() != null) {
            record.setProxyPassword(request.getProxyPassword());
        }
        if (request.getAvailableStatus() != null) {
            record.setAvailableStatus(request.getAvailableStatus());
        }
        if (request.getForceProxy() != null) {
            record.setForceProxy(request.getForceProxy() == 1 ? 1 : 0);
        } else if (record.getForceProxy() == null) {
            record.setForceProxy(0);
        }
        // null = 全局共享
        record.setTenantId(normalizeTenantId(request.getTenantId()));
        record.setUpdateTime(now);

        VpnProxyRecord saved = vpnProxyRecordRepository.save(record);
        if (saved.getTenantId() != null && saved.getId() != null) {
            vpnProxyRecordRepository.clearTenantBindingExcept(saved.getTenantId(), saved.getId());
        }
    }

    @Override
    public List<VpnProxyRecord> queryListEnable() {
        return vpnProxyRecordRepository.findAllByAvailableStatus(1);
    }

    @Transactional
    @Override
    public void delete(VpnProxyRecordRequest vpnProxyRecordRequest) {
        vpnProxyRecordRepository.deleteById(vpnProxyRecordRequest.getId());
    }

    @Override
    public Map<String, Object> testConnection(Long id) {
        if (id == null) {
            throw new IllegalArgumentException("代理 id 不能为空");
        }
        VpnProxyRecord record = vpnProxyRecordRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("代理不存在: " + id));
        return probeAndPersist(record);
    }

    @Override
    public Map<String, Object> testAll() {
        List<VpnProxyRecord> all = vpnProxyRecordRepository.findAll();
        List<Map<String, Object>> results = new ArrayList<>();
        int successCount = 0;
        int failCount = 0;
        for (VpnProxyRecord record : all) {
            Map<String, Object> one = probeAndPersist(record);
            results.add(one);
            if (Boolean.TRUE.equals(one.get("connected"))) {
                successCount++;
            } else {
                failCount++;
            }
        }
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", all.size());
        summary.put("successCount", successCount);
        summary.put("failCount", failCount);
        summary.put("results", results);
        return summary;
    }

    /**
     * 探测连通性并落库 availableStatus：1=通，0=不通
     */
    private Map<String, Object> probeAndPersist(VpnProxyRecord record) {
        boolean connected = false;
        try {
            connected = SocksProxyUtils.isProxyAvailable(record);
        } catch (Exception e) {
            log.warn("代理连通测试异常 id={} {}:{} -> {}",
                    record.getId(), record.getProxyHost(), record.getProxyPort(), e.getMessage());
        }
        record.setAvailableStatus(connected ? 1 : 0);
        record.setUpdateTime(LocalDateTime.now());
        vpnProxyRecordRepository.save(record);

        Map<String, Object> data = new HashMap<>();
        data.put("id", record.getId());
        data.put("connected", connected);
        data.put("availableStatus", record.getAvailableStatus());
        data.put("proxyHost", record.getProxyHost());
        data.put("proxyPort", record.getProxyPort());
        data.put("proxyType", record.getProxyType());
        return data;
    }

    private void fillTenantName(VpnProxyRecord record) {
        if (record.getTenantId() == null) {
            record.setTenantName(null);
            return;
        }
        Optional<Tenant> opt = tenantRepository.findById(record.getTenantId());
        if (!opt.isPresent()) {
            record.setTenantName("租户#" + record.getTenantId());
            return;
        }
        Tenant t = opt.get();
        String name = StringUtils.isNotBlank(t.getTenancyName()) ? t.getTenancyName() : t.getUserName();
        if (StringUtils.isBlank(name)) {
            name = "租户#" + record.getTenantId();
        }
        record.setTenantName(name);
    }

    /**
     * 配置绑定时只存「根父租户」id，子区域统一向上归一。
     */
    private Long normalizeTenantId(Long tenantId) {
        if (tenantId == null || tenantId <= 0) {
            return null;
        }
        Long current = tenantId;
        for (int i = 0; i < 8; i++) {
            Optional<Tenant> opt = tenantRepository.findById(current);
            if (!opt.isPresent()) {
                return current;
            }
            Tenant t = opt.get();
            Long parenId = t.getParenId();
            if (parenId == null || parenId == 0L || parenId.equals(current)) {
                return t.getId();
            }
            current = parenId;
        }
        return current;
    }
}
