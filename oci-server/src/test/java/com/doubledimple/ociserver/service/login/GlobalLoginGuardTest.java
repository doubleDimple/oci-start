package com.doubledimple.ociserver.service.login;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.entity.LoginFailureState;
import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.dao.repository.LoginFailureStateRepository;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.service.LoginAttemptService;
import com.doubledimple.ociserver.service.security.LoginIpTransactions;
import org.aopalliance.intercept.MethodInterceptor;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
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

import javax.persistence.EntityManager;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/** Three security entities and real H2 row locks/commits; session callbacks never access external services. */
class GlobalLoginGuardTest {
    private static final String IP = "198.51.100.42";
    private static LocalContainerEntityManagerFactoryBean factory;
    private static JpaTransactionManager transactions;
    private static EntityManager entityManager;
    private static SystemConfigRepository configs;
    private static LoginFailureStateRepository ipFailures;
    private static BanRecordRepository ipBans;
    private MutableClock clock;
    private GlobalLoginGuard guard;

    @BeforeAll
    static void startDatabase() {
        factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource("jdbc:h2:mem:global_login_" + UUID.randomUUID()
                + ";DB_CLOSE_DELAY=-1;LOCK_TIMEOUT=10000", "sa", ""));
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        factory.setPackagesToScan(SystemConfig.class.getPackage().getName());
        factory.setPersistenceUnitPostProcessors(unit -> {
            unit.getManagedClassNames().clear();
            unit.addManagedClassName(SystemConfig.class.getName());
            unit.addManagedClassName(LoginFailureState.class.getName());
            unit.addManagedClassName(BanRecord.class.getName());
        });
        Properties properties = new Properties();
        properties.setProperty("hibernate.hbm2ddl.auto", "create-drop");
        properties.setProperty("hibernate.dialect", "org.hibernate.dialect.H2Dialect");
        factory.setJpaProperties(properties);
        factory.afterPropertiesSet();
        assertNotNull(factory.getObject());
        assertEquals(3, factory.getObject().getMetamodel().getEntities().size());
        transactions = new JpaTransactionManager(factory.getObject());
        entityManager = SharedEntityManagerCreator.createSharedEntityManager(factory.getObject());
        SystemConfigRepository repository = new JpaRepositoryFactory(entityManager).getRepository(SystemConfigRepository.class);
        ProxyFactory proxy = new ProxyFactory(repository);
        proxy.addAdvice(new PersistenceExceptionTranslationInterceptor(new HibernateJpaDialect()));
        configs = (SystemConfigRepository) proxy.getProxy();
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(entityManager);
        ipFailures = repositories.getRepository(LoginFailureStateRepository.class);
        ipBans = repositories.getRepository(BanRecordRepository.class);
    }

    @AfterAll
    static void stopDatabase() { if (factory != null) factory.destroy(); }

    @BeforeEach
    void prepare() {
        new TransactionTemplate(transactions).execute(status -> {
            configs.deleteAll(); ipFailures.deleteAll(); ipBans.deleteAll(); return null;
        });
        clock = new MutableClock(Instant.parse("2026-10-24T15:59:30Z")); // 30 seconds before local midnight.
        guard = newGuard(configs, transactions);
    }

    @Test
    void threeConcurrentFailuresInitializeOnceAndPersistTheGlobalBlock() throws Exception {
        CyclicBarrier emptyReads = new CyclicBarrier(3);
        ProxyFactory racing = new ProxyFactory(configs);
        racing.addAdvice((MethodInterceptor) invocation -> {
            Object result = invocation.proceed();
            if ("existsByKey".equals(invocation.getMethod().getName()) && Boolean.FALSE.equals(result)) {
                emptyReads.await(10, TimeUnit.SECONDS);
            }
            return result;
        });
        SystemConfigRepository concurrentRepository = (SystemConfigRepository) racing.getProxy();
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService workers = Executors.newFixedThreadPool(3);
        List<Throwable> results = new ArrayList<>();
        try {
            List<Future<Throwable>> attempts = new ArrayList<>();
            for (int index = 0; index < 3; index++) {
                attempts.add(workers.submit(() -> {
                    assertTrue(start.await(5, TimeUnit.SECONDS));
                    try { newGuard(concurrentRepository, transactions).recordCredentialFailure(); return null; }
                    catch (Throwable failure) { return failure; }
                }));
            }
            start.countDown();
            for (Future<Throwable> attempt : attempts) results.add(attempt.get(25, TimeUnit.SECONDS));
        } finally {
            workers.shutdownNow();
            assertTrue(workers.awaitTermination(5, TimeUnit.SECONDS));
        }

        assertEquals(2, results.stream().filter(value -> value == null).count(), results.toString());
        Throwable rejected = results.stream().filter(value -> value != null).findFirst().orElseThrow(AssertionError::new);
        assertTrue(assertInstanceOf(GlobalLoginGuard.LoginGuardException.class, rejected).isBlocked());
        assertEquals(1L, new TransactionTemplate(transactions).execute(status -> configs.count()).longValue());
        assertEquals("2026-10-24|3", stored().getValue());
        assertTrue(stored().isEnabled());
        assertTrue(newGuard(configs, transactions).status().isBlocked());
    }

    @Test
    void theThirdFailureSurvivesItsCallersRollbackAndAServiceReconstruction() {
        guard.recordCredentialFailure();
        newGuard(configs, transactions).recordCredentialFailure();
        assertThrows(IllegalStateException.class, () -> new TransactionTemplate(transactions).execute(status -> {
            GlobalLoginGuard.LoginGuardException failure = assertThrows(GlobalLoginGuard.LoginGuardException.class,
                    guard::recordCredentialFailure);
            assertTrue(failure.isBlocked());
            throw new IllegalStateException("rollback the rejected login transaction");
        }));

        assertTrue(newGuard(configs, transactions).status().isBlocked());
        assertEquals("2026-10-24|3", stored().getValue());
    }

    @Test
    void onlyACompleteSuccessfulLoginResetsAnUnblockedConsecutiveSequence() {
        guard.recordCredentialFailure();
        guard.recordCredentialFailure();
        AtomicBoolean created = new AtomicBoolean();
        guard.completeLogin(() -> created.set(true), () -> fail("Successful login must retain its session"));

        assertTrue(created.get());
        assertEquals("2026-10-24|0", stored().getValue());
        guard.recordCredentialFailure();
        guard.recordCredentialFailure();
        assertDoesNotThrow(guard::assertAllowed);
        assertTrue(assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::recordCredentialFailure).isBlocked());
    }

    @Test
    void finalAuthenticationRechecksTheLockAndDoesNotLogOutAnExistingSession() {
        guard.assertAllowed(); // A request passed the initial check before other requests reached the limit.
        block();

        GlobalLoginGuard.LoginGuardException failure = assertThrows(GlobalLoginGuard.LoginGuardException.class,
                () -> newGuard(configs, transactions).completeLogin(
                        () -> fail("No new session may be issued after the global lock"),
                        () -> fail("A rejected new login must not remove an existing session")));

        assertTrue(failure.isBlocked());
        assertEquals(GlobalLoginGuardTestSupport.BLOCKED_MESSAGE, failure.getMessage());
        assertEquals("2026-10-25T00:00+08:00", failure.getBlockedUntil());
        assertEquals("2026-10-24|3", stored().getValue());
    }

    @Test
    void midnightAutomaticallyRestoresLoginAndStartsANewSequence() {
        block();
        LoginAttemptService attempts = new LoginAttemptService(ipFailures, ipBans, new LoginIpTransactions(transactions));
        for (int index = 0; index < 3; index++) attempts.recordFailure(IP, false);
        clock.advance(Duration.ofSeconds(29));
        assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::assertAllowed);
        clock.advance(Duration.ofSeconds(1));

        assertDoesNotThrow(() -> newGuard(configs, transactions).assertAllowed());
        assertEquals("2026-10-25|0", stored().getValue());
        assertFalse(stored().isEnabled());
        assertThrows(IpBannedException.class, () -> attempts.assertAllowed(IP));
        guard.recordCredentialFailure();
        assertEquals("2026-10-25|1", stored().getValue());
    }

    @Test
    void failedSessionCreationDoesNotClearTheSequenceAndCleansUpAPartialSession() {
        guard.recordCredentialFailure();
        AtomicBoolean undone = new AtomicBoolean();
        GlobalLoginGuard.LoginGuardException failure = assertThrows(GlobalLoginGuard.LoginGuardException.class,
                () -> guard.completeLogin(() -> { throw new IllegalStateException("private session storage detail"); },
                        () -> undone.set(true)));

        assertTrue(undone.get());
        assertFalse(failure.getMessage().contains("private session"));
        assertEquals("2026-10-24|1", stored().getValue());
    }

    @Test
    void aFailedCommitRevokesTheCreatedSessionAndRollsBackTheCounterReset() {
        guard.recordCredentialFailure();
        LoginIpTransactions ipTransactions = new LoginIpTransactions(transactions);
        new LoginAttemptService(ipFailures, ipBans, ipTransactions).recordFailure(IP, false);
        LoginFailureGuard ipGuard = ipGuard(ipBans, ipTransactions);
        AtomicInteger commits = new AtomicInteger();
        JpaTransactionManager failingCommit = new JpaTransactionManager(factory.getObject()) {
            @Override protected void doCommit(DefaultTransactionStatus status) {
                // The first commit is the independent existing-row initialization check.
                if (commits.incrementAndGet() == 2) throw new TransactionSystemException("private commit detail");
                super.doCommit(status);
            }
        };
        failingCommit.setRollbackOnCommitFailure(true);
        AtomicBoolean created = new AtomicBoolean();
        AtomicBoolean undone = new AtomicBoolean();

        GlobalLoginGuard.LoginGuardException failure = assertThrows(GlobalLoginGuard.LoginGuardException.class,
                () -> ipGuard.withLoginLock(IP, () -> newGuard(configs, failingCommit).completeLogin(() -> {
                    created.set(true);
                    ipGuard.loginSucceededInCurrentTransaction(IP);
                }, () -> undone.set(true))));

        assertTrue(created.get());
        assertTrue(undone.get());
        assertFalse(failure.getMessage().contains("private commit"));
        assertEquals("2026-10-24|1", stored().getValue());
        assertEquals(1, new TransactionTemplate(transactions).execute(status -> ipFailures.findById(IP)
                .orElseThrow(AssertionError::new).getWrongPasswordCount()).intValue());
    }

    @Test
    void anUnreadablePersistedStateFailsClosedWithoutExposingItsContents() {
        guard.assertAllowed();
        new TransactionTemplate(transactions).execute(status -> {
            SystemConfig row = configs.findByKey(GlobalLoginGuard.STATE_KEY).orElseThrow(AssertionError::new);
            row.setValue("private-invalid-state");
            configs.saveAndFlush(row);
            return null;
        });

        GlobalLoginGuard.LoginGuardException failure = assertThrows(GlobalLoginGuard.LoginGuardException.class,
                guard::assertAllowed);
        assertFalse(failure.isBlocked());
        assertFalse(failure.getMessage().contains("private-invalid-state"));
        assertThrows(GlobalLoginGuard.LoginGuardException.class, () -> guard.completeLogin(
                () -> fail("An unreadable state must prevent session creation"),
                () -> fail("No existing session should be removed")));
        assertEquals("private-invalid-state", stored().getValue());
    }

    @Test
    void anIndependentIpBanAtCompletionIsPreservedAndRevokesTheAttemptedSession() {
        guard.recordCredentialFailure();
        IpBannedException ban = new IpBannedException("independent IP ban");
        AtomicBoolean undone = new AtomicBoolean();

        IpBannedException failure = assertThrows(IpBannedException.class, () -> guard.completeLogin(
                () -> { throw ban; }, () -> undone.set(true)));

        assertSame(ban, failure);
        assertTrue(undone.get());
        assertEquals("2026-10-24|1", stored().getValue());
    }

    @Test
    void aCompletedLoginClearsBothGlobalAndIpFailuresInItsCommittedTransaction() {
        guard.recordCredentialFailure();
        LoginIpTransactions ipTransactions = new LoginIpTransactions(transactions);
        new LoginAttemptService(ipFailures, ipBans, ipTransactions).recordFailure(IP, false);
        LoginFailureGuard ipGuard = ipGuard(ipBans, ipTransactions);
        AtomicBoolean session = new AtomicBoolean();

        ipGuard.withLoginLock(IP, () -> guard.completeLogin(() -> {
            session.set(true);
            ipGuard.loginSucceededInCurrentTransaction(IP);
        }, () -> session.set(false)));

        assertTrue(session.get());
        assertEquals("2026-10-24|0", stored().getValue());
        assertFalse(new TransactionTemplate(transactions).execute(status -> ipFailures.existsById(IP)).booleanValue());
    }

    @Test
    void anIpBanCommittingDuringAuthenticationWinsBeforeTheFinalSessionCanSurvive() throws Exception {
        guard.recordCredentialFailure();
        LoginIpTransactions ipTransactions = new LoginIpTransactions(transactions);
        CountDownLatch banWritten = new CountDownLatch(1);
        CountDownLatch finishBan = new CountDownLatch(1);
        ProxyFactory banProxy = new ProxyFactory(ipBans);
        banProxy.addAdvice((MethodInterceptor) invocation -> {
            Object result = invocation.proceed();
            if ("save".equals(invocation.getMethod().getName())) {
                banWritten.countDown();
                assertTrue(finishBan.await(10, TimeUnit.SECONDS));
            }
            return result;
        });
        BanRecordRepository delayedBans = (BanRecordRepository) banProxy.getProxy();
        LoginAttemptService attempts = new LoginAttemptService(ipFailures, delayedBans, ipTransactions);
        LoginFailureGuard ipGuard = ipGuard(delayedBans, ipTransactions);
        attempts.recordFailure(IP, false);
        attempts.recordFailure(IP, false);
        AtomicBoolean session = new AtomicBoolean();
        CountDownLatch completing = new CountDownLatch(1);
        ExecutorService workers = Executors.newFixedThreadPool(2);
        try {
            Future<?> banning = workers.submit(() -> attempts.recordFailure(IP, false));
            assertTrue(banWritten.await(5, TimeUnit.SECONDS));
            Future<Throwable> login = workers.submit(() -> {
                completing.countDown();
                try {
                    ipGuard.withLoginLock(IP, () -> guard.completeLogin(() -> {
                        session.set(true);
                        ipGuard.loginSucceededInCurrentTransaction(IP);
                    }, () -> session.set(false)));
                    return null;
                } catch (Throwable failure) { return failure; }
            });
            assertTrue(completing.await(5, TimeUnit.SECONDS));
            finishBan.countDown();
            banning.get(15, TimeUnit.SECONDS);
            assertInstanceOf(IpBannedException.class, login.get(15, TimeUnit.SECONDS));
        } finally {
            finishBan.countDown();
            workers.shutdownNow();
            assertTrue(workers.awaitTermination(5, TimeUnit.SECONDS));
        }
        assertFalse(session.get());
        assertEquals("2026-10-24|1", stored().getValue());
        assertThrows(IpBannedException.class, () -> attempts.assertAllowed(IP));
        assertEquals(3, new TransactionTemplate(transactions).execute(status -> ipFailures.findById(IP)
                .orElseThrow(AssertionError::new).getWrongPasswordCount()).intValue());
    }

    private LoginFailureGuard ipGuard(BanRecordRepository repository, LoginIpTransactions ipTransactions) {
        LoginFailureGuard result = new LoginFailureGuard();
        ReflectionTestUtils.setField(result, "loginAttemptService", new LoginAttemptService(ipFailures, repository, ipTransactions));
        return result;
    }

    private void block() {
        guard.recordCredentialFailure();
        guard.recordCredentialFailure();
        assertThrows(GlobalLoginGuard.LoginGuardException.class, guard::recordCredentialFailure);
    }

    private GlobalLoginGuard newGuard(SystemConfigRepository repository, JpaTransactionManager manager) {
        GlobalLoginGuard created = new GlobalLoginGuard(repository, manager, clock);
        ReflectionTestUtils.setField(created, "entityManager", entityManager);
        return created;
    }

    private SystemConfig stored() {
        return new TransactionTemplate(transactions).execute(status -> configs.findByKey(GlobalLoginGuard.STATE_KEY)
                .orElseThrow(AssertionError::new));
    }

    private static final class MutableClock extends Clock {
        private final AtomicReference<Instant> current;
        private MutableClock(Instant instant) { current = new AtomicReference<>(instant); }
        @Override public ZoneId getZone() { return ZoneId.of("Asia/Shanghai"); }
        @Override public Clock withZone(ZoneId zone) { return Clock.fixed(instant(), zone); }
        @Override public Instant instant() { return current.get(); }
        private void advance(Duration duration) { current.updateAndGet(value -> value.plus(duration)); }
    }
}
