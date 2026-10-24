package com.doubledimple.ociserver.service.security;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import com.doubledimple.ociserver.config.context.UserContext;
import com.doubledimple.ociserver.controller.TenantController;
import com.doubledimple.ociserver.controller.MigrationController;
import com.doubledimple.ociserver.controller.OciController;
import com.doubledimple.ociserver.controller.MfaBackupController;
import com.doubledimple.ociserver.controller.mfa.OTPController;
import com.doubledimple.ociserver.controller.nginx.NginxController;
import com.doubledimple.ociserver.config.datamigration.DatabaseExportService;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.impl.VerifyServiceImpl;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.service.message.MessageService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.mfa.OTPService;
import com.doubledimple.ociserver.service.mfa.MfaBackupService;
import com.doubledimple.ociserver.service.mfa.MfaImportCodec;
import com.doubledimple.ociserver.service.nginx.NginxConfigService;
import com.doubledimple.ociserver.service.nginx.ProxyConfigService;
import com.doubledimple.ociserver.service.nginx.SslCertificateService;
import com.google.common.base.Ticker;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.dao.support.PersistenceExceptionTranslationInterceptor;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.SharedEntityManagerCreator;
import org.springframework.orm.jpa.vendor.HibernateJpaDialect;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.support.TransactionTemplate;

import javax.persistence.EntityManager;
import java.io.ByteArrayOutputStream;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Real H2 persistence and row locks; code delivery and exported OCI data are isolated mocks. */
class ExportVerificationGuardTest {
    private static final String USER = "export-owner";
    private static final String OTHER = "other-owner";
    private static final String CODE = "AB12CD34";
    private static final String WRONG = "ZZ99ZZ99";
    private static LocalContainerEntityManagerFactoryBean factory;
    private static JpaTransactionManager transactions;
    private static EntityManager entityManager;
    private static LoginUserRepository users;
    private final Map<Long, String> codes = new ConcurrentHashMap<>();
    private final List<String> delivered = new ArrayList<>();
    private MutableClock clock;
    private ExportVerificationGuard guard;
    private Long userId;
    private Long otherId;
    private VerifyServiceImpl verification;
    private MessageService messages;
    private TenantService tenantService;
    private DatabaseExportService databaseExports;
    private TenantRepository ociTenants;
    private OracleInstanceDetailRepository instances;
    private OTPService otp;
    private MfaBackupService mfa;
    private SslCertificateService certificates;
    private MockMvc mvc;

