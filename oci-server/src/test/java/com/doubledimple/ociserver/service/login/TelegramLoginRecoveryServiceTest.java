package com.doubledimple.ociserver.service.login;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.doubledimple.dao.entity.*;
import com.doubledimple.dao.repository.*;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.LoginAttemptService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.message.MessageService;
import com.doubledimple.ociserver.service.message.TelegramMessageService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.security.LoginIpTransactions;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.aopalliance.intercept.MethodInterceptor;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.dao.support.PersistenceExceptionTranslationInterceptor;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.SharedEntityManagerCreator;
import org.springframework.orm.jpa.vendor.HibernateJpaDialect;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.slf4j.LoggerFactory;

import javax.persistence.EntityManager;
import java.security.SecureRandom;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static com.doubledimple.ociserver.service.login.TelegramLoginRecoveryService.RecoveryResult.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Real isolated H2 transactions and persisted tenant aliases; every notification transport is a mock. */
class TelegramLoginRecoveryServiceTest {
    private static final String USER = "Recovery.Owner";
    private static final String TENANT = "Imported Account";
    private static final String ALIAS = "Primary Tenant";
    private static final String BOT = "fixture-bot-token";
    private static final String IP = "198.51.100.71";
    private static final long CHAT = 1234567L;
    private static LocalContainerEntityManagerFactoryBean factory;
    private static JpaTransactionManager transactions;
    private static EntityManager entityManager;
    private static SystemConfigRepository configs;
    private static LoginUserRepository users;
    private static TenantRepository tenants;
    private static CloudTenancyRepository aliases;
    private static LoginFailureStateRepository ipFailures;
    private static BanRecordRepository ipBans;
    private static final Map<Logger, Level> originalLogLevels = new LinkedHashMap<>();
    private MutableClock clock;
    private GlobalLoginLockNotifier notifier;
    private GlobalLoginGuard guard;
    private final List<GlobalLoginGuard.LockEvent> alerts = new CopyOnWriteArrayList<>();

