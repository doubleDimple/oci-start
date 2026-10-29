package com.doubledimple.ociserver.service.dashboard;

import com.doubledimple.dao.entity.*;
import com.doubledimple.ociserver.pojo.response.BusinessOverview;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.test.util.ReflectionTestUtils;
import javax.persistence.EntityManager;
import java.time.*;
import java.util.Date;
import java.util.Properties;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

class BusinessOverviewServiceTest {
    private static LocalContainerEntityManagerFactoryBean factory;
    private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-10-28T02:34:00Z"), ZoneId.of("Asia/Shanghai"));
    private EntityManager entities;
    private BusinessOverviewService service;

    @BeforeAll static void database() {
        factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource("jdbc:h2:mem:business_" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1", "sa", ""));
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        factory.setPackagesToScan(Tenant.class.getPackage().getName());
        factory.setPersistenceUnitPostProcessors(unit -> {
            unit.getManagedClassNames().clear();
            for (Class<?> type : new Class<?>[]{Tenant.class, InstanceDetails.class, AuditLog.class, EmailSendRecord.class, BootInstance.class}) unit.addManagedClassName(type.getName());
        });
        Properties properties = new Properties();
        properties.setProperty("hibernate.hbm2ddl.auto", "create-drop");
        properties.setProperty("hibernate.dialect", "org.hibernate.dialect.H2Dialect");
        factory.setJpaProperties(properties);
        factory.afterPropertiesSet();
    }
    @AfterAll static void closeDatabase() { factory.destroy(); }
    @BeforeEach void prepare() {
        entities = factory.getObject().createEntityManager();
        entities.getTransaction().begin();
        service = new BusinessOverviewService();
        ReflectionTestUtils.setField(service, "entities", entities);
        ReflectionTestUtils.setField(service, "clock", CLOCK);
    }
    @AfterEach void close() { entities.getTransaction().rollback(); entities.close(); }

    @Test void aggregatesOnlyOciAndMergesRegionalChildrenWithoutLeakingSecrets() throws Exception {
        tenant(1, 0, 1, true, "ap-tokyo-1", null);
        tenant(2, 1, 1, false, "ap-osaka-1", "Child region name");
        tenant(3, 0, 1, false, "ap-tokyo-1", "Inactive");
        tenant(4, 0, 2, true, "us-central1", "GCP excluded");
        tenant(5, 0, 1, null, "ap-tokyo-1", "Not checked");
        instance(1, 1, "RUNNING", "aarch64", true, 0, 2, 12, 50L);
        instance(2, 1, "STOPPED", "amd64", true, 180001, 1, 1, 50L);
        instance(3, 1, "RUNNING", null, false, null, null, null, null);
        instance(99, 1, "RUNNING", "arm64", true, null, null, null, null);
        instance(1, 1, "TERMINATED", "aarch64", true, 0, 999, 999, 999L);
        instance(4, 2, "RUNNING", "amd64", true, 0, 999, 999, 999L);
        boot(1, 60, 10, 2); boot(1, 30, 2, 4); boot(2, 99999, 99999, 0);
        entities.flush();
        BusinessOverview result = service.overview(7);
        assertEquals(3, result.getAccounts());
        assertEquals(1, value(result.getAccountStates(), "active"));
        assertEquals(1, value(result.getAccountStates(), "inactive"));
        assertEquals(1, value(result.getAccountStates(), "unknown"));
        assertEquals(4, result.getInstances());
        assertEquals(3, value(result.getInstanceStates(), "running"));
        assertEquals(1, value(result.getInstanceStates(), "stopped"));
        assertEquals(2, value(result.getArchitectures(), "arm"));
        assertEquals(1, value(result.getArchitectures(), "x86"));
        assertEquals(1, value(result.getArchitectures(), "unknown"));
        assertEquals(1, value(result.getMonitoring(), "online"));
        assertEquals(2, value(result.getMonitoring(), "stale"));
        assertEquals(1, value(result.getMonitoring(), "uninstalled"));
        assertEquals(2, result.getRegions());
        assertEquals(1, value(result.getRegionRanking(), "unknown"));
        assertEquals(2, value(result.getTenantRanking(), "1"));
        assertEquals(1, result.getTenantRanking().stream().filter(b -> b.getKey().equals("1")).count());
        assertEquals(3, result.getOcpus()); assertEquals(13, result.getMemoryGiB()); assertEquals(100, result.getBootVolumeGiB());
        assertEquals(2, result.getKnownCpuInstances());
        assertEquals(2, result.getLaunch().getTotalBootInstances());
        assertEquals(90, result.getLaunch().getTotalAttempts());
        assertEquals(12, result.getLaunch().getSuccessfulAttempts());
        assertEquals(6, result.getLaunch().getFailCounts());
        String json = new ObjectMapper().writeValueAsString(result);
        assertFalse(json.contains("SECRET")); assertFalse(json.contains("GCP excluded"));
        assertFalse(json.contains("keyFile")); assertFalse(json.contains("password"));
    }

    @Test void historicalSeriesHonorPeriodBoundariesAndExcludePollingAndOtherCloudMail() {
        tenant(1, 0, 1, true, "ap-tokyo-1", "OCI"); tenant(2, 0, 2, true, "elsewhere", "GCP");
        LocalDateTime now = LocalDateTime.now(CLOCK), start = now.toLocalDate().minusDays(6).atStartOfDay();
        audit(start, 1, "POST", "/oci/action");
        audit(now.minusDays(1), 0, "DELETE", "/oci/action");
        audit(now, null, "PATCH", "/system/settings");
        audit(start.minusSeconds(1), 1, "POST", "/oci/action");
        audit(now.plusSeconds(1), 1, "POST", "/oci/action");
        audit(now, 1, "GET", "/monitor/stats");
        audit(now, 1, "POST", "/email/send/list");
        audit(now, 1, "POST", "/sysMessage/countUnread");
        audit(now, 1, "POST", "/cost/query");
        audit(now, 1, "POST", "/other/instances/change");
        mail(1, start, 1); mail(1, now.minusDays(1), 0); mail(1, now, 99);
        mail(2, now, 1); mail(1, start.minusSeconds(1), 1); mail(1, now.plusSeconds(1), 1);
        entities.flush();
        BusinessOverview seven = service.overview(7);
        assertEquals("2026-10-22", seven.getStartDate());
        assertEquals("Asia/Shanghai", seven.getTimeZone());
        assertEquals(7, seven.getOperations().getDaily().size());
        assertEquals(3, seven.getOperations().getTotal());
        assertEquals(1, seven.getOperations().getFailed());
        assertEquals(1, seven.getOperations().getUnknown());
        assertEquals(0, seven.getOperations().getDaily().get(1).getSuccess());
        assertEquals(3, seven.getEmail().getTotal());
        assertEquals(1, seven.getEmail().getSuccess()); assertEquals(1, seven.getEmail().getFailed()); assertEquals(1, seven.getEmail().getUnknown());
        BusinessOverview thirty = service.overview(30);
        assertEquals(30, thirty.getOperations().getDaily().size());
        assertEquals(4, thirty.getOperations().getTotal()); assertEquals(4, thirty.getEmail().getTotal());
    }

    @Test void emptyInventoryIsAnHonestZeroAndUnsupportedPeriodsAreRejected() {
        BusinessOverview empty = service.overview(7);
        assertEquals(0, empty.getAccounts()); assertEquals(0, empty.getInstances());
        assertEquals(0, empty.getOperations().getTotal()); assertEquals(7, empty.getEmail().getDaily().size());
        assertEquals(0, empty.getKnownCpuInstances());
        assertTrue(empty.getRegionRanking().isEmpty()); assertTrue(empty.getTenantRanking().isEmpty());
        assertThrows(IllegalArgumentException.class, () -> service.overview(365));
    }

    @Test void heartbeatAtThresholdIsOnlineAndRankingsStayBounded() {
        for (int i = 1; i <= 9; i++) {
            tenant(i, 0, 1, true, "region-" + i, "Tenant " + i);
            instance(i, 1, "RUNNING", "ARM", true, 180000, 1, 1, 1L);
        }
        entities.flush();
        BusinessOverview result = service.overview(7);
        assertEquals(9, result.getRegions()); assertEquals(9, value(result.getMonitoring(), "online"));
        assertEquals(6, result.getRegionRanking().size()); assertEquals(6, result.getTenantRanking().size());
    }

    private void tenant(long id, long parent, int cloud, Boolean active, String region, String name) {
        Tenant t = new Tenant(); t.setId(id); t.setParenId(parent); t.setCloudType(cloud); t.setActive(active); t.setRegion(region); t.setTenancyName(name); t.setUserName("Account " + id); t.setKeyFile("SECRET_KEY"); entities.persist(t);
    }
    private void instance(long tenant, int cloud, String state, String architecture, boolean installed, Integer age, Integer cpu, Integer memory, Long disk) {
        InstanceDetails i = new InstanceDetails(); i.setTenantId(tenant); i.setCloudType(cloud); i.setInstanceId(UUID.randomUUID().toString()); i.setState(state); i.setArchitecture(architecture); i.setMonitorInstalled(installed); i.setLastHeartbeat(age == null ? null : new Date(CLOCK.millis() - age)); i.setOcpus(cpu); i.setMemoryInGBs(memory); i.setBootVolumeSizeInGBs(disk); i.setPassword("SECRET_PASSWORD"); entities.persist(i);
    }
    private void audit(LocalDateTime time, Integer state, String method, String uri) {
        AuditLog a = new AuditLog(); a.setCreateTime(time); a.setStatus(state); a.setMethod(method); a.setRequestUri(uri); a.setParams("SECRET_AUDIT_PAYLOAD"); entities.persist(a);
    }
    private void mail(long tenant, LocalDateTime time, int state) {
        EmailSendRecord e = new EmailSendRecord(); e.setTenantId(tenant); e.setCreateTime(time); e.setSendState(state); entities.persist(e);
    }
    private void boot(int cloud, long attempts, int success, int failed) {
        BootInstance b = new BootInstance(); b.setCloudType(cloud); b.setAddCount(attempts); b.setSuccessCount(success); b.setFailCount(failed); b.setRootPassword("SECRET_BOOT_PASSWORD"); entities.persist(b);
    }
    private long value(java.util.List<BusinessOverview.Bucket> values, String key) {
        return values.stream().filter(value -> key.equals(value.getKey())).mapToLong(BusinessOverview.Bucket::getCount).sum();
    }
}
