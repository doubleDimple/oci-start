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
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
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
        Long tenantId = request.getTenantId() == null ? null : normalizeTenantId(request.getTenantId());
        Specification<VpnProxyRecord> spec = (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            // 按租户过滤：命中 bind 表或兼容旧 tenant_id 列
            if (tenantId != null) {
                Long tid = tenantId;
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
        validateProxyRequest(request);
        List<Long> normalizedTenantIds = resolveTenantIdsFromRequest(request);
        LocalDateTime now = LocalDateTime.now();
        VpnProxyRecord record = null;

        if (request.getId() != null) {
            record = vpnProxyRecordRepository.findById(request.getId())
                    .orElseThrow(() -> new IllegalArgumentException("代理不存在"));
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
        requireProxyId(id);
        vpnProxyTenantBindRepository.deleteByProxyId(id);
        vpnProxyRecordRepository.deleteById(id);
    }

    @Override
    public String getPassword(Long id) {
        requireProxyId(id);
        String password = vpnProxyRecordRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("代理不存在")).getProxyPassword();
        return password == null || password.isEmpty() ? null : password;
    }

    @Override
    public void updateForce(Long id, Integer forceProxy) {
        requireProxyId(id);
        if (forceProxy == null || (forceProxy != 0 && forceProxy != 1)) {
            throw new IllegalArgumentException("强制代理状态无效");
        }
        if (vpnProxyRecordRepository.updateForce(id, forceProxy, LocalDateTime.now()) != 1) {
            throw new IllegalArgumentException("代理不存在");
        }
    }

    @Override
    public Map<String, Object> testConnection(Long id) {
        requireProxyId(id);
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
        upsertBind(proxy.getId(), rootId);
        syncLegacyTenantIdColumn(Collections.singleton(rootId), proxy.getId());
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
            connected = "HTTP".equalsIgnoreCase(record.getProxyType()) || "HTTPS".equalsIgnoreCase(record.getProxyType())
                    ? probeHttpConnect(record) : SocksProxyUtils.isProxyAvailable(record);
        } catch (Exception e) {
            log.warn("代理连通测试异常 id={}", record.getId());
        }
        int status = connected ? 1 : 0;
        int updated = vpnProxyRecordRepository.updateProbeStatus(record.getId(), record.getProxyType(),
                record.getProxyHost(), record.getProxyPort(), record.getProxyUsername(), record.getProxyPassword(),
                status, LocalDateTime.now());

        Map<String, Object> data = new HashMap<>();
        data.put("id", record.getId());
        data.put("connected", updated == 1 ? connected : null);
        data.put("availableStatus", updated == 1 ? status : null);
        if (updated != 1) data.put("errorKey", "configurationChanged");
        data.put("proxyHost", record.getProxyHost());
        data.put("proxyPort", record.getProxyPort());
        data.put("proxyType", record.getProxyType());
        return data;
    }

    /** C9 keeps the existing CONNECT target and transport; this is not a TLS-to-proxy test. */
    private boolean probeHttpConnect(VpnProxyRecord record) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(record.getProxyHost(), record.getProxyPort()), 3000);
            StringBuilder request = new StringBuilder("CONNECT www.oracle.com:443 HTTP/1.1\r\n")
                    .append("Host: www.oracle.com:443\r\nUser-Agent: ProxyChecker/1.0\r\n")
                    .append("Proxy-Connection: Keep-Alive\r\n");
            if (StringUtils.isNotEmpty(record.getProxyUsername()) && StringUtils.isNotEmpty(record.getProxyPassword())) {
                String auth = record.getProxyUsername() + ":" + record.getProxyPassword();
                request.append("Proxy-Authorization: Basic ")
                        .append(Base64.getEncoder().encodeToString(auth.getBytes(StandardCharsets.UTF_8))).append("\r\n");
            }
            socket.getOutputStream().write(request.append("\r\n").toString().getBytes(StandardCharsets.UTF_8));
            socket.getOutputStream().flush();
            long deadline = System.nanoTime() + 3000000000L;
            InputStream input = socket.getInputStream();
            byte[] line = new byte[512];
            int length = 0;
            while (length < line.length) {
                long remaining = deadline - System.nanoTime();
                if (remaining <= 0) throw new SocketTimeoutException();
                socket.setSoTimeout((int) Math.max(1L, (remaining + 999999L) / 1000000L));
                int value = input.read();
                if (value < 0) return false;
                if (value == '\n') {
                    if (length > 0 && line[length - 1] == '\r') length--;
                    return new String(line, 0, length, StandardCharsets.US_ASCII).matches("HTTP/1\\.[01] 200(?:[ \\t].*)?");
                }
                line[length++] = (byte) value;
            }
            return false;
        } catch (IOException e) {
            return false;
        }
    }

    private void requireProxyId(Long id) {
        if (id == null || id <= 0) throw new IllegalArgumentException("代理 id 无效");
    }

    private void validateProxyRequest(VpnProxyRecordRequest request) {
        if (request == null) throw new IllegalArgumentException("代理配置不能为空");
        if (request.getId() != null) requireProxyId(request.getId());
        String type = StringUtils.trimToEmpty(request.getProxyType()).toUpperCase(Locale.ROOT);
        if (!"HTTP".equals(type) && !"HTTPS".equals(type) && !"SOCKS5".equals(type)) {
            throw new IllegalArgumentException("代理类型无效");
        }
        String host = StringUtils.trimToEmpty(request.getProxyHost());
        Integer port = request.getProxyPort();
        if (host.isEmpty() || host.length() > 128 || port == null || port < 1 || port > 65535) {
            throw new IllegalArgumentException("代理主机或端口无效");
        }
        try {
            URI address = new URI("http", null, host, port, null, null, null);
            if (address.getHost() == null) throw new IllegalArgumentException("代理主机无效");
        } catch (URISyntaxException e) {
            throw new IllegalArgumentException("代理主机无效");
        }
        if (request.getAvailableStatus() != null && request.getAvailableStatus() != 0 && request.getAvailableStatus() != 1) {
            throw new IllegalArgumentException("代理可用状态无效");
        }
        if (request.getForceProxy() != null && request.getForceProxy() != 0 && request.getForceProxy() != 1) {
            throw new IllegalArgumentException("强制代理状态无效");
        }
        if ((request.getProxyUsername() != null && request.getProxyUsername().length() > 64)
                || (request.getProxyPassword() != null && request.getProxyPassword().length() > 128)
                || (request.getCustomName() != null && request.getCustomName().trim().length() > 128)) {
            throw new IllegalArgumentException("代理配置字段过长");
        }
        request.setProxyType(type);
        request.setProxyHost(host);
    }

    /**
     * 批量填充 tenantIds / tenantName。只读，不写 bind 表。
     * 旧 tenant_id 列仅用于展示回退；写入只走 save/bind。
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
     * 替换某代理的全部绑定。租户已有行则改 proxy_id，避免 delete+insert 撞 uk_vpn_proxy_tenant。
     */
    private void replaceBinds(Long proxyId, List<Long> tenantIds) {
        if (proxyId == null) {
            return;
        }
        LinkedHashSet<Long> desired = new LinkedHashSet<>();
        if (tenantIds != null) {
            for (Long tid : tenantIds) {
                if (tid != null) {
                    desired.add(tid);
                }
            }
        }

        List<VpnProxyTenantBind> current = vpnProxyTenantBindRepository.findByProxyId(proxyId);
        if (current != null) {
            for (VpnProxyTenantBind b : current) {
                if (b == null) {
                    continue;
                }
                if (b.getTenantId() == null || !desired.contains(b.getTenantId())) {
                    vpnProxyTenantBindRepository.delete(b);
                }
            }
        }

        for (Long tid : desired) {
            upsertBind(proxyId, tid);
        }
        if (!desired.isEmpty()) {
            syncLegacyTenantIdColumn(desired, proxyId);
        }
        vpnProxyTenantBindRepository.flush();
    }

    /** 一租户一行：已存在则改绑到本代理，不存在再插入。 */
    private void upsertBind(Long proxyId, Long tenantId) {
        VpnProxyTenantBind existing = vpnProxyTenantBindRepository.findTopByTenantId(tenantId);
        if (existing == null) {
            VpnProxyTenantBind b = new VpnProxyTenantBind();
            b.setProxyId(proxyId);
            b.setTenantId(tenantId);
            vpnProxyTenantBindRepository.save(b);
            return;
        }
        if (!proxyId.equals(existing.getProxyId())) {
            existing.setProxyId(proxyId);
            vpnProxyTenantBindRepository.save(existing);
        }
    }

    /** 其它代理旧列若仍写着这些租户，清掉，避免列表回退显示成重复绑定。 */
    private void syncLegacyTenantIdColumn(Set<Long> tenantIds, Long keepProxyId) {
        if (tenantIds == null || tenantIds.isEmpty()) {
            return;
        }
        List<VpnProxyRecord> all = vpnProxyRecordRepository.findAll();
        for (VpnProxyRecord r : all) {
            if (r == null || r.getId() == null || r.getId().equals(keepProxyId)) {
                continue;
            }
            if (r.getTenantId() != null && tenantIds.contains(r.getTenantId())) {
                r.setTenantId(null);
                r.setUpdateTime(LocalDateTime.now());
                vpnProxyRecordRepository.save(r);
            }
        }
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
            throw new IllegalArgumentException("租户 id 无效");
        }
        Long current = tenantId;
        Set<Long> visited = new HashSet<>();
        for (int i = 0; i < 8; i++) {
            if (!visited.add(current)) throw new IllegalArgumentException("租户父级关系存在循环");
            Optional<Tenant> opt = tenantRepository.findById(current);
            if (!opt.isPresent()) {
                throw new IllegalArgumentException("租户或父级租户不存在");
            }
            Tenant t = opt.get();
            Long parenId = t.getParenId();
            if (parenId == null || parenId == 0L) {
                return t.getId();
            }
            current = parenId;
        }
        throw new IllegalArgumentException("租户父级关系层数过多");
    }
}