    @BeforeAll
    static void startDatabase() {
        // Verbose row-lock logging can itself dominate the timeout in the concurrent H2 checks.
        for (String name : Arrays.asList("org.hibernate", "org.springframework")) {
            Logger logger = (Logger) LoggerFactory.getLogger(name);
            originalLogLevels.put(logger, logger.getLevel());
            logger.setLevel(Level.WARN);
        }
        factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource("jdbc:h2:mem:telegram_recovery_" + UUID.randomUUID()
                + ";DB_CLOSE_DELAY=-1;LOCK_TIMEOUT=10000", "sa", ""));
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        factory.setPackagesToScan(SystemConfig.class.getPackage().getName());
        factory.setPersistenceUnitPostProcessors(unit -> {
            unit.getManagedClassNames().clear();
            for (Class<?> entity : Arrays.asList(SystemConfig.class, LoginUser.class, Tenant.class,
                    CloudTenancy.class, BootInstance.class, LoginFailureState.class, BanRecord.class)) {
                unit.addManagedClassName(entity.getName());
            }
        });
        Properties properties = new Properties();
        properties.setProperty("hibernate.hbm2ddl.auto", "create-drop");
        properties.setProperty("hibernate.dialect", "org.hibernate.dialect.H2Dialect");
        factory.setJpaProperties(properties);
        factory.afterPropertiesSet();
        assertNotNull(factory.getObject());
        assertEquals(7, factory.getObject().getMetamodel().getEntities().size());
        transactions = new JpaTransactionManager(factory.getObject());
        entityManager = SharedEntityManagerCreator.createSharedEntityManager(factory.getObject());
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(entityManager);
        ProxyFactory translated = new ProxyFactory(repositories.getRepository(SystemConfigRepository.class));
        translated.addAdvice(new PersistenceExceptionTranslationInterceptor(new HibernateJpaDialect()));
        configs = (SystemConfigRepository) translated.getProxy();
        users = repositories.getRepository(LoginUserRepository.class);
        tenants = repositories.getRepository(TenantRepository.class);
        aliases = repositories.getRepository(CloudTenancyRepository.class);
        ipFailures = repositories.getRepository(LoginFailureStateRepository.class);
        ipBans = repositories.getRepository(BanRecordRepository.class);
    }

    @AfterAll
    static void stopDatabase() {
        try { if (factory != null) factory.destroy(); }
        finally { originalLogLevels.forEach(Logger::setLevel); originalLogLevels.clear(); }
    }

    @BeforeEach
    void prepare() {
        new TransactionTemplate(transactions).execute(status -> {
            configs.deleteAll(); users.deleteAll(); tenants.deleteAll(); aliases.deleteAll();
            ipFailures.deleteAll(); ipBans.deleteAll();
            entityManager.flush();
            entityManager.clear();
            LoginUser user = new LoginUser();
            user.setUsername(USER);
            user.setPassword("independent-password-hash-not-a-recovery-code");
            user.setExportVerificationDate(LocalDate.of(2026, 10, 24));
            user.setExportVerificationWrongCount(2);
            users.saveAndFlush(user);
            Tenant tenant = new Tenant();
            tenant.setId(71L);
            tenant.setUserName(TENANT);
            tenant.setTenancyName("Oracle-main");
            tenant.setTenancy("ocid1.tenancy.fixture");
            tenant.setTenantId("ocid1.user.fixture");
            tenant.setCloudType(1);
            tenants.saveAndFlush(tenant);
            CloudTenancy alias = new CloudTenancy();
            alias.setTenancyName(tenant.getTenancy());
            alias.setCloudType(1);
            alias.setType(1);
            alias.setDefName(ALIAS);
            aliases.saveAndFlush(alias);
            return null;
        });
        configure("telegram.bot.token", BOT, false);
        configure("telegram.chat.id", String.valueOf(CHAT), false);
        configure("telegram.enabled", "", true);
        clock = new MutableClock(Instant.parse("2026-10-24T15:59:30Z"));
        alerts.clear();
        notifier = mock(GlobalLoginLockNotifier.class);
        doAnswer(call -> { alerts.add(call.getArgument(0)); return null; }).when(notifier).notifyBlocked(any());
        guard = newGuard(transactions);
    }

    @Test
    void aHighEntropyCodeIsOnlyHashedInStorageAndWorksAfterServiceReconstruction() {
        String code = block();

        assertTrue(code.matches("LGR-[A-Za-z0-9_-]{43}"));
        String persisted = stored().getValue();
        assertTrue(persisted.startsWith("v3|3|"));
        assertFalse(persisted.contains(BOT));
        for (SystemConfig config : configs.findAll()) assertFalse(config.getValue().contains(code));

        assertEquals(SUCCESS, recover(newGuard(transactions), USER, code, TENANT));
        assertEquals("v2|0|", stored().getValue());
        assertFalse(stored().isEnabled());
        assertEquals(REJECTED, recover(newGuard(transactions), USER, code, TENANT));
    }

    @ParameterizedTest
    @ValueSource(strings = {TENANT, "Oracle-main", ALIAS})
    void existingTenantNamesAndTheActualPersistedAliasCanRecover(String name) {
        String code = block();
        assertEquals(SUCCESS, recover(guard, USER, code, name));
        assertFalse(newGuard(transactions).status().isBlocked());
    }

    @ParameterizedTest
    @ValueSource(strings = {"username", "code", "tenant-case", "tenant-substring", "ocid", "password", "orphan-alias", "instance-alias", "other-cloud-alias", "deleted-tenant"})
    void incorrectFactorsAndUnrelatedOrStaleAliasesHaveTheSameRejection(String mismatch) {
        String code = block();
        String username = USER;
        String suppliedCode = code;
        String tenant = TENANT;
        switch (mismatch) {
            case "username": username = "recovery.owner"; break;
            case "code": suppliedCode = code.substring(0, 46) + (code.endsWith("A") ? "B" : "A"); break;
            case "tenant-case": tenant = "imported account"; break;
            case "tenant-substring": tenant = "Imported"; break;
            case "ocid": tenant = "ocid1.tenancy.fixture"; break;
            case "password": suppliedCode = "independent-password-hash-not-a-recovery-code"; break;
            case "deleted-tenant":
                new TransactionTemplate(transactions).execute(status -> { tenants.deleteAll(); return null; });
                tenant = ALIAS;
                break;
            default:
                final String kind = mismatch;
                new TransactionTemplate(transactions).execute(status -> {
                    CloudTenancy alias = aliases.findAll().get(0);
                    if ("orphan-alias".equals(kind)) alias.setTenancyName("missing-tenant");
                    if ("instance-alias".equals(kind)) alias.setType(2);
                    if ("other-cloud-alias".equals(kind)) alias.setCloudType(2);
                    aliases.saveAndFlush(alias);
                    return null;
                });
                tenant = ALIAS;
        }

        assertEquals(REJECTED, recover(guard, username, suppliedCode, tenant));
        assertTrue(newGuard(transactions).status().isBlocked());
    }

    @Test
    void failedAttemptsCommitAcrossRollbackAndRestartAndTheCooldownStartsAtTheFifthFailure() {
        String code = block();
        new TransactionTemplate(transactions).execute(status -> {
            assertEquals(REJECTED, recover(guard, USER, "wrong", TENANT));
            status.setRollbackOnly();
            return null;
        });
        // The first four failures do not age out while the owner is still gathering the correct factors.
        clock.advance(Duration.ofMinutes(16));
        for (int attempt = 1; attempt < 4; attempt++) {
            assertEquals(REJECTED, recover(newGuard(transactions), USER, "wrong", TENANT));
        }
        assertEquals(RATE_LIMITED, recover(newGuard(transactions), USER, "wrong", TENANT));
        assertEquals(RATE_LIMITED, recover(newGuard(transactions), USER, code, TENANT));
        clock.advance(Duration.ofMinutes(15).minusNanos(1));
        assertEquals(RATE_LIMITED, recover(newGuard(transactions), USER, code, TENANT));
        clock.advance(Duration.ofNanos(1));
        assertEquals(SUCCESS, recover(newGuard(transactions), USER, code, TENANT));
    }

    @ParameterizedTest
    @ValueSource(strings = {"disabled", "missing-token", "group-chat", "missing-chat"})
    void aMissingPrivateTelegramBindingStillCommitsTheLockWithoutCreatingARecoverySecret(String setting) {
        if ("disabled".equals(setting)) configure("telegram.enabled", "", false);
        if ("missing-token".equals(setting)) configure("telegram.bot.token", "", false);
        if ("group-chat".equals(setting)) configure("telegram.chat.id", "-1234567", false);
        if ("missing-chat".equals(setting)) configure("telegram.chat.id", "", false);

        guard.recordCredentialFailure();
        guard.recordCredentialFailure();
        assertTrue(assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::recordCredentialFailure).isBlocked());

        assertEquals("v2|3|" + clock.instant().plus(Duration.ofHours(100)), stored().getValue());
        assertEquals(1, alerts.size());
        assertNull(alerts.get(0).getRecoveryCode());
        assertTrue(newGuard(transactions).status().isBlocked());
    }

    @Test
    void anExistingVersionTwoLockDoesNotMintOrResendARecoveryCodeWhenTelegramIsEnabled() {
        configure(GlobalLoginGuard.STATE_KEY, "v2|3|" + clock.instant().plus(Duration.ofHours(100)), true);
        assertTrue(newGuard(transactions).status().isBlocked());
        assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::recordCredentialFailure);
        assertTrue(alerts.isEmpty());
        assertEquals(REJECTED, recover(guard, USER, "LGR-" + "A".repeat(43), TENANT));
    }

    @Test
    void aTelegramConfigurationReadFailureCannotRollBackTheThirdCredentialFailure() {
        ProxyFactory unavailableTelegram = new ProxyFactory(configs);
        unavailableTelegram.addAdvice((MethodInterceptor) call -> {
            if ("findByKey".equals(call.getMethod().getName()) && "telegram.enabled".equals(call.getArguments()[0])) {
                assertFalse(TransactionSynchronizationManager.isActualTransactionActive(),
                        "Optional notification configuration must not poison the lock's write transaction");
                throw new IllegalStateException("private Telegram configuration failure");
            }
            return call.proceed();
        });
        ReflectionTestUtils.setField(guard, "configs", unavailableTelegram.getProxy());
        guard.recordCredentialFailure();
        guard.recordCredentialFailure();

        assertTrue(assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::recordCredentialFailure).isBlocked());
        assertEquals("v2|3|" + clock.instant().plus(Duration.ofHours(100)), stored().getValue());
        assertEquals(1, alerts.size());
        assertNull(alerts.get(0).getRecoveryCode());
    }

    @Test
    void concurrentValidRequestsConsumeTheCodeExactlyOnce() throws Exception {
        String code = block();
        List<TelegramLoginRecoveryService.RecoveryResult> results = race(8,
                () -> recover(newGuard(transactions), USER, code, ALIAS));
        assertEquals(1, results.stream().filter(result -> result == SUCCESS).count());
        assertEquals(7, results.stream().filter(result -> result == REJECTED).count());
        assertEquals("v2|0|", stored().getValue());
    }

    @Test
    void concurrentInvalidRequestsCannotLoseThePersistentAttemptLimit() throws Exception {
        String code = block();
        List<TelegramLoginRecoveryService.RecoveryResult> results = race(8,
                () -> recover(newGuard(transactions), USER, "wrong", TENANT));
        assertTrue(results.stream().noneMatch(result -> result == SUCCESS || result == UNAVAILABLE));
        assertEquals(RATE_LIMITED, recover(newGuard(transactions), USER, code, TENANT));
        assertTrue(guard.status().isBlocked());
    }

    @Test
    void aConsumedCodeCannotUnlockTheNextLockAndOnlyItsNewCodeWorks() {
        String oldCode = block();
        assertEquals(SUCCESS, recover(guard, USER, oldCode, TENANT));
        String newCode = block();
        assertNotEquals(oldCode, newCode);
        assertEquals(REJECTED, recover(newGuard(transactions), USER, oldCode, TENANT));
        assertTrue(guard.status().isBlocked());
        assertEquals(SUCCESS, recover(newGuard(transactions), USER, newCode, TENANT));
    }

    @Test
    void anExpiredCodeCannotUnlockAnExpiredOrSubsequentLock() {
        String oldCode = block();
        clock.advance(Duration.ofHours(100));
        assertEquals(REJECTED, recover(newGuard(transactions), USER, oldCode, TENANT));
        assertFalse(guard.status().isBlocked());
        String newCode = block();
        assertEquals(REJECTED, recover(newGuard(transactions), USER, oldCode, TENANT));
        assertEquals(SUCCESS, recover(newGuard(transactions), USER, newCode, TENANT));
    }

    @ParameterizedTest
    @ValueSource(strings = {"chat", "sender", "token", "changed-config-token", "changed-config-chat", "disabled"})
    void recoveryIsBoundToTheConfiguredPrivateChatSenderAndCurrentBot(String mismatch) {
        String code = block();
        long chat = CHAT;
        long sender = CHAT;
        String token = BOT;
        if ("chat".equals(mismatch)) chat = CHAT + 1;
        if ("sender".equals(mismatch)) sender = CHAT + 1;
        if ("token".equals(mismatch)) token = "other-token";
        if ("changed-config-token".equals(mismatch)) configure("telegram.bot.token", "new-token", false);
        if ("changed-config-chat".equals(mismatch)) configure("telegram.chat.id", String.valueOf(CHAT + 1), false);
        if ("disabled".equals(mismatch)) configure("telegram.enabled", "", false);
        for (int attempt = 0; attempt < 6; attempt++) {
            assertEquals(REJECTED, service(guard).recover(chat, sender, token, USER, code, TENANT));
        }
        assertTrue(guard.status().isBlocked());
        if (Arrays.asList("chat", "sender", "token").contains(mismatch)) {
            assertEquals(SUCCESS, recover(guard, USER, code, TENANT), "An unrelated sender must not consume the owner's attempt budget");
        }
    }

    @Test
    void successfulRecoveryDoesNotRemoveIndependentIpBansOrTheExportFailureCount() {
        LoginAttemptService ipGuard = new LoginAttemptService(ipFailures, ipBans, new LoginIpTransactions(transactions));
        ipGuard.recordFailure(IP, false);
        ipGuard.recordFailure(IP, false);
        ipGuard.recordFailure(IP, false);
        assertThrows(IpBannedException.class, () -> ipGuard.assertAllowed(IP));
        String code = block();

        assertEquals(SUCCESS, recover(guard, USER, code, ALIAS));

        assertThrows(IpBannedException.class, () -> ipGuard.assertAllowed(IP));
        assertEquals(3, ipFailures.findById(IP).orElseThrow(AssertionError::new).getWrongPasswordCount());
        LoginUser persisted = users.findByUsername(USER).orElseThrow(AssertionError::new);
        assertEquals(2, persisted.getExportVerificationWrongCount());
        assertEquals(LocalDate.of(2026, 10, 24), persisted.getExportVerificationDate());
    }

    @Test
    void aFailedRecoveryCommitPreservesTheLockAndLeavesTheCodeUsableForRetry() {
        String code = block();
        AtomicInteger commits = new AtomicInteger();
        JpaTransactionManager failing = new JpaTransactionManager(factory.getObject()) {
            @Override protected void doCommit(DefaultTransactionStatus status) {
                if (commits.incrementAndGet() == 2) throw new TransactionSystemException("private recovery commit detail");
                super.doCommit(status);
            }
        };
        failing.setRollbackOnCommitFailure(true);

        assertEquals(UNAVAILABLE, recover(newGuard(failing), USER, code, TENANT));
        assertTrue(guard.status().isBlocked());
        assertEquals(SUCCESS, recover(newGuard(transactions), USER, code, TENANT));
    }

    @ParameterizedTest
    @ValueSource(strings = {"user", "tenant"})
    void identityLookupFailuresCannotUnlockTheSiteOrExposeDatabaseDetails(String lookup) {
        String code = block();
        TelegramLoginRecoveryService service = service(guard);
        if ("user".equals(lookup)) {
            LoginUserRepository broken = mock(LoginUserRepository.class);
            when(broken.existsByUsername(USER)).thenThrow(new IllegalStateException("private account database content"));
            ReflectionTestUtils.setField(service, "loginUserRepository", broken);
        } else {
            TenantRepository broken = mock(TenantRepository.class);
            when(broken.countByRecoveryName(TENANT)).thenThrow(new IllegalStateException("private tenant database content"));
            ReflectionTestUtils.setField(service, "tenantRepository", broken);
        }

        assertEquals(UNAVAILABLE, service.recover(CHAT, CHAT, BOT, USER, code, TENANT));
        assertTrue(guard.status().isBlocked());
        assertEquals(SUCCESS, recover(newGuard(transactions), USER, code, TENANT));
    }

    @Test
    void recoveryCodeIsSentOnlyToTheBoundTelegramDestinationAndNeverToTheFanout() {
        MessageService fanout = mock(MessageService.class);
        MessageFactory messages = mock(MessageFactory.class);
        when(messages.getType(MessageEnum.TELEGRAM)).thenReturn(fanout);
        TelegramMessageService privateTelegram = mock(TelegramMessageService.class);
        SystemConfigService settings = mock(SystemConfigService.class);
        when(settings.getSiteLogoName()).thenReturn("Recovery fixture");
        GlobalLoginLockNotifier realNotifier = new GlobalLoginLockNotifier();
        ReflectionTestUtils.setField(realNotifier, "systemConfigService", settings);
        ReflectionTestUtils.setField(realNotifier, "messageFactory", messages);
        ReflectionTestUtils.setField(realNotifier, "telegramMessageService", privateTelegram);
        ReflectionTestUtils.setField(realNotifier, "notificationExecutor", (java.util.concurrent.Executor) Runnable::run);
        doAnswer(call -> {
            GlobalLoginGuard.LockEvent event = call.getArgument(0);
            alerts.add(event);
            realNotifier.notifyBlocked(event);
            return null;
        }).when(notifier).notifyBlocked(any());

        String code = block();

        ArgumentCaptor<String> publicContent = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> privateContent = ArgumentCaptor.forClass(String.class);
        verify(fanout).sendMessageTemplateText(publicContent.capture(), eq(Boolean.FALSE));
        verify(privateTelegram).sendPrivateRecoveryMessage(privateContent.capture(), eq(CHAT), eq(alerts.get(0).getRecoveryBotTokenHash()));
        assertFalse(publicContent.getValue().contains(code));
        assertTrue(privateContent.getValue().contains(code));
        verifyNoMoreInteractions(fanout, privateTelegram);
    }

    private String block() {
        int before = alerts.size();
        guard.recordCredentialFailure();
        guard.recordCredentialFailure();
        assertTrue(assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::recordCredentialFailure).isBlocked());
        assertEquals(before + 1, alerts.size());
        String code = alerts.get(before).getRecoveryCode();
        assertNotNull(code);
        return code;
    }

    private GlobalLoginGuard newGuard(JpaTransactionManager manager) {
        SecureRandom random = new SecureRandom() { @Override public int nextInt(int bound) { assertEquals(925, bound); return 0; } };
        GlobalLoginGuard result = new GlobalLoginGuard(configs, manager, clock, random);
        ReflectionTestUtils.setField(result, "entityManager", entityManager);
        ReflectionTestUtils.setField(result, "lockNotifier", notifier);
        return result;
    }

    private TelegramLoginRecoveryService service(GlobalLoginGuard activeGuard) {
        TelegramLoginRecoveryService result = new TelegramLoginRecoveryService();
        ReflectionTestUtils.setField(result, "globalLoginGuard", activeGuard);
        ReflectionTestUtils.setField(result, "loginUserRepository", users);
        ReflectionTestUtils.setField(result, "tenantRepository", tenants);
        return result;
    }

    private TelegramLoginRecoveryService.RecoveryResult recover(GlobalLoginGuard activeGuard, String username, String code, String tenant) {
        return service(activeGuard).recover(CHAT, CHAT, BOT, username, code, tenant);
    }

    private void configure(String key, String value, boolean enabled) {
        new TransactionTemplate(transactions).execute(status -> {
            SystemConfig row = configs.findByKey(key).orElseGet(SystemConfig::new);
            row.setKey(key); row.setValue(value); row.setEnabled(enabled);
            configs.saveAndFlush(row);
            return null;
        });
    }

    private SystemConfig stored() {
        return configs.findByKey(GlobalLoginGuard.STATE_KEY).orElseThrow(AssertionError::new);
    }

    private <T> List<T> race(int count, Callable<T> attempt) throws Exception {
        ExecutorService workers = Executors.newFixedThreadPool(count);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Future<T>> futures = new ArrayList<>();
            for (int i = 0; i < count; i++) futures.add(workers.submit(() -> { assertTrue(start.await(5, TimeUnit.SECONDS)); return attempt.call(); }));
            start.countDown();
            List<T> result = new ArrayList<>();
            for (Future<T> future : futures) result.add(future.get(30, TimeUnit.SECONDS));
            return result;
        } finally {
            workers.shutdownNow();
            assertTrue(workers.awaitTermination(5, TimeUnit.SECONDS));
        }
    }

    private static final class MutableClock extends Clock {
        private final AtomicReference<Instant> current;
        private MutableClock(Instant now) { current = new AtomicReference<>(now); }
        @Override public ZoneId getZone() { return ZoneId.of("Asia/Shanghai"); }
        @Override public Clock withZone(ZoneId zone) { return Clock.fixed(instant(), zone); }
        @Override public Instant instant() { return current.get(); }
        private void advance(Duration duration) { current.updateAndGet(now -> now.plus(duration)); }
    }
}
