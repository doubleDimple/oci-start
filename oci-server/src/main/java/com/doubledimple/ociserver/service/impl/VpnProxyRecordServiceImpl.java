package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.entity.VpnProxyTenantBind;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.dao.repository.VpnProxyTenantBindRepository;
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
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * VPN 代理：支持多父租户绑定（tenantIds 空 = 全局共享）。
 */
@Slf4j
@Service
public class VpnProxyRecordServiceImpl implements VpnProxyRecordService {

    @Resource
    VpnProxyRecordRepository vpnProxyRecordRepository;

    @Resource
    VpnProxyTenantBindRepository vpnProxyTenantBindRepository;

    @Resource
    TenantRepository tenantRepository;

    @Override
    public Page<VpnProxyRecord> listPage(VpnProxyRecordRequest request) {
        Specification<VpnProxyRecord> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            // 按租户过滤：命中 bind 表或兼容旧 tenant_id 列
            if (request.getTenantId() != null) {
                Long tid = request.getTenantId();
                List<VpnProxyTenantBind> binds = vpnProxyTenantBindRepository.findByTenantIdIn(Collections.singletonList(tid));
                List<Long> proxyIds = binds.stream().map(VpnProxyTenantBind::getProxyId).collect(Collectors.toList());
                if (proxyIds.isEmpty()) {
                    predicates.add(criteriaBuilder.equal(root.get("tenantId"), tid));
                } else {
                    predicates.add(criteriaBuilder.or(
                            root.get("id").in(proxyIds),
                            criteriaBuilder.equal(root.get("tenantId"), tid)
                    ));
                }
            }
            return criteriaBuilder.and(predicates.toArray(new Predicate[0]));
        };

        Page<VpnProxyRecord> page = PageUtils.findWithSpec(vpnProxyRecordRepository, request, spec);
        fillBindings(page.getContent());
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
        // 自定义名称：null 未传保留；空串清空
        if (request.getCustomName() != null) {
            String cn = StringUtils.trimToNull(request.getCustomName());
            record.setCustomName(cn);
        }
        record.setUpdateTime(now);

        List<Long> normalizedTenantIds = resolveTenantIdsFromRequest(request);
        // 兼容旧列：首个租户写入 tenant_id，无则 null
        record.setTenantId(normalizedTenantIds.isEmpty() ? null : normalizedTenantIds.get(0));