    @BeforeAll
    static void startDatabase() {
        factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource("jdbc:h2:mem:export_guard_" + UUID.randomUUID()
                + ";DB_CLOSE_DELAY=-1;LOCK_TIMEOUT=10000", "sa", ""));
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        factory.setPackagesToScan(LoginUser.class.getPackage().getName());
        factory.setPersistenceUnitPostProcessors(unit -> {
            unit.getManagedClassNames().clear();
            unit.addManagedClassName(LoginUser.class.getName());
        });
        Properties properties = new Properties();
        properties.setProperty("hibernate.hbm2ddl.auto", "create-drop");
        properties.setProperty("hibernate.dialect", "org.hibernate.dialect.H2Dialect");
        factory.setJpaProperties(properties);
        factory.afterPropertiesSet();
        assertNotNull(factory.getObject());
        assertEquals(1, factory.getObject().getMetamodel().getEntities().size());
        transactions = new JpaTransactionManager(factory.getObject());
        entityManager = SharedEntityManagerCreator.createSharedEntityManager(factory.getObject());
        LoginUserRepository repository = new JpaRepositoryFactory(entityManager).getRepository(LoginUserRepository.class);
        ProxyFactory proxy = new ProxyFactory(repository);
        proxy.addAdvice(new PersistenceExceptionTranslationInterceptor(new HibernateJpaDialect()));
        users = (LoginUserRepository) proxy.getProxy();
    }

    @AfterAll
    static void stopDatabase() { if (factory != null) factory.destroy(); }

    @BeforeEach
    void setUp() throws Exception {
        tx(() -> { users.deleteAll(); return null; });
        userId = tx(() -> users.saveAndFlush(account(USER)).getId());
        otherId = tx(() -> users.saveAndFlush(account(OTHER)).getId());
        clock = new MutableClock(Instant.parse("2026-10-24T03:00:00Z"), ZoneId.of("Asia/Shanghai"));
        guard = newGuard();
        verification = new VerifyServiceImpl();
        ReflectionTestUtils.setField(verification, "exportVerificationGuard", guard);
        verification.init();
        Object cache = ReflectionTestUtils.getField(verification, "verificationCodeCache");
        Object localCache = ReflectionTestUtils.getField(cache, "localCache");
        ReflectionTestUtils.setField(localCache, "ticker", new Ticker() {
            @Override public long read() { return clock.elapsedNanos.get(); }
        });
        messages = mock(MessageService.class);
        doAnswer(call -> {
            Matcher match = Pattern.compile("(?m)^([A-Z0-9]{8})$").matcher(call.getArgument(0));
            assertTrue(match.find(), "The delivered export message must contain its eight-character code");
            delivered.add(match.group(1));
            return null;
        }).when(messages).sendMessageTemplateText(anyString(), eq(Boolean.FALSE));
        MessageFactory messageFactory = mock(MessageFactory.class);
        when(messageFactory.getType(MessageEnum.TELEGRAM)).thenReturn(messages);
        ReflectionTestUtils.setField(verification, "messageFactory", messageFactory);
        tenantService = mock(TenantService.class);
        ResponseEntity<?> export = ResponseEntity.ok(Collections.singletonList(Collections.singletonMap("id", "101")));
        doReturn(export).when(tenantService).exportData();
        doReturn(export).when(tenantService).exportData(101L);
        TenantController controller = new TenantController();
        ReflectionTestUtils.setField(controller, "verifyService", verification);
        ReflectionTestUtils.setField(controller, "tenantService", tenantService);
        databaseExports = mock(DatabaseExportService.class);
        when(databaseExports.exportDatabaseToStream()).thenReturn(new ByteArrayOutputStream());
        MigrationController migration = new MigrationController();
        ReflectionTestUtils.setField(migration, "verifyService", verification);
        ReflectionTestUtils.setField(migration, "databaseExportService", databaseExports);
        ociTenants = mock(TenantRepository.class);
        instances = mock(OracleInstanceDetailRepository.class);
        OciController oci = new OciController();
        ReflectionTestUtils.setField(oci, "verifyService", verification);
        ReflectionTestUtils.setField(oci, "tenantRepository", ociTenants);
        ReflectionTestUtils.setField(oci, "oracleInstanceDetailRepository", instances);
        otp = mock(OTPService.class);
        OTPController oldMfa = new OTPController();
        ReflectionTestUtils.setField(oldMfa, "verifyService", verification);
        ReflectionTestUtils.setField(oldMfa, "otpService", otp);
        mfa = mock(MfaBackupService.class);
        MfaBackupController newMfa = new MfaBackupController(mfa, mock(MfaImportCodec.class));
        ReflectionTestUtils.setField(newMfa, "verifyService", verification);
        certificates = mock(SslCertificateService.class);
        when(certificates.downloadCertificate(101L)).thenReturn(Map.of("content", new byte[]{1, 2, 3}, "fileName", "fixture.zip"));
        NginxController nginx = new NginxController(mock(ProxyConfigService.class), certificates, mock(NginxConfigService.class));
        ReflectionTestUtils.setField(nginx, "verifyService", verification);
        mvc = MockMvcBuilders.standaloneSetup(controller, migration, oci, oldMfa, newMfa, nginx).build();
        UserContext.setUsername(USER);
    }

    @AfterEach
    void clearUserContext() { UserContext.clear(); }

    @Test
    void aFailedCheckCommitsBeforeThrowingEvenWhenItsCallerRollsBack() {
        issue(USER, CODE);

        assertThrows(IllegalStateException.class, () -> new TransactionTemplate(transactions).execute(status -> {
            assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, WRONG));
            throw new IllegalStateException("rollback the outer transaction");
        }));

        assertEquals(1, failures(userId));
        assertEquals(LocalDate.of(2026, 10, 24), state(userId).getExportVerificationDate());
        ExportVerificationGuard recreated = newGuard();
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(recreated, USER, WRONG));
        assertEquals(2, failures(userId));
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(recreated, USER, CODE));
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> recreated.issueCode(USER, id -> {
            fail("A blocked account must not generate or send a new code"); return null;
        }));
    }

    @Test
    void successfulVerificationAndReissuingDoNotResetTodaysWrongCount() {
        issue(USER, CODE);
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, WRONG));
        verifyCode(guard, USER, "  " + CODE.toLowerCase(Locale.ROOT) + "  ");
        assertEquals(1, failures(userId));

        issue(USER, "EF56GH78");
        assertEquals(1, failures(userId));
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, WRONG));
        assertEquals(2, failures(userId));
    }

    @ParameterizedTest
    @ValueSource(booleans = {true, false})
    void passwordAndExportErrorsShareTheSameDailyBudgetInEitherOrder(boolean passwordFirst) {
        issue(USER, CODE);
        if (passwordFirst) guard.recordPasswordFailure(USER);
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, WRONG));
        if (!passwordFirst) newGuard().recordPasswordFailure(USER);

        assertEquals(2, failures(userId));
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(newGuard(), USER, CODE));
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> issue(USER, "EF56GH78"));
        issue(OTHER, CODE);
        assertDoesNotThrow(() -> verifyCode(guard, OTHER, CODE));
    }

    @Test
    void twoPasswordFailuresPersistAcrossGuardsAndOuterRollbackWithoutRequiringAnExportCode() {
        assertThrows(IllegalStateException.class, () -> tx(() -> {
            guard.recordPasswordFailure(USER);
            throw new IllegalStateException("rollback login transaction");
        }));
        assertEquals(1, failures(userId));

        assertDoesNotThrow(() -> newGuard().recordPasswordFailure(USER));
        assertEquals(2, failures(userId));
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> issue(USER, CODE));
        assertDoesNotThrow(() -> newGuard().recordPasswordFailure(USER));
        assertEquals(2, failures(userId));

        clock.advance(Duration.ofDays(1));
        issue(USER, CODE);
        assertEquals(0, failures(userId));
        assertDoesNotThrow(() -> verifyCode(guard, USER, CODE));
    }

    @Test
    void aSuccessfulPasswordValidationDoesNotForgiveThePersistedExportFailure() {
        guard.recordPasswordFailure(USER);
        LoginUserService login = new LoginUserService();
        PasswordEncoder encoder = mock(PasswordEncoder.class);
        when(encoder.matches("correct-password", "unused-test-password-hash")).thenReturn(true);
        ReflectionTestUtils.setField(login, "loginUserRepository", users);
        ReflectionTestUtils.setField(login, "passwordEncoder", encoder);

        assertEquals(userId, login.validateCredentials(USER, "correct-password").getId());
        assertEquals(1, failures(userId));
        issue(USER, CODE);
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, WRONG));
        assertEquals(2, failures(userId));
    }

    @Test
    void simultaneousPasswordAndExportFailuresDoNotLoseAnIncrement() throws Exception {
        issue(USER, CODE);
        List<Throwable> results = concurrently(() -> guard.recordPasswordFailure(USER),
                () -> verifyCode(newGuard(), USER, WRONG));

        assertNull(results.get(0));
        assertInstanceOf(ExportVerificationGuard.ExportVerificationException.class, results.get(1));
        assertEquals(2, failures(userId));
    }

    @Test
    void theNextCalendarDayAutomaticallyAllowsANewCode() {
        clock.advance(Duration.ofHours(12).plusMinutes(59).plusSeconds(30));
        issue(USER, CODE);
        rejectTwice(USER);
        clock.advance(Duration.ofSeconds(30));

        issue(USER, "EF56GH78");
        assertEquals(0, failures(userId));
        assertEquals(LocalDate.of(2026, 10, 25), state(userId).getExportVerificationDate());
        assertDoesNotThrow(() -> verifyCode(guard, USER, "EF56GH78"));
    }

    @Test
    void renamingDoesNotResetTheLimitAndOtherAccountIdsRemainIndependent() {
        issue(USER, CODE);
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, WRONG));
        tx(() -> {
            LoginUser renamed = users.findById(userId).orElseThrow(AssertionError::new);
            renamed.setUsername("renamed-owner");
            users.saveAndFlush(renamed);
            return null;
        });

        assertThrows(ExportVerificationGuard.ExportVerificationException.class,
                () -> verifyCode(newGuard(), "renamed-owner", WRONG));
        assertEquals(2, failures(userId));
        issue(OTHER, "EF56GH78");
        assertDoesNotThrow(() -> verifyCode(newGuard(), OTHER, "EF56GH78"));
        assertEquals(0, failures(otherId));
    }

    @Test
    void concurrentWrongRequestsAcrossGuardInstancesDoNotLoseAnIncrement() throws Exception {
        issue(USER, CODE);
        List<Throwable> results = concurrently(() -> verifyCode(guard, USER, WRONG), () -> verifyCode(newGuard(), USER, WRONG));

        assertTrue(results.stream().allMatch(result -> result instanceof ExportVerificationGuard.ExportVerificationException));
        assertEquals(2, failures(userId));
    }

    @Test
    void concurrentCorrectRequestsConsumeTheCodeExactlyOnce() throws Exception {
        issue(USER, CODE);
        List<Throwable> results = concurrently(() -> verifyCode(guard, USER, CODE), () -> verifyCode(newGuard(), USER, CODE));

        assertEquals(1, results.stream().filter(result -> result == null).count());
        assertEquals(1, results.stream().filter(result -> result instanceof ExportVerificationGuard.ExportVerificationException).count());
        assertEquals(0, failures(userId));
        assertFalse(codes.containsKey(userId));
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "123456", "AB!12CD3", "ZZ99ZZ99"})
    void malformedOrWrongInputCountsOnlyWhenAnActiveCodeExists(String input) {
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, input));
        assertEquals(0, failures(userId));
        issue(USER, CODE);
        assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, USER, input));
        assertEquals(1, failures(userId));
    }

    @Test
    void theRealExportServiceGeneratesMixedEightCharacterCodesAndExpiredCodesDoNotCount() {
        String code = sendExportCode();
        assertTrue(code.matches("[A-Z0-9]{8}"));
        assertTrue(code.matches(".*[A-Z].*"));
        assertTrue(code.matches(".*[0-9].*"));
        clock.advance(Duration.ofMinutes(5));

        assertThrows(ExportVerificationGuard.ExportVerificationException.class,
                () -> verification.checkCodeForExport(USER, code));

        assertEquals(0, failures(userId));
        String replacement = sendExportCode();
        assertDoesNotThrow(() -> verification.checkCodeForExport(USER, replacement));
    }

    @Test
    void theRealCodeCacheAndCounterStayBoundToTheAccountIdAfterRename() {
        String code = sendExportCode();
        assertThrows(ExportVerificationGuard.ExportVerificationException.class,
                () -> verification.checkCodeForExport(USER, WRONG));
        tx(() -> {
            LoginUser renamed = users.findById(userId).orElseThrow(AssertionError::new);
            renamed.setUsername("renamed-owner");
            users.saveAndFlush(renamed);
            return null;
        });

        assertDoesNotThrow(() -> verification.checkCodeForExport("renamed-owner", code));
        assertEquals(1, failures(userId));
    }

    @ParameterizedTest
    @ValueSource(strings = {"/tenants/export", "/tenants/exportByTenant", "/migration/export", "/migration/exportEncrypted",
            "/oci/export", "/export-data", "/api/mfa/export", "/ssl/certificates/101/download"})
    void eachExportRequiresItsHeaderCodeOnThatRequestAndRejectsReplay(String path) throws Exception {
        String code = sendExportCode();

        org.springframework.test.web.servlet.ResultActions rejected = mvc.perform(exportRequest(path).param("verificationCode", code))
                .andExpect(status().isForbidden())
                .andExpect(header().string("Cache-Control", "no-store"));
        if ("/api/mfa/export".equals(path)) {
            rejected.andExpect(jsonPath("$.success").value(false))
                    .andExpect(jsonPath("$.errorKey").value("forbidden"))
                    .andExpect(jsonPath("$.writeAttempted").value(false));
        }
        verifyNoInteractions(tenantService, databaseExports, ociTenants, instances, otp, mfa, certificates);
        assertEquals(1, failures(userId));
        mvc.perform(exportRequest(path).header("X-Verify-Code", code))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"));
        mvc.perform(exportRequest(path).header("X-Verify-Code", code))
                .andExpect(status().isForbidden());

        switch (path) {
            case "/tenants/export": verify(tenantService).exportData(); break;
            case "/tenants/exportByTenant": verify(tenantService).exportData(101L); break;
            case "/migration/export": verify(databaseExports).exportDatabaseToStream(); break;
            case "/migration/exportEncrypted": verify(databaseExports).exportEncryptedBackup(any()); break;
            case "/oci/export": verify(ociTenants).findAll(); verify(instances).findAll(); break;
            case "/export-data": verify(otp).getAllKeys(); break;
            case "/api/mfa/export": verify(mfa).exportEntries(Collections.singletonList(1L)); break;
            case "/ssl/certificates/101/download": verify(certificates).downloadCertificate(101L); break;
            default: fail("Unhandled export route");
        }
        verifyNoMoreInteractions(tenantService, databaseExports, ociTenants, instances, otp, mfa, certificates);
        assertEquals(1, failures(userId));
    }

    @Test
    void twoWrongExportRequestsAlsoBlockTheCorrectCodeAndSendingUntilTomorrow() throws Exception {
        String code = sendExportCode();
        for (int attempt = 0; attempt < 2; attempt++) {
            mvc.perform(exportRequest("/tenants/exportByTenant").header("X-Verify-Code", WRONG))
                    .andExpect(status().isForbidden());
        }
        for (String path : Arrays.asList("/tenants/export", "/tenants/exportByTenant", "/migration/export",
                "/migration/exportEncrypted", "/oci/export", "/export-data", "/api/mfa/export", "/ssl/certificates/101/download")) {
            mvc.perform(exportRequest(path).header("X-Verify-Code", code))
                    .andExpect(status().isForbidden());
        }
        mvc.perform(post("/tenants/verify/sendExportCode"))
                .andExpect(status().isForbidden());
        verifyNoInteractions(tenantService, databaseExports, ociTenants, instances, otp, mfa, certificates);
        verify(messages, times(1)).sendMessageTemplateText(anyString(), eq(Boolean.FALSE));
        assertEquals(2, failures(userId));

        clock.advance(Duration.ofDays(1));
        mvc.perform(post("/tenants/verify/sendExportCode")).andExpect(status().isOk());
        assertEquals(0, failures(userId));
        assertEquals(2, delivered.size());
    }

    @Test
    void unavailableCounterStoragePreventsEverySensitiveExportWithoutLeakingDatabaseDetails() throws Exception {
        String code = sendExportCode();
        LoginUserRepository unavailable = mock(LoginUserRepository.class);
        when(unavailable.findByUsernameForUpdate(USER))
                .thenThrow(new DataAccessResourceFailureException("jdbc:private-db password=private-secret"));
        ExportVerificationGuard broken = new ExportVerificationGuard(unavailable, transactions, clock);
        ReflectionTestUtils.setField(broken, "entityManager", entityManager);
        ReflectionTestUtils.setField(verification, "exportVerificationGuard", broken);

        for (String path : Arrays.asList("/tenants/export", "/tenants/exportByTenant", "/migration/export",
                "/migration/exportEncrypted", "/oci/export", "/export-data", "/api/mfa/export", "/ssl/certificates/101/download")) {
            org.springframework.mock.web.MockHttpServletResponse response = mvc.perform(exportRequest(path)
                    .header("X-Verify-Code", code)).andReturn().getResponse();
            assertTrue(response.getStatus() >= 400, path);
            assertEquals("no-store", response.getHeader("Cache-Control"), path);
            assertFalse(response.getContentAsString().contains("private-secret"), path);
            assertFalse(response.getContentAsString().contains("jdbc:"), path);
        }
        verifyNoInteractions(tenantService, databaseExports, ociTenants, instances, otp, mfa, certificates);
    }

    private String sendExportCode() {
        verification.sendVerifyCodeForExport(USER, new MockHttpServletRequest());
        return delivered.get(delivered.size() - 1);
    }

    private ExportVerificationGuard newGuard() {
        ExportVerificationGuard created = new ExportVerificationGuard(users, transactions, clock);
        ReflectionTestUtils.setField(created, "entityManager", entityManager);
        return created;
    }

    private void issue(String username, String code) {
        guard.issueCode(username, id -> { codes.put(id, code); return code; });
    }

    private void rejectTwice(String username) {
        for (int attempt = 0; attempt < 2; attempt++) {
            assertThrows(ExportVerificationGuard.ExportVerificationException.class, () -> verifyCode(guard, username, WRONG));
        }
    }

    private void verifyCode(ExportVerificationGuard current, String username, String code) {
        current.verify(username, code, codes::get, codes::remove);
    }

    private LoginUser state(Long id) { return tx(() -> users.findById(id).orElseThrow(AssertionError::new)); }
    private int failures(Long id) { Integer count = state(id).getExportVerificationWrongCount(); return count == null ? 0 : count; }
    private static <T> T tx(Supplier<T> work) { return new TransactionTemplate(transactions).execute(status -> work.get()); }

    private static LoginUser account(String username) {
        LoginUser user = new LoginUser();
        user.setUsername(username);
        user.setPassword("unused-test-password-hash");
        user.setLoginType(LoginTypeEnum.LOCAL);
        user.setExportVerificationWrongCount(null); // Existing installations may have null in the added columns.
        return user;
    }

    private MockHttpServletRequestBuilder exportRequest(String path) {
        if ("/api/mfa/export".equals(path)) {
            return post(path).contentType("application/json").content("{\"ids\":[\"1\"]}");
        }
        return get(path).param("id", "101");
    }

    private List<Throwable> concurrently(Runnable first, Runnable second) throws Exception {
        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService workers = Executors.newFixedThreadPool(2);
        try {
            Future<Throwable> one = workers.submit(() -> executeConcurrent(first, ready, start));
            Future<Throwable> two = workers.submit(() -> executeConcurrent(second, ready, start));
            assertTrue(ready.await(5, TimeUnit.SECONDS));
            start.countDown();
            return Arrays.asList(one.get(20, TimeUnit.SECONDS), two.get(20, TimeUnit.SECONDS));
        } finally {
            workers.shutdownNow();
            assertTrue(workers.awaitTermination(5, TimeUnit.SECONDS));
        }
    }

    private Throwable executeConcurrent(Runnable work, CountDownLatch ready, CountDownLatch start) {
        try {
            ready.countDown();
            assertTrue(start.await(5, TimeUnit.SECONDS));
            work.run();
            return null;
        } catch (Throwable failure) { return failure; }
    }

    private static final class MutableClock extends Clock {
        private final AtomicReference<Instant> now;
        private final AtomicLong elapsedNanos;
        private final ZoneId zone;
        private MutableClock(Instant instant, ZoneId zone) { this(new AtomicReference<>(instant), new AtomicLong(), zone); }
        private MutableClock(AtomicReference<Instant> now, AtomicLong elapsedNanos, ZoneId zone) {
            this.now = now; this.elapsedNanos = elapsedNanos; this.zone = zone;
        }
        @Override public ZoneId getZone() { return zone; }
        @Override public Clock withZone(ZoneId next) { return new MutableClock(now, elapsedNanos, next); }
        @Override public Instant instant() { return now.get(); }
        private void advance(Duration duration) { now.updateAndGet(value -> value.plus(duration)); elapsedNanos.addAndGet(duration.toNanos()); }
    }
}
