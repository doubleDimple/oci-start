package com.doubledimple.ocimonitor.service.quality;

import com.doubledimple.dao.entity.*;
import com.doubledimple.dao.repository.*;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import javax.annotation.Resource;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.*;

/** Task targets are executed only by the authenticated remote agent, never by this service. */
@Service
public class NetworkQualityService {
    private static final long RETENTION_MS = 7L * 24 * 60 * 60 * 1000;
    private static final long LEASE_MS = 120000;
    private static final Set<String> TYPES = set("icmp", "tcp", "http");
    private static final Set<String> OPERATORS = set("telecom", "unicom", "mobile", "custom");
    private static final Set<String> STATUSES = set("success", "partial", "failed", "unsupported", "error");
    private static final Set<String> ERRORS = set("timeout", "dns_error", "connection_refused", "network_error", "http_error", "unsupported", "internal_error");
    private final SecureRandom random = new SecureRandom();
    private final Object creationLock = new Object();
    @Resource private NetworkQualityTaskRepository tasks;
    @Resource private NetworkQualityCredentialRepository credentials;
    @Resource private NetworkQualityAssignmentRepository assignments;
    @Resource private NetworkQualitySampleRepository samples;
    @Resource private NetworkQualityInstanceRepository instances;
    @Resource private PlatformTransactionManager transactionManager;

    @Transactional
    public AgentCredentialReceipt issueAgentCredential(String localInstanceId) {
        Long id = id(localInstanceId);
        requireInstance(id);
        NetworkQualityCredential credential = credentials.lockByInstance(id).orElseGet(() -> {
            NetworkQualityCredential value = new NetworkQualityCredential();
            value.setInstanceId(id);
            value.setGeneration(UUID.randomUUID().toString());
            return value;
        });
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Arrays.fill(bytes, (byte) 0);
        credential.setPendingHash(hash(token));
        credential.setPendingGeneration(UUID.randomUUID().toString());
        credential.setPendingExpiresAt(System.currentTimeMillis() + 24L * 60 * 60 * 1000);
        credentials.saveAndFlush(credential);
        return new AgentCredentialReceipt(localInstanceId, token);
    }

