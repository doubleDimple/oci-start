package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.ociserver.pojo.request.VpnProxyRecordRequest;
import com.doubledimple.ociserver.service.VpnProxyRecordService;
import com.doubledimple.ociserver.utils.PageUtils;
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
import java.util.List;
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
        record.setProxyUsername(request.getProxyUsername());
        record.setProxyPassword(request.getProxyPassword());
        if (request.getAvailableStatus() != null) {
            record.setAvailableStatus(request.getAvailableStatus());
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

    private Long normalizeTenantId(Long tenantId) {
        if (tenantId == null || tenantId <= 0) {
            return null;
        }
        // 若误传子区域 ID，归一到父租户
        Optional<Tenant> opt = tenantRepository.findById(tenantId);
        if (!opt.isPresent()) {
            return tenantId;
        }
        Tenant t = opt.get();
        Long parenId = t.getParenId();
        if (parenId == null || parenId == 0L) {
            return t.getId();
        }
        return parenId;
    }
}
