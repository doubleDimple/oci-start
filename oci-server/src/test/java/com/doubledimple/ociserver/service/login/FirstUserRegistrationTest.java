package com.doubledimple.ociserver.service.login;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import com.doubledimple.ociserver.controller.login.LoginUserController;
import org.aopalliance.intercept.MethodInterceptor;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.dao.support.PersistenceExceptionTranslationInterceptor;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.SharedEntityManagerCreator;
import org.springframework.orm.jpa.vendor.HibernateJpaDialect;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import javax.persistence.EntityManagerFactory;
import java.util.Arrays;
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

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Only two mapped entities and real in-memory H2 transactions; no application context or outbound services. */
class FirstUserRegistrationTest {
    private static final String CLAIM = "auth.first-user.initialized";
    private static final String PASSWORD = "correct-password";
    private static LocalContainerEntityManagerFactoryBean factory;
    private static JpaTransactionManager transactionManager;
    private static LoginUserRepository persistedUsers;
    private static SystemConfigRepository persistedConfig;
    private LoginUserService service;
    private ControllableEncoder encoder;
    private AtomicBoolean raceEnabled;
    private CyclicBarrier emptyDatabaseRead;
    private CyclicBarrier claimAttempt;

    @BeforeAll
    static void startIsolatedPersistence() {
        DriverManagerDataSource dataSource = new DriverManagerDataSource(
                "jdbc:h2:mem:first_user_" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1;LOCK_TIMEOUT=10000", "sa", "");
        factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(dataSource);
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        factory.setPackagesToScan(LoginUser.class.getPackage().getName());
        factory.setPersistenceUnitPostProcessors(unit -> {
            unit.getManagedClassNames().clear();
            unit.addManagedClassName(LoginUser.class.getName());
            unit.addManagedClassName(SystemConfig.class.getName());
        });
        Properties properties = new Properties();
        properties.setProperty("hibernate.hbm2ddl.auto", "create-drop");
        properties.setProperty("hibernate.dialect", "org.hibernate.dialect.H2Dialect");
        properties.setProperty("hibernate.show_sql", "false");
        factory.setJpaProperties(properties);
        factory.afterPropertiesSet();
        EntityManagerFactory entities = factory.getObject();
        assertNotNull(entities);
        assertEquals(2, entities.getMetamodel().getEntities().size());
        transactionManager = new JpaTransactionManager(entities);
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(SharedEntityManagerCreator.createSharedEntityManager(entities));
        persistedUsers = translated(repositories.getRepository(LoginUserRepository.class));
        persistedConfig = translated(repositories.getRepository(SystemConfigRepository.class));
    }

    @AfterAll
    static void stopIsolatedPersistence() {
        if (factory != null) factory.destroy();
    }

    @BeforeEach
    void prepareService() {
        transaction().execute(status -> { persistedUsers.deleteAll(); persistedConfig.deleteAll(); return null; });
        encoder = new ControllableEncoder();
        raceEnabled = new AtomicBoolean();
        emptyDatabaseRead = new CyclicBarrier(2);
        claimAttempt = new CyclicBarrier(2);

        ProxyFactory userProxy = new ProxyFactory(persistedUsers);
        userProxy.addAdvice((MethodInterceptor) invocation -> {
            Object result = invocation.proceed();
            // Both callers must observe the real empty database before either can initialize it.
            if (raceEnabled.get() && "count".equals(invocation.getMethod().getName())) {
                emptyDatabaseRead.await(10, TimeUnit.SECONDS);
            }
            return result;
        });
        ProxyFactory configProxy = new ProxyFactory(persistedConfig);
        configProxy.addAdvice((MethodInterceptor) invocation -> {
            // Both callers pass the preflight checks, then contend on the actual unique database key.
            if (raceEnabled.get() && "saveAndFlush".equals(invocation.getMethod().getName())) {
                claimAttempt.await(10, TimeUnit.SECONDS);
            }
            return invocation.proceed();
        });
        LoginUserService target = new LoginUserService();
        ReflectionTestUtils.setField(target, "loginUserRepository", userProxy.getProxy());
        ReflectionTestUtils.setField(target, "systemConfigRepository", configProxy.getProxy());
        ReflectionTestUtils.setField(target, "passwordEncoder", encoder);
        ProxyFactory serviceProxy = new ProxyFactory(target);
        serviceProxy.setProxyTargetClass(true);
        serviceProxy.addAdvice(new TransactionInterceptor(transactionManager, new AnnotationTransactionAttributeSource()));
        service = (LoginUserService) serviceProxy.getProxy();
    }

    @Test
    void simultaneousDifferentUsernamesCanCreateOnlyOneInitialAccount() throws Exception {
        raceEnabled.set(true);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService workers = Executors.newFixedThreadPool(2);
        List<Throwable> results;
        try {
            Future<Throwable> first = workers.submit(() -> attemptRegistration(start, "owner-one"));
            Future<Throwable> second = workers.submit(() -> attemptRegistration(start, "owner-two"));
            start.countDown();
            results = Arrays.asList(first.get(25, TimeUnit.SECONDS), second.get(25, TimeUnit.SECONDS));
        } finally {
            raceEnabled.set(false);
            workers.shutdownNow();
            assertTrue(workers.awaitTermination(5, TimeUnit.SECONDS));
        }

        assertEquals(1, results.stream().filter(result -> result == null).count());
        Throwable rejected = results.stream().filter(result -> result != null).findFirst().orElseThrow(AssertionError::new);
        assertTrue(rejected instanceof LoginUserService.FirstRegistrationException, rejected.toString());
        assertEquals(1L, userCount());
        SystemConfig claim = transaction().execute(status -> persistedConfig.findByKey(CLAIM).orElseThrow(AssertionError::new));
        assertEquals("true", claim.getValue());
        assertTrue(claim.isEnabled());
        assertFalse(service.isFirstTimeDeployment());
    }

    @Test
    void failureAfterTheClaimFlushRollsBackBothWritesAndAllowsRetry() {
        encoder.failNext.set(true);

        assertThrows(IllegalStateException.class, () -> service.registerFirstUser("owner-one", PASSWORD));

        assertEquals(0L, userCount());
        assertFalse(hasClaim());
        assertTrue(service.isFirstTimeDeployment());
        service.registerFirstUser("owner-two", PASSWORD);
        assertEquals(1L, userCount());
        assertTrue(hasClaim());
        assertEquals("owner-two", service.validateCredentials("owner-two", PASSWORD).getUsername());
    }

    @Test
    void anExistingThirdPartyUserAlsoClosesFirstRegistration() {
        transaction().execute(status -> {
            LoginUser external = user("existing-google", LoginTypeEnum.GOOGLE);
            persistedUsers.saveAndFlush(external);
            return null;
        });

        assertFalse(service.isFirstTimeDeployment());
        assertTrue(service.existsAnyUser());
        assertThrows(LoginUserService.FirstRegistrationException.class,
                () -> service.registerFirstUser("new-owner", PASSWORD));
        assertEquals(1L, userCount());
        assertFalse(hasClaim());
    }

    @Test
    void aPersistedClaimPreventsRegistrationEvenIfTheOriginalAccountWasRemoved() {
        service.registerFirstUser("initial-owner", PASSWORD);
        transaction().execute(status -> { persistedUsers.deleteAll(); return null; });

        assertEquals(0L, userCount());
        assertTrue(hasClaim());
        assertFalse(service.isFirstTimeDeployment());
        assertThrows(LoginUserService.FirstRegistrationException.class,
                () -> service.registerFirstUser("replacement-owner", PASSWORD));
        assertEquals(0L, userCount());
    }

    @ParameterizedTest
    @ValueSource(strings = {"root", "admin", "administrator", "superadmin", "superuser", "system", "guest", "test", "user",
            "  AdMiN  ", "\tROOT\n", "admin123", "RoOt007", "ＡＤＭＩＮ", "　ＲＯＯＴ　"})
    void reservedNamesCannotClaimTheFirstAccountRegardlessOfCaseOrSurroundingWhitespace(String username) {
        assertThrows(LoginUserService.FirstRegistrationException.class, () -> service.registerFirstUser(username, PASSWORD));
        assertEquals(0L, userCount());
        assertFalse(hasClaim());
    }

    @Test
    void aPersonalNameIsTrimmedAndThePasswordIsPreservedExactly() {
        String spacedPassword = "  exact password  ";

        service.registerFirstUser("  CloudOwner  ", spacedPassword);

        LoginUser account = service.validateCredentials("CloudOwner", spacedPassword);
        assertTrue(account.isFirstUser());
        assertEquals(LoginTypeEnum.LOCAL, account.getLoginType());
        assertNotEquals(spacedPassword, account.getPassword());
        assertThrows(LoginUserService.CredentialValidationException.class,
                () -> service.validateCredentials("CloudOwner", spacedPassword.trim()));
    }

    @Test
    void anExistingAdminAccountCanStillAuthenticate() {
        transaction().execute(status -> { persistedUsers.saveAndFlush(user("admin", LoginTypeEnum.LOCAL)); return null; });

        assertEquals("admin", service.validateCredentials("admin", PASSWORD).getUsername());
        assertThrows(LoginUserService.CredentialValidationException.class,
                () -> service.validateCredentials("admin", "wrong-password"));
    }

    @Test
    void unexpectedRegistrationFailureIsSanitizedByTheRealControllerAndRollsBack() throws Exception {
        encoder.failNext.set(true);
        LoginUserController controller = new LoginUserController();
        ReflectionTestUtils.setField(controller, "loginUserService", service);
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).build();

        mvc.perform(post("/api/register-first-user").contentType("application/json")
                        .content("{\"username\":\"cloud-owner\",\"password\":\"correct-password\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("internal encoder failure"))));

        assertEquals(0L, userCount());
        assertFalse(hasClaim());
    }

    private Throwable attemptRegistration(CountDownLatch start, String username) {
        try {
            assertTrue(start.await(5, TimeUnit.SECONDS));
            service.registerFirstUser(username, PASSWORD);
            return null;
        } catch (Throwable failure) {
            return failure;
        }
    }

    private LoginUser user(String username, LoginTypeEnum type) {
        LoginUser user = new LoginUser();
        user.setUsername(username);
        user.setPassword(encoder.encode(PASSWORD));
        user.setLoginType(type);
        return user;
    }

    private long userCount() { return transaction().execute(status -> persistedUsers.count()); }
    private boolean hasClaim() { return transaction().execute(status -> persistedConfig.existsByKey(CLAIM)); }
    private static TransactionTemplate transaction() { return new TransactionTemplate(transactionManager); }

    @SuppressWarnings("unchecked")
    private static <T> T translated(T repository) {
        ProxyFactory proxy = new ProxyFactory(repository);
        proxy.addAdvice(new PersistenceExceptionTranslationInterceptor(new HibernateJpaDialect()));
        return (T) proxy.getProxy();
    }

    private static final class ControllableEncoder implements PasswordEncoder {
        private final PasswordEncoder delegate = new BCryptPasswordEncoder(4);
        private final AtomicBoolean failNext = new AtomicBoolean();
        @Override public String encode(CharSequence rawPassword) {
            assertTrue(TransactionSynchronizationManager.isActualTransactionActive());
            if (failNext.getAndSet(false)) throw new IllegalStateException("internal encoder failure");
            return delegate.encode(rawPassword);
        }
        @Override public boolean matches(CharSequence rawPassword, String encodedPassword) {
            return delegate.matches(rawPassword, encodedPassword);
        }
    }
}