    @Transactional
    public void revokeAgentCredential(String localInstanceId) {
        Long id = id(localInstanceId);
        Optional<NetworkQualityCredential> found = credentials.lockByInstance(id);
        if (!found.isPresent()) return;
        NetworkQualityCredential credential = found.get();
        credential.setTokenHash(null);
        clearPending(credential);
        credential.setGeneration(UUID.randomUUID().toString());
        credential.setLastSeen(null);
        credential.setAgentVersion(null);
        credential.setCapabilities(null);
        for (NetworkQualityAssignment assignment : assignments.lockForInstance(id)) clearLease(assignment);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String, Object> overview() {
        long now = System.currentTimeMillis();
        List<NetworkQualityTask> taskRows = tasks.findAll(PageRequest.of(0, 65, Sort.by("id"))).getContent();
        List<NetworkQualityAssignment> links = assignments.findAll(PageRequest.of(0, 16385, Sort.by("id"))).getContent();
        if (taskRows.size() > 64 || links.size() > 16384) throw limit();
        Map<Long, List<String>> ids = new HashMap<>();
        List<Long> latestIds = new ArrayList<>();
        for (NetworkQualityAssignment a : links) {
            ids.computeIfAbsent(a.getTaskId(), key -> new ArrayList<>()).add(a.getInstanceId().toString());
            if (a.getLatestSampleId() != null) latestIds.add(a.getLatestSampleId());
        }
        List<Map<String, Object>> taskData = new ArrayList<>();
        Map<Long, Long> revisions = new HashMap<>();
        for (NetworkQualityTask task : taskRows) {
            taskData.add(taskData(task, ids.getOrDefault(task.getId(), Collections.emptyList())));
            revisions.put(task.getId(), task.getVersion());
        }
        List<Map<String, Object>> latest = new ArrayList<>();
        for (int start = 0; start < latestIds.size(); start += 256) {
            for (NetworkQualitySample sample : samples.findAllById(latestIds.subList(start, Math.min(start + 256, latestIds.size())))) {
                if (sample.getUpdatedAt() >= now - RETENTION_MS && sample.getRevision().equals(revisions.get(sample.getTaskId()))) latest.add(sampleData(sample));
            }
        }
        List<Map<String, Object>> agents = new ArrayList<>();
        for (int page = 0; page <= 40; page++) {
            List<NetworkQualityInstanceRepository.AgentInstance> rows = instances.listAgents(PageRequest.of(page, 500));
            if (agents.size() + rows.size() > 20000) throw limit();
            Map<Long, NetworkQualityCredential> byInstance = new HashMap<>();
            List<Long> pageIds = new ArrayList<>();
            for (NetworkQualityInstanceRepository.AgentInstance row : rows) pageIds.add(row.getId());
            if (!pageIds.isEmpty()) for (NetworkQualityCredential credential : credentials.findAllById(pageIds)) byInstance.put(credential.getInstanceId(), credential);
            for (NetworkQualityInstanceRepository.AgentInstance row : rows) {
                NetworkQualityCredential credential = byInstance.get(row.getId());
                Long lastSeen = credential == null ? null : credential.getLastSeen();
                String state = !Boolean.TRUE.equals(row.getMonitorInstalled()) ? "not_installed"
                        : credential == null || credential.getTokenHash() == null || lastSeen == null ? "upgrade_required"
                        : now - lastSeen <= 45000 ? "online" : "offline";
                agents.add(map("id", row.getId().toString(), "instanceId", row.getId().toString(),
                        "displayName", row.getDisplayName(), "publicIps", row.getPublicIps(),
                        "tenancyName", row.getTenancyName(), "regionName", row.getRegionName(),
                        "cloudType", row.getCloudType(), "monitorInstalled", row.getMonitorInstalled(),
                        "qualityStatus", state, "lastSeen", lastSeen,
                        "version", credential == null ? null : credential.getAgentVersion()));
            }
            if (rows.size() < 500) break;
        }
        return map("tasks", taskData, "agents", agents, "latest", latest, "serverTime", now, "legacyDisabled", true);
    }

    /** Commit while holding this application's creation lock so the task limit cannot race between HTTP requests. */
    public Map<String, Object> createTask(JsonNode body) {
        synchronized (creationLock) {
            return new TransactionTemplate(transactionManager).execute(status -> {
                if (tasks.count() >= 64) throw limit();
                NetworkQualityTask task = new NetworkQualityTask();
                List<Long> instanceIds = applyTaskInput(task, body);
                task.setCreatedAt(System.currentTimeMillis());
                task.setUpdatedAt(task.getCreatedAt());
                tasks.saveAndFlush(task);
                for (Long instanceId : instanceIds) assignments.save(newAssignment(task.getId(), instanceId));
                return taskData(task, strings(instanceIds));
            });
        }
    }

    @Transactional
    public Map<String, Object> updateTask(String taskId, JsonNode body) {
        NetworkQualityTask task = lockedTask(taskId);
        requireVersion(task, text(body, "version", true));
        List<Long> instanceIds = applyTaskInput(task, body);
        task.setUpdatedAt(Math.max(System.currentTimeMillis(), task.getUpdatedAt() + 1));
        List<NetworkQualityAssignment> previous = assignments.lockForTask(task.getId());
        Map<Long, NetworkQualityAssignment> retained = new HashMap<>();
        for (NetworkQualityAssignment assignment : previous) {
            if (instanceIds.contains(assignment.getInstanceId())) {
                // Reject the old result, but keep its slot until expiry to avoid overlapping probes.
                assignment.setRequested(false);
                assignment.setNextDue(task.getUpdatedAt());
                assignment.setLatestSampleId(null);
                retained.put(assignment.getInstanceId(), assignment);
            } else assignments.delete(assignment);
        }
        for (Long instanceId : instanceIds) if (!retained.containsKey(instanceId)) assignments.save(newAssignment(task.getId(), instanceId));
        tasks.saveAndFlush(task);
        return taskData(task, strings(instanceIds));
    }

    @Transactional
    public Map<String, Object> deleteTask(String taskId, String version) {
        NetworkQualityTask task = lockedTask(taskId);
        requireVersion(task, version);
        assignments.deleteAll(assignments.lockForTask(task.getId()));
        samples.deleteTaskHistory(task.getId());
        tasks.delete(task);
        return map("deleted", true);
    }

    @Transactional
    public Map<String, Object> runTask(String taskId, JsonNode body) {
        NetworkQualityTask task = lockedTask(taskId);
        requireVersion(task, text(body, "version", true));
        List<NetworkQualityAssignment> links = assignments.lockForTask(task.getId());
        Set<Long> allowed = new LinkedHashSet<>();
        for (NetworkQualityAssignment link : links) allowed.add(link.getInstanceId());
        Set<Long> selected = body.has("instanceIds") ? new LinkedHashSet<>(instanceIds(body.get("instanceIds"))) : allowed;
        if (selected.isEmpty() || !allowed.containsAll(selected)) throw invalid();
        int queued = 0, running = 0, alreadyQueued = 0;
        long now = System.currentTimeMillis();
        for (NetworkQualityAssignment link : links) {
            if (!selected.contains(link.getInstanceId())) continue;
            expire(link, now);
            if (link.getExecutionId() != null) running++;
            else if (Boolean.TRUE.equals(link.getRequested())) alreadyQueued++;
            else { link.setRequested(true); queued++; }
        }
        return map("status", "queued", "requested", selected.size(), "queued", queued,
                "alreadyRunning", running, "alreadyQueued", alreadyQueued);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String, Object> history(String instanceId, String taskId, String revision, int hours) {
        Long localId = id(instanceId), localTaskId = id(taskId);
        Long requestedRevision = version(revision);
        if (!(hours == 1 || hours == 6 || hours == 24 || hours == 168)) throw invalid();
        if (!assignments.findByInstanceIdAndTaskId(localId, localTaskId).isPresent()) throw missing();
        NetworkQualityTask task = tasks.findById(localTaskId).orElseThrow(NetworkQualityService::missing);
        if (!task.getVersion().equals(requestedRevision)) throw conflict();
        long to = System.currentTimeMillis(), from = to - hours * 3600000L;
        NetworkQualitySampleRepository.WindowStats summary = samples.statistics(localId, localTaskId, task.getVersion(), from, to);
        long count = zero(summary.getCount()), attempts = zero(summary.getAttempts()), successful = zero(summary.getSuccessful());
        Map<String, Object> stats = map("count", count, "successCount", zero(summary.getSuccessCount()),
                "partialCount", zero(summary.getPartialCount()), "failedCount", zero(summary.getFailedCount()),
                "unsupportedCount", zero(summary.getUnsupportedCount()), "errorCount", zero(summary.getErrorCount()),
                "unknownCount", zero(summary.getUnknownCount()), "attempts", attempts, "successful", successful,
                "avgMs", successful == 0 || summary.getWeightedMs() == null ? null : summary.getWeightedMs() / successful,
                "minMs", summary.getMinMs(), "maxMs", summary.getMaxMs(),
                "lossPercent", attempts == 0 ? null : 100.0 * (attempts - successful) / attempts);
        List<NetworkQualitySample> rows = samples.window(localId, localTaskId, task.getVersion(), from, to, PageRequest.of(0, 720));
        Collections.reverse(rows);
        List<Map<String, Object>> points = new ArrayList<>();
        for (NetworkQualitySample sample : rows) points.add(sampleData(sample));
        return map("instanceId", instanceId, "taskId", taskId, "revision", revision, "hours", hours, "from", from, "to", to,
                "points", points, "totalPoints", count, "truncated", count > points.size(), "stats", stats);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public Map<String, Object> poll(String authorization, JsonNode body) {
        if (!"1".equals(text(body, "version", true))) throw invalid();
        Set<String> capabilities = capabilities(body.get("capabilities"));
        int slots = integer(body, "availableSlots", 4, 0, 4);
        long now = System.currentTimeMillis();
        NetworkQualityCredential credential = authenticate(authorization, true, now);
        List<NetworkQualityAssignment> links = assignments.lockForInstance(credential.getInstanceId());
        if (links.size() > 64) throw limit();
        credential.setAgentVersion("1");
        credential.setCapabilities(String.join(",", capabilities));
        credential.setLastSeen(now);
        int active = 0;
        for (NetworkQualityAssignment link : links) {
            expire(link, now);
            if (link.getExecutionId() != null) active++;
        }
        slots = Math.min(slots, Math.max(0, 4 - active));
        // Oldest due work first: a busy low-ID task cannot starve the remaining tasks.
        links.sort(Comparator.comparing((NetworkQualityAssignment a) -> !Boolean.TRUE.equals(a.getRequested()))
                .thenComparing(NetworkQualityAssignment::getNextDue).thenComparing(NetworkQualityAssignment::getId));
        List<Map<String, Object>> jobs = new ArrayList<>();
        int processed = 0;
        for (NetworkQualityAssignment link : links) {
            if (processed >= slots || link.getExecutionId() != null) continue;
            Optional<NetworkQualityTask> found = tasks.findById(link.getTaskId());
            if (!found.isPresent()) continue;
            NetworkQualityTask task = found.get();
            if (!Boolean.TRUE.equals(link.getRequested()) && (!Boolean.TRUE.equals(task.getEnabled()) || link.getNextDue() > now)) continue;
            link.setExecutionId(UUID.randomUUID().toString());
            link.setCredentialGeneration(credential.getGeneration());
            link.setRevision(task.getVersion());
            link.setLeaseExpiresAt(now + LEASE_MS);
            link.setNextDue(now + task.getIntervalSeconds() * 1000L);
            link.setRequested(false);
            processed++;
            if (!capabilities.contains(task.getType())) {
                NetworkQualitySample sample = baseSample(link, now);
                sample.setStatus("unsupported"); sample.setErrorCode("unsupported");
                sample.setAttempts(0); sample.setSuccessful(0);
                record(link, sample);
                continue;
            }
            jobs.add(map("executionId", link.getExecutionId(), "taskId", task.getId().toString(),
                    "revision", task.getVersion().toString(), "type", task.getType(), "target", task.getTarget(),
                    "sampleCount", task.getSampleCount(), "timeoutMs", 3000));
        }
        return map("pollAfterSeconds", 10, "jobs", jobs);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public Map<String, Object> report(String authorization, JsonNode body) {
        long now = System.currentTimeMillis();
        NetworkQualityCredential credential = authenticate(authorization, false, now);
        Long taskId = id(text(body, "taskId", true));
        String executionId = text(body, "executionId", true);
        if (!executionId.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) throw invalid();
        Long revision = version(text(body, "revision", true));
        NetworkQualityAssignment link = assignments.lockPair(credential.getInstanceId(), taskId).orElseThrow(NetworkQualityService::missing);
        NetworkQualityTask task = tasks.findById(taskId).orElseThrow(NetworkQualityService::missing);
        if (!executionId.equals(link.getExecutionId()) || !revision.equals(link.getRevision())
                || !revision.equals(task.getVersion()) || !credential.getGeneration().equals(link.getCredentialGeneration())) throw conflict();
        if (link.getLeaseExpiresAt() == null || link.getLeaseExpiresAt() <= now) throw expired();
        String status = text(body, "status", true);
        if (!STATUSES.contains(status)) throw invalid();
        int attempts = integer(body, "attempts", null, 0, task.getSampleCount());
        int successful = integer(body, "successful", null, 0, attempts);
        if (("success".equals(status) && (attempts != task.getSampleCount() || successful != attempts))
                || ("partial".equals(status) && (attempts != task.getSampleCount() || successful == 0 || successful == attempts))
                || ("failed".equals(status) && (attempts != task.getSampleCount() || successful != 0))
                || ("unsupported".equals(status) && attempts != 0)) throw invalid();
        Double avg = metric(body, "avgMs", successful > 0), min = metric(body, "minMs", successful > 0), max = metric(body, "maxMs", successful > 0);
        if (successful > 0 && (min > avg || avg > max)) throw invalid();
        String errorCode = text(body, "errorCode", false);
        if (errorCode != null && !ERRORS.contains(errorCode)) throw invalid();
        if ("success".equals(status) && errorCode != null) throw invalid();
        if ("unsupported".equals(status)) errorCode = "unsupported";
        Integer httpStatus = optionalInteger(body, "httpStatus", 100, 599);
        if (httpStatus != null && !"http".equals(task.getType())) throw invalid();
        NetworkQualitySample sample = baseSample(link, now);
        sample.setStatus(status); sample.setAttempts(attempts); sample.setSuccessful(successful);
        sample.setAvgMs(avg); sample.setMinMs(min); sample.setMaxMs(max);
        sample.setErrorCode(errorCode); sample.setHttpStatus(httpStatus);
        record(link, sample);
        credential.setLastSeen(now);
        return map("accepted", true);
    }

    /** Small lease batches; task/agent activity also expires the exact rows it visits. */
    @Scheduled(fixedDelay = 30000)
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public void expireLeases() {
        long now = System.currentTimeMillis();
        for (NetworkQualityAssignment link : assignments.lockExpired(now, PageRequest.of(0, 256))) expire(link, now);
    }

    @Scheduled(fixedDelay = 60000)
    @Transactional
    public void retainHistory() {
        long cutoff = System.currentTimeMillis() - RETENTION_MS;
        // Read and delete bounded ID batches; never hydrate the complete seven-day history.
        for (int batch = 0; batch < 128; batch++) {
            List<Long> ids = samples.expiredIds(cutoff, PageRequest.of(0, 512));
            if (ids.isEmpty()) break;
            samples.deleteIds(ids);
            if (ids.size() < 512) break;
        }
    }

    private NetworkQualityCredential authenticate(String authorization, boolean mayActivate, long now) {
        if (authorization == null || !authorization.matches("Bearer [A-Za-z0-9_-]{43}")) throw unauthorized();
        String tokenHash = hash(authorization.substring(7));
        NetworkQualityCredential credential = credentials.lockByHash(tokenHash).orElseThrow(NetworkQualityService::unauthorized);
        if (!instances.existsById(credential.getInstanceId())) throw unauthorized();
        if (tokenHash.equals(credential.getPendingHash())) {
            if (!mayActivate || credential.getPendingExpiresAt() == null || credential.getPendingExpiresAt() <= now) throw unauthorized();
            credential.setTokenHash(credential.getPendingHash());
            credential.setGeneration(credential.getPendingGeneration());
            clearPending(credential);
            for (NetworkQualityAssignment link : assignments.lockForInstance(credential.getInstanceId())) clearLease(link);
        } else if (!tokenHash.equals(credential.getTokenHash())) throw unauthorized();
        return credential;
    }

    private void expire(NetworkQualityAssignment link, long now) {
        if (link.getExecutionId() == null || link.getLeaseExpiresAt() == null || link.getLeaseExpiresAt() > now) return;
        Optional<NetworkQualityTask> task = tasks.findById(link.getTaskId());
        if (task.isPresent() && task.get().getVersion().equals(link.getRevision())) {
            NetworkQualitySample sample = baseSample(link, now);
            sample.setStatus("unknown"); sample.setErrorCode("lease_expired");
            record(link, sample);
        } else clearLease(link);
    }

    private NetworkQualitySample baseSample(NetworkQualityAssignment link, long now) {
        NetworkQualitySample sample = new NetworkQualitySample();
        sample.setInstanceId(link.getInstanceId()); sample.setTaskId(link.getTaskId());
        sample.setExecutionId(link.getExecutionId()); sample.setRevision(link.getRevision()); sample.setUpdatedAt(now);
        return sample;
    }
    private void record(NetworkQualityAssignment link, NetworkQualitySample sample) {
        samples.saveAndFlush(sample);
        link.setLatestSampleId(sample.getId());
        clearLease(link);
    }
    private static void clearLease(NetworkQualityAssignment link) {
        link.setExecutionId(null); link.setCredentialGeneration(null); link.setRevision(null); link.setLeaseExpiresAt(null);
    }
    private static void clearPending(NetworkQualityCredential credential) {
        credential.setPendingHash(null); credential.setPendingGeneration(null); credential.setPendingExpiresAt(null);
    }
    private NetworkQualityAssignment newAssignment(Long taskId, Long instanceId) {
        NetworkQualityAssignment link = new NetworkQualityAssignment();
        link.setTaskId(taskId); link.setInstanceId(instanceId); link.setNextDue(System.currentTimeMillis());
        return link;
    }

    private List<Long> applyTaskInput(NetworkQualityTask task, JsonNode body) {
        String name = text(body, "name", true), operator = text(body, "operator", true), region = text(body, "region", true);
        String type = text(body, "type", true), target = text(body, "target", true);
        if (name.trim().isEmpty() || name.length() > 80 || region.length() > 80 || !OPERATORS.contains(operator) || !TYPES.contains(type)) throw invalid();
        if (controls(name) || controls(region)) throw invalid();
        validateTarget(type, target);
        int interval = integer(body, "intervalSeconds", 60, 30, 86400), sampleCount = integer(body, "sampleCount", 3, 1, 10);
        if (!body.has("enabled") || !body.get("enabled").isBoolean()) throw invalid();
        List<Long> ids = instanceIds(body.get("instanceIds"));
        if (instances.existingIds(ids).size() != ids.size()) throw missing();
        task.setName(name.trim()); task.setOperator(operator); task.setRegion(region.trim()); task.setType(type); task.setTarget(target);
        task.setIntervalSeconds(interval); task.setSampleCount(sampleCount); task.setEnabled(body.get("enabled").booleanValue());
        return ids;
    }
    private static List<Long> instanceIds(JsonNode node) {
        if (node == null || !node.isArray() || node.size() < 1 || node.size() > 256) throw invalid();
        Set<Long> result = new LinkedHashSet<>();
        for (JsonNode value : node) {
            if (!value.isTextual() || !result.add(id(value.textValue()))) throw invalid();
        }
        return new ArrayList<>(result);
    }
    private static Set<String> capabilities(JsonNode node) {
        if (node == null || !node.isArray() || node.size() > 3) throw invalid();
        Set<String> result = new LinkedHashSet<>();
        for (JsonNode value : node) if (!value.isTextual() || !TYPES.contains(value.textValue()) || !result.add(value.textValue())) throw invalid();
        return result;
    }
    private NetworkQualityTask lockedTask(String taskId) { return tasks.lockById(id(taskId)).orElseThrow(NetworkQualityService::missing); }
    private void requireInstance(Long id) { if (!instances.existsById(id)) throw missing(); }
    private static void requireVersion(NetworkQualityTask task, String version) { if (!task.getVersion().equals(version(version))) throw conflict(); }

    private static void validateTarget(String type, String target) {
        if (target.isEmpty() || target.length() > 2048 || controls(target) || !target.equals(target.trim()) || target.matches(".*\\s.*")) throw invalid();
        try {
            if ("http".equals(type)) {
                URI uri = new URI(target);
                if (!("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) || uri.getHost() == null
                        || uri.getRawUserInfo() != null || uri.getRawFragment() != null || uri.getPort() == 0 || uri.getPort() > 65535) throw invalid();
                host(uri.getHost());
            } else if ("tcp".equals(type)) {
                URI uri = new URI("tcp://" + target);
                if (uri.getHost() == null || uri.getPort() < 1 || uri.getPort() > 65535 || uri.getRawUserInfo() != null
                        || uri.getRawQuery() != null || uri.getRawFragment() != null || !"".equals(uri.getRawPath())) throw invalid();
                host(uri.getHost());
            } else host(target);
        } catch (URISyntaxException e) { throw invalid(); }
    }
    private static void host(String input) {
        String host = input;
        if (host.startsWith("[") && host.endsWith("]")) host = host.substring(1, host.length() - 1);
        if (host.isEmpty() || host.length() > 253) throw invalid();
        if (host.indexOf(':') >= 0) {
            // URI parses IPv6 syntax locally; this does not call InetAddress/DNS.
            try { if (new URI("http://[" + host + "]/").getHost() == null || host.indexOf('%') >= 0) throw invalid(); }
            catch (URISyntaxException e) { throw invalid(); }
            return;
        }
        String name = host.endsWith(".") ? host.substring(0, host.length() - 1) : host;
        for (String label : name.split("\\.", -1)) if (!label.matches("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")) throw invalid();
    }

    private static Map<String, Object> taskData(NetworkQualityTask t, List<String> ids) {
        return map("id", t.getId().toString(), "version", t.getVersion().toString(), "name", t.getName(), "operator", t.getOperator(),
                "region", t.getRegion(), "type", t.getType(), "target", t.getTarget(), "intervalSeconds", t.getIntervalSeconds(),
                "sampleCount", t.getSampleCount(), "enabled", t.getEnabled(), "instanceIds", ids,
                "createdAt", t.getCreatedAt(), "updatedAt", t.getUpdatedAt());
    }
    private static Map<String, Object> sampleData(NetworkQualitySample s) {
        return map("instanceId", s.getInstanceId().toString(), "taskId", s.getTaskId().toString(), "revision", s.getRevision().toString(),
                "executionId", s.getExecutionId(), "updatedAt", s.getUpdatedAt(), "status", s.getStatus(),
                "attempts", s.getAttempts(), "successful", s.getSuccessful(), "avgMs", s.getAvgMs(), "minMs", s.getMinMs(), "maxMs", s.getMaxMs(),
                "errorCode", s.getErrorCode(), "errorMessage", errorMessage(s.getErrorCode()), "httpStatus", s.getHttpStatus());
    }
    private static String errorMessage(String code) {
        if (code == null) return null;
        switch (code) {
            case "timeout": return "采样超时";
            case "dns_error": return "域名解析失败";
            case "connection_refused": return "连接被拒绝";
            case "network_error": return "网络请求失败";
            case "http_error": return "HTTP返回错误状态";
            case "unsupported": return "探针不支持此协议";
            case "lease_expired": return "执行租约过期，未收到有效报告";
            default: return "探针执行异常";
        }
    }
    private static Map<String, Object> map(Object... pairs) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) result.put((String) pairs[i], pairs[i + 1]);
        return result;
    }
    private static List<String> strings(List<Long> values) {
        List<String> result = new ArrayList<>();
        for (Long value : values) result.add(value.toString());
        return result;
    }
    private static Set<String> set(String... values) { return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(values))); }
    private static boolean controls(String value) { for (int i = 0; i < value.length(); i++) if (Character.isISOControl(value.charAt(i))) return true; return false; }
    private static String text(JsonNode body, String field, boolean required) {
        if (body == null || !body.isObject()) throw invalid();
        JsonNode value = body.get(field);
        if (value == null || value.isNull()) { if (required) throw invalid(); return null; }
        if (!value.isTextual()) throw invalid();
        return value.textValue();
    }
    private static int integer(JsonNode body, String field, Integer fallback, int min, int max) {
        if (body == null || !body.isObject()) throw invalid();
        JsonNode value = body.get(field);
        if (value == null && fallback != null) return fallback;
        if (value == null || !value.isIntegralNumber() || !value.canConvertToInt() || value.intValue() < min || value.intValue() > max) throw invalid();
        return value.intValue();
    }
    private static Integer optionalInteger(JsonNode body, String field, int min, int max) {
        return !body.has(field) || body.get(field).isNull() ? null : integer(body, field, null, min, max);
    }
    private static Double metric(JsonNode body, String field, boolean required) {
        JsonNode value = body.get(field);
        if (value == null || value.isNull()) { if (required) throw invalid(); return null; }
        if (!required || !value.isNumber()) throw invalid();
        double number = value.doubleValue();
        if (!Double.isFinite(number) || number < 0 || number > 60000) throw invalid();
        return number;
    }
    private static Long id(String value) {
        if (value == null || !value.matches("[1-9][0-9]{0,18}")) throw invalid();
        try { return Long.valueOf(value); } catch (NumberFormatException e) { throw invalid(); }
    }
    private static Long version(String value) {
        if (value == null || !value.matches("0|[1-9][0-9]{0,18}")) throw invalid();
        try { return Long.valueOf(value); } catch (NumberFormatException e) { throw invalid(); }
    }
    private static String hash(String token) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8));
            StringBuilder value = new StringBuilder(64);
            for (byte b : digest) value.append(Character.forDigit((b >>> 4) & 15, 16)).append(Character.forDigit(b & 15, 16));
            return value.toString();
        } catch (NoSuchAlgorithmException e) { throw new IllegalStateException("SHA-256 unavailable"); }
    }
    private static long zero(Long value) { return value == null ? 0 : value; }
    private static NetworkQualityException invalid() { return new NetworkQualityException(400, "invalidInput", "网络质量请求参数无效"); }
    private static NetworkQualityException missing() { return new NetworkQualityException(404, "notFound", "实例、任务或关联不存在"); }
    private static NetworkQualityException conflict() { return new NetworkQualityException(409, "conflict", "任务版本或执行已变化，请重新读取"); }
    private static NetworkQualityException expired() { return new NetworkQualityException(410, "expired", "执行租约已过期"); }
    private static NetworkQualityException unauthorized() { return new NetworkQualityException(401, "unauthorized", "探针凭据无效或已撤销"); }
    private static NetworkQualityException limit() { return new NetworkQualityException(409, "limitExceeded", "网络质量任务或实例数量超过上限"); }
}