        VpnProxyRecord saved = vpnProxyRecordRepository.save(record);
        replaceBinds(saved.getId(), normalizedTenantIds);
    }

    @Override
    public List<VpnProxyRecord> queryListEnable() {
        List<VpnProxyRecord> list = vpnProxyRecordRepository.findAllByAvailableStatus(1);
        fillBindings(list);
        return list;
    }

    @Transactional
    @Override
    public void delete(VpnProxyRecordRequest vpnProxyRecordRequest) {
        Long id = vpnProxyRecordRequest.getId();
        if (id != null) {
            vpnProxyTenantBindRepository.deleteByProxyId(id);
            vpnProxyRecordRepository.deleteById(id);
        }
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

    @Override
    @Transactional
    public void bindTenant(Long tenantId, Long proxyId) {
        Long rootId = normalizeTenantId(tenantId);
        if (rootId == null) {
            throw new IllegalArgumentException("租户 id 无效");
        }
        // 解绑
        if (proxyId == null || proxyId <= 0) {
            unbindTenantEverywhere(rootId);
            return;
        }
        VpnProxyRecord proxy = vpnProxyRecordRepository.findById(proxyId)
                .orElseThrow(() -> new IllegalArgumentException("代理不存在: " + proxyId));
        unbindTenantEverywhere(rootId);

        VpnProxyTenantBind bind = new VpnProxyTenantBind();
        bind.setProxyId(proxy.getId());
        bind.setTenantId(rootId);
        vpnProxyTenantBindRepository.save(bind);

        // 同步旧列：若该代理 tenant_id 为空则写入首个
        if (proxy.getTenantId() == null) {
            proxy.setTenantId(rootId);
            proxy.setUpdateTime(LocalDateTime.now());
            vpnProxyRecordRepository.save(proxy);
        }
    }

    @Override
    public VpnProxyRecord findBoundByTenantId(Long tenantId) {
        Long rootId = normalizeTenantId(tenantId);
        if (rootId == null) {
            return null;
        }
        VpnProxyRecord record = vpnProxyRecordRepository.findTopByTenantId(rootId);
        if (record != null) {
            fillBindings(Collections.singletonList(record));
        }
        return record;
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

    /**
     * 批量填充 tenantIds / tenantName；并把旧 tenant_id 列迁移到 bind 表（懒迁移）。
     */
    private void fillBindings(List<VpnProxyRecord> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        List<Long> proxyIds = records.stream()
                .filter(r -> r != null && r.getId() != null)
                .map(VpnProxyRecord::getId)
                .collect(Collectors.toList());
        if (proxyIds.isEmpty()) {
            return;
        }

        List<VpnProxyTenantBind> allBinds = vpnProxyTenantBindRepository.findByProxyIdIn(proxyIds);
        Map<Long, List<Long>> proxyToTenants = new HashMap<>();
        for (VpnProxyTenantBind b : allBinds) {
            if (b == null || b.getProxyId() == null || b.getTenantId() == null) {
                continue;
            }
            proxyToTenants.computeIfAbsent(b.getProxyId(), k -> new ArrayList<>()).add(b.getTenantId());
        }

        // 懒迁移：旧列有 tenant_id 但 bind 表没有 → 写入 bind
        for (VpnProxyRecord r : records) {
            if (r == null || r.getId() == null) {
                continue;
            }
            List<Long> fromBind = proxyToTenants.get(r.getId());
            if ((fromBind == null || fromBind.isEmpty()) && r.getTenantId() != null) {
                try {
                    // 该租户若已绑到其它代理，以 bind 为准，不覆盖
                    VpnProxyTenantBind existing = vpnProxyTenantBindRepository.findTopByTenantId(r.getTenantId());
                    if (existing == null) {
                        VpnProxyTenantBind nb = new VpnProxyTenantBind();
                        nb.setProxyId(r.getId());
                        nb.setTenantId(r.getTenantId());
                        vpnProxyTenantBindRepository.save(nb);
                        fromBind = new ArrayList<>();
                        fromBind.add(r.getTenantId());
                        proxyToTenants.put(r.getId(), fromBind);
                    } else if (existing.getProxyId().equals(r.getId())) {
                        fromBind = Collections.singletonList(r.getTenantId());
                        proxyToTenants.put(r.getId(), new ArrayList<>(fromBind));
                    }
                } catch (Exception e) {
                    log.debug("懒迁移代理绑定失败 proxyId={}: {}", r.getId(), e.getMessage());
                }
            }
        }

        // 收集租户名
        Set<Long> allTenantIds = new HashSet<>();
        for (List<Long> ids : proxyToTenants.values()) {
            allTenantIds.addAll(ids);
        }
        for (VpnProxyRecord r : records) {
            if (r != null && r.getTenantId() != null) {
                allTenantIds.add(r.getTenantId());
            }
        }
        Map<Long, String> nameMap = loadTenantNames(allTenantIds);

        for (VpnProxyRecord r : records) {
            if (r == null) {
                continue;
            }
            List<Long> ids = proxyToTenants.get(r.getId());
            if (ids == null || ids.isEmpty()) {
                if (r.getTenantId() != null) {
                    ids = Collections.singletonList(r.getTenantId());
                } else {
                    ids = Collections.emptyList();
                }
            }
            // 去重保序
            LinkedHashSet<Long> ordered = new LinkedHashSet<>(ids);
            List<Long> finalIds = new ArrayList<>(ordered);
            r.setTenantIds(finalIds);
            r.setTenantId(finalIds.isEmpty() ? null : finalIds.get(0));
            if (finalIds.isEmpty()) {
                r.setTenantName(null);
            } else {
                List<String> names = new ArrayList<>();
                for (Long tid : finalIds) {
                    String n = nameMap.get(tid);
                    names.add(StringUtils.isNotBlank(n) ? n : ("租户#" + tid));
                }
                r.setTenantName(String.join(", ", names));
            }
        }
    }

    private Map<Long, String> loadTenantNames(Set<Long> tenantIds) {
        Map<Long, String> map = new HashMap<>();
        if (tenantIds == null || tenantIds.isEmpty()) {
            return map;
        }
        for (Long tid : tenantIds) {
            if (tid == null) {
                continue;
            }
            Optional<Tenant> opt = tenantRepository.findById(tid);
            if (!opt.isPresent()) {
                map.put(tid, "租户#" + tid);
                continue;
            }
            Tenant t = opt.get();
            String name = StringUtils.isNotBlank(t.getTenancyName()) ? t.getTenancyName() : t.getUserName();
            if (StringUtils.isBlank(name)) {
                name = "租户#" + tid;
            }
            map.put(tid, name);
        }
        return map;
    }

    /**
     * 解析请求中的租户列表：tenantIds 优先；否则兼容 tenantId 单选。
     */
    private List<Long> resolveTenantIdsFromRequest(VpnProxyRecordRequest request) {
        LinkedHashSet<Long> set = new LinkedHashSet<>();
        if (request.getTenantIds() != null) {
            for (Long id : request.getTenantIds()) {
                Long n = normalizeTenantId(id);
                if (n != null) {
                    set.add(n);
                }
            }
        } else if (request.getTenantId() != null) {
            Long n = normalizeTenantId(request.getTenantId());
            if (n != null) {
                set.add(n);
            }
        }
        return new ArrayList<>(set);
    }

    /**
     * 替换某代理的全部绑定；并保证这些租户从其它代理解绑。
     */
    private void replaceBinds(Long proxyId, List<Long> tenantIds) {
        if (proxyId == null) {
            return;
        }
        List<Long> ids = tenantIds == null ? Collections.emptyList() : tenantIds;
        if (!ids.isEmpty()) {
            vpnProxyTenantBindRepository.deleteByTenantIdInAndProxyIdNot(ids, proxyId);
        }
        vpnProxyTenantBindRepository.deleteByProxyId(proxyId);
        for (Long tid : ids) {
            if (tid == null) {
                continue;
            }
            VpnProxyTenantBind b = new VpnProxyTenantBind();
            b.setProxyId(proxyId);
            b.setTenantId(tid);
            vpnProxyTenantBindRepository.save(b);
        }
        // 清理仍挂在旧 tenant_id 列、但已不在本次绑定里的兼容数据
        // （其它代理的 tenant_id 列由懒迁移 / 下次 save 纠正）
    }

    private void unbindTenantEverywhere(Long tenantId) {
        if (tenantId == null) {
            return;
        }
        vpnProxyTenantBindRepository.deleteByTenantId(tenantId);
        // 兼容旧列：若某代理 tenant_id 等于该租户，清空
        List<VpnProxyRecord> all = vpnProxyRecordRepository.findAll();
        for (VpnProxyRecord r : all) {
            if (r != null && tenantId.equals(r.getTenantId())) {
                // 若 bind 里还有其它租户，把 tenant_id 改成其中一个；否则置空
                List<VpnProxyTenantBind> remains = vpnProxyTenantBindRepository.findByProxyId(r.getId());
                if (remains == null || remains.isEmpty()) {
                    r.setTenantId(null);
                } else {
                    r.setTenantId(remains.get(0).getTenantId());
                }
                r.setUpdateTime(LocalDateTime.now());
                vpnProxyRecordRepository.save(r);
            }
        }
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
