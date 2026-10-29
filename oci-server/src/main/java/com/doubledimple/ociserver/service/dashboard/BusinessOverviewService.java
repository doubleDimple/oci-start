package com.doubledimple.ociserver.service.dashboard;

import com.doubledimple.ociserver.pojo.response.BusinessOverview;
import com.doubledimple.ociserver.pojo.response.BusinessOverview.Activity;
import com.doubledimple.ociserver.pojo.response.BusinessOverview.Bucket;
import com.doubledimple.ociserver.pojo.response.BusinessOverview.Day;
import com.doubledimple.ociserver.pojo.response.DashboardStats;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;
import javax.persistence.TypedQuery;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class BusinessOverviewService {
    private static final String OCI_INSTANCES = "i.cloudType = 1 and (i.state is null or upper(trim(i.state)) <> 'TERMINATED')";
    private static final String OCI_ACCOUNTS = "t.cloudType = 1 and (t.parenId is null or t.parenId = 0)";
    private static final int RANK_LIMIT = 6;

    @PersistenceContext
    private EntityManager entities;
    private Clock clock = Clock.systemDefaultZone();

    @Transactional(readOnly = true)
    public BusinessOverview overview(int days) {
        if (days != 7 && days != 30) throw new IllegalArgumentException("days must be 7 or 30");
        LocalDate today = LocalDate.now(clock);
        LocalDate first = today.minusDays(days - 1L);
        LocalDateTime start = first.atStartOfDay();
        LocalDateTime end = LocalDateTime.now(clock);
        BusinessOverview result = new BusinessOverview();
        result.setDays(days);
        result.setStartDate(first.toString());
        result.setEndDate(today.toString());
        result.setTimeZone(clock.getZone().getId());
        result.setGeneratedAt(clock.millis());

        Map<String, Long> accountStates = buckets("active", "inactive", "unknown");
        for (Object[] row : rows("select t.isActive, count(t) from Tenant t where " + OCI_ACCOUNTS + " group by t.isActive")) {
            String key = Boolean.TRUE.equals(row[0]) ? "active" : Boolean.FALSE.equals(row[0]) ? "inactive" : "unknown";
            accountStates.put(key, count(row[1]));
        }
        result.setAccountStates(list(accountStates));
        result.setAccounts(sum(accountStates));

        Map<String, Long> states = buckets("running", "stopped", "transitioning", "unknown");
        Map<String, Long> architectures = buckets("arm", "x86", "unknown");
        for (Object[] row : rows("select i.state, i.architecture, count(i), sum(i.ocpus), sum(i.memoryInGBs), sum(i.bootVolumeSizeInGBs), "
                + "count(i.ocpus), count(i.memoryInGBs), count(i.bootVolumeSizeInGBs) from InstanceDetails i where "
                + OCI_INSTANCES + " group by i.state, i.architecture")) {
            add(states, instanceState(row[0]), count(row[2]));
            add(architectures, architecture(row[1]), count(row[2]));
            result.setOcpus(result.getOcpus() + count(row[3]));
            result.setMemoryGiB(result.getMemoryGiB() + count(row[4]));
            result.setBootVolumeGiB(result.getBootVolumeGiB() + count(row[5]));
            result.setKnownCpuInstances(result.getKnownCpuInstances() + count(row[6]));
            result.setKnownMemoryInstances(result.getKnownMemoryInstances() + count(row[7]));
            result.setKnownVolumeInstances(result.getKnownVolumeInstances() + count(row[8]));
        }
        result.setInstances(sum(states));
        result.setInstanceStates(list(states));
        result.setArchitectures(list(architectures));

        // Match MonitorCoreService's three-minute heartbeat threshold.
        Object[] heartbeat = entities.createQuery("select "
                + "sum(case when i.monitorInstalled = true and i.lastHeartbeat >= :threshold then 1 else 0 end), "
                + "sum(case when i.monitorInstalled = true and (i.lastHeartbeat is null or i.lastHeartbeat < :threshold) then 1 else 0 end), "
                + "sum(case when i.monitorInstalled = false or i.monitorInstalled is null then 1 else 0 end) "
                + "from InstanceDetails i where " + OCI_INSTANCES, Object[].class)
                .setParameter("threshold", new Date(clock.millis() - 180000L)).getSingleResult();
        result.setMonitoring(Arrays.asList(new Bucket("online", "online", count(heartbeat[0])),
                new Bucket("stale", "stale", count(heartbeat[1])), new Bucket("uninstalled", "uninstalled", count(heartbeat[2]))));

        // Group in SQL; no full instance rows, passwords, keys or audit bodies are loaded.
        List<Object[]> regions = rows("select t.region, count(i) from InstanceDetails i left join Tenant t on t.id = i.tenantId and t.cloudType = 1 "
                + "where " + OCI_INSTANCES + " group by t.region order by count(i) desc, t.region asc");
        Map<String, Long> regionCounts = new LinkedHashMap<>();
        for (Object[] row : regions) add(regionCounts, text(row[0]).isEmpty() ? "unknown" : text(row[0]), count(row[1]));
        result.setRegions(regionCounts.keySet().stream().filter(key -> !"unknown".equals(key)).count());
        result.setRegionRanking(ranked(regionCounts));

        String owner = "coalesce(p.id, t.id)";
        String ownerName = "case when p.id is not null then coalesce(p.tenancyName, p.userName) else coalesce(t.tenancyName, t.userName) end";
        List<Object[]> tenants = entities.createQuery("select " + owner + ", " + ownerName + ", count(i) "
                + "from InstanceDetails i join Tenant t on t.id = i.tenantId and t.cloudType = 1 "
                + "left join Tenant p on p.id = t.parenId and p.cloudType = 1 "
                + "where " + OCI_INSTANCES + " group by " + owner + ", " + ownerName
                + " order by count(i) desc, " + owner + " asc", Object[].class).setMaxResults(RANK_LIMIT).getResultList();
        for (Object[] row : tenants) result.getTenantRanking().add(new Bucket(String.valueOf(row[0]), text(row[1]), count(row[2])));

        // GET polling would overwhelm genuine activity; this view counts recorded
        // POST/PUT/PATCH/DELETE operations, including failed operations.
        result.setOperations(activity("AuditLog a", "a.createTime", "a.status",
                "upper(a.method) in ('POST', 'PUT', 'PATCH', 'DELETE') "
                + "and (a.requestUri is null or (a.requestUri not like '/other/%' and a.requestUri not like '/gcp/%' "
                + "and a.requestUri not like '/azure/%' and a.requestUri not like '/aws/%' and a.requestUri not like '/tenants/gcp%' "
                + "and a.requestUri not like '%/list' and a.requestUri not like '%/get' and a.requestUri not like '%/pageList' "
                + "and a.requestUri not in ('/sysMessage/countUnread', '/cost/query', '/tenants/querySystemImages', '/vps/instances/getLatLon')))", start, end, first, days));
        result.setEmail(activity("EmailSendRecord e", "e.createTime", "e.sendState",
                "exists (select t.id from Tenant t where t.id = e.tenantId and t.cloudType = 1)", start, end, first, days));

        Object[] launch = rows("select count(b), sum(b.addCount), sum(b.successCount), sum(b.failCount) from BootInstance b where b.cloudType = 1").get(0);
        DashboardStats launchStats = new DashboardStats();
        launchStats.setTotalApiCalls(result.getAccounts());
        launchStats.setTotalBootInstances(count(launch[0]));
        launchStats.setTotalAttempts(count(launch[1]));
        launchStats.setSuccessfulAttempts(count(launch[2]));
        launchStats.setFailCounts(count(launch[3]));
        result.setLaunch(launchStats);
        return result;
    }

    private Activity activity(String entity, String timestamp, String status, String scope,
                              LocalDateTime start, LocalDateTime end, LocalDate first, int days) {
        String dateParts = "year(" + timestamp + "), month(" + timestamp + "), day(" + timestamp + ")";
        TypedQuery<Object[]> query = entities.createQuery("select " + dateParts + ", " + status + ", count(*) from " + entity
                + " where " + timestamp + " >= :start and " + timestamp + " <= :end and " + scope
                + " group by " + dateParts + ", " + status, Object[].class);
        query.setParameter("start", start).setParameter("end", end);
        Map<String, Day> daily = new LinkedHashMap<>();
        for (int i = 0; i < days; i++) {
            String date = first.plusDays(i).toString();
            daily.put(date, new Day(date, 0, 0, 0));
        }
        Activity activity = new Activity();
        for (Object[] row : query.getResultList()) {
            String date = LocalDate.of(((Number) row[0]).intValue(), ((Number) row[1]).intValue(), ((Number) row[2]).intValue()).toString();
            Day day = daily.get(date);
            long value = count(row[4]);
            Integer state = row[3] == null ? null : ((Number) row[3]).intValue();
            if (Integer.valueOf(1).equals(state)) {
                day.setSuccess(day.getSuccess() + value);
                activity.setSuccess(activity.getSuccess() + value);
            } else if (Integer.valueOf(0).equals(state)) {
                day.setFailed(day.getFailed() + value);
                activity.setFailed(activity.getFailed() + value);
            } else {
                day.setUnknown(day.getUnknown() + value);
                activity.setUnknown(activity.getUnknown() + value);
            }
            activity.setTotal(activity.getTotal() + value);
        }
        activity.setDaily(new ArrayList<>(daily.values()));
        return activity;
    }

    private List<Object[]> rows(String hql) { return entities.createQuery(hql, Object[].class).getResultList(); }
    private static long count(Object value) { return value instanceof Number ? ((Number) value).longValue() : 0L; }
    private static String text(Object value) { return value == null ? "" : String.valueOf(value).trim(); }
    private static String instanceState(Object value) {
        String state = text(value).toUpperCase(Locale.ROOT);
        if ("RUNNING".equals(state)) return "running";
        if ("STOPPED".equals(state)) return "stopped";
        if (Arrays.asList("STARTING", "STOPPING", "PROVISIONING", "TERMINATING", "MOVING", "CREATING_IMAGE").contains(state)) return "transitioning";
        return "unknown";
    }
    private static String architecture(Object value) {
        String arch = text(value).toLowerCase(Locale.ROOT);
        if (Arrays.asList("arm", "arm64", "aarch64").contains(arch)) return "arm";
        if (Arrays.asList("x86", "x86_64", "amd64", "x64").contains(arch)) return "x86";
        return "unknown";
    }
    private static Map<String, Long> buckets(String... keys) {
        Map<String, Long> result = new LinkedHashMap<>();
        for (String key : keys) result.put(key, 0L);
        return result;
    }
    private static void add(Map<String, Long> values, String key, long count) { values.merge(key, count, Long::sum); }
    private static long sum(Map<String, Long> values) { return values.values().stream().mapToLong(Long::longValue).sum(); }
    private static List<Bucket> list(Map<String, Long> values) {
        return values.entrySet().stream().map(entry -> new Bucket(entry.getKey(), entry.getKey(), entry.getValue())).collect(Collectors.toList());
    }
    private static List<Bucket> ranked(Map<String, Long> values) {
        return values.entrySet().stream().sorted(Map.Entry.<String, Long>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey()))
                .limit(RANK_LIMIT).map(entry -> new Bucket(entry.getKey(), entry.getKey(), entry.getValue())).collect(Collectors.toList());
    }
}
