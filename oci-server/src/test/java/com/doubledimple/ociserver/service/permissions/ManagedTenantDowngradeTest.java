package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.config.SpringAppContext;
import com.doubledimple.ociserver.config.TenantProxyBinder;
import com.doubledimple.ociserver.controller.ManagedTenantController;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.http.ClientConfigurator;
import com.oracle.bmc.identity.model.RegionSubscription;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.BeanUtils;
import org.springframework.context.ApplicationContext;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.util.StreamUtils;

import javax.persistence.EntityManager;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.StringJoiner;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Real service/file operations, with cloud requests and transaction persistence kept in memory. */
class ManagedTenantDowngradeTest {
    private static final String TENANCY = "ocid1.tenancy.oc1..test";
    private static final String ADMIN_USER = "ocid1.user.oc1..original";
    private static final String DEDICATED_USER = "ocid1.user.oc1..dedicated";
    private static byte[] originalKey;
    private static byte[] dedicatedKey;
    private static String originalFingerprint;
    private static String dedicatedFingerprint;

    @TempDir Path directory;
    private final Map<Long, Tenant> database = new LinkedHashMap<>();
    private Map<Long, Tenant> pending;
    private TenantRepository tenants;
    private VpnProxyRecordRepository proxies;
    private ManagedOciIdentityProvisioner provisioner;
    private PlatformTransactionManager transactions;
    private ManagedTenantImportService service;
    private ApplicationContext previousContext;
    private Path originalKeyPath;
    private String failureAt;
    private String suppliedAdminUser;
    private byte[] suppliedAdminKey;
    private ManagedOciIdentityProvisioner.ExistingIdentity suppliedPrevious;

    @BeforeAll
    static void createSyntheticKeys() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair admin = generator.generateKeyPair();
        KeyPair dedicated = generator.generateKeyPair();
        originalKey = pem(admin);
        dedicatedKey = pem(dedicated);
        originalFingerprint = fingerprint(admin);
        dedicatedFingerprint = fingerprint(dedicated);
    }

    @BeforeEach
    void setUp() throws Exception {
        originalKeyPath = directory.resolve("original-admin.pem");
        Files.write(originalKeyPath, originalKey);
        database.put(101L, source(101L, 0L, "us-ashburn-1"));
        database.put(102L, source(102L, 101L, "us-phoenix-1"));
        tenants = mock(TenantRepository.class);
        when(tenants.findById(anyLong())).thenAnswer(call -> Optional.ofNullable(copy(database.get(call.getArgument(0)))));
        when(tenants.findByParenId(anyLong())).thenAnswer(call -> database.values().stream()
                .filter(row -> call.getArgument(0).equals(row.getParenId())).map(ManagedTenantDowngradeTest::copy).collect(Collectors.toList()));
        when(tenants.findByTenancy(anyString())).thenAnswer(call -> database.values().stream()
                .filter(row -> call.getArgument(0).equals(row.getTenancy())).map(ManagedTenantDowngradeTest::copy).collect(Collectors.toList()));
        when(tenants.findByTenantId(anyString())).thenAnswer(call -> database.values().stream()
                .filter(row -> call.getArgument(0).equals(row.getTenantId())).map(ManagedTenantDowngradeTest::copy).collect(Collectors.toList()));
        when(tenants.findAll()).thenAnswer(call -> database.values().stream().map(ManagedTenantDowngradeTest::copy).collect(Collectors.toList()));
        when(tenants.saveAll(any())).thenAnswer(call -> {
            if ("save".equals(failureAt)) throw new TransactionSystemException("synthetic write failure");
            pending = new LinkedHashMap<>(database);
            List<Tenant> saved = new ArrayList<>();
            for (Tenant row : (Iterable<Tenant>) call.getArgument(0)) {
                pending.put(row.getId(), copy(row));
                saved.add(copy(row));
            }
            return saved;
        });
        transactions = mock(PlatformTransactionManager.class);
        when(transactions.getTransaction(any())).thenReturn(new SimpleTransactionStatus());
        doAnswer(call -> {
            assertTrue(Files.exists(originalKeyPath), "The original key must survive until the database commits");
            if ("commit".equals(failureAt)) throw new TransactionSystemException("synthetic commit failure");
            if (pending != null) {
                database.clear();
                database.putAll(pending);
                pending = null;
            }
            return null;
        }).when(transactions).commit(any());
        doAnswer(call -> { pending = null; return null; }).when(transactions).rollback(any());

        proxies = mock(VpnProxyRecordRepository.class);
        TenantProxyBinder binder = new TenantProxyBinder();
        ReflectionTestUtils.setField(binder, "tenantRepository", tenants);
        ReflectionTestUtils.setField(binder, "vpnProxyRecordRepository", proxies);
        ApplicationContext context = mock(ApplicationContext.class);
        when(context.getBean(TenantProxyBinder.class)).thenReturn(binder);
        previousContext = SpringAppContext.get();
        SpringAppContext.set(context);
        ProxyContext.set(mock(ClientConfigurator.class));

        provisioner = mock(ManagedOciIdentityProvisioner.class);
        when(provisioner.provision(any(), anyString(), anyString(), anyString(), any(), any(), anySet(), any()))
                .thenAnswer(call -> {
                    SimpleAuthenticationDetailsProvider provider = call.getArgument(0);
                    suppliedAdminUser = provider.getUserId();
                    try (InputStream key = provider.getPrivateKey()) { suppliedAdminKey = StreamUtils.copyToByteArray(key); }
                    suppliedPrevious = call.getArgument(5);
                    assertNull(ProxyContext.get(), "The previous request's proxy must not be reused");
                    return provisioned();
                });
        service = new ManagedTenantImportService();
        ReflectionTestUtils.setField(service, "tenantRepository", tenants);
        ReflectionTestUtils.setField(service, "provisioner", provisioner);
        ReflectionTestUtils.setField(service, "transactionManager", transactions);
        ReflectionTestUtils.setField(service, "entityManager", mock(EntityManager.class));
        ReflectionTestUtils.setField(service, "baseFile", directory.toString());
    }

    @AfterEach
    void clearContext() {
        TenantProxyBinder.clear();
        ReflectionTestUtils.setField(SpringAppContext.class, "CONTEXT", previousContext);
    }

    @Test
    void refusesToStartWithoutBackupConfirmation() throws Exception {
        assertThrows(IllegalArgumentException.class, () -> downgrade(false));
        verifyNoInteractions(provisioner);
        assertOriginalCredentialsIntact();
    }

    @ParameterizedTest
    @ValueSource(strings = {"managed", "other-cloud", "transferred"})
    void rejectsAnIneligibleSourceBeforeCallingOracle(String kind) throws Exception {
        if ("managed".equals(kind)) database.get(101L).setPermissionMode(OciPermissions.MODE);
        if ("other-cloud".equals(kind)) database.get(101L).setCloudType(2);
        if ("transferred".equals(kind)) database.get(101L).setTransferStatus(1);

        assertThrows(IllegalArgumentException.class, () -> downgrade(true));

        verifyNoInteractions(provisioner);
        assertOriginalCredentialsIntact();
    }

    @Test
    void preservesRegionalPrimaryKeysAndUsesANewDedicatedIdentityAfterCommit() throws Exception {
        Map<String, Object> response = downgrade(true);

        assertEquals("101", response.get("id"));
        assertEquals(Arrays.asList(101L, 102L), new ArrayList<>(database.keySet()));
        assertEquals(Long.valueOf(0), database.get(101L).getParenId());
        assertEquals(Long.valueOf(101), database.get(102L).getParenId());
        for (Tenant row : database.values()) {
            assertEquals(DEDICATED_USER, row.getTenantId());
            assertEquals(dedicatedFingerprint, row.getFingerprint());
            assertEquals(OciPermissions.MODE, row.getPermissionMode());
            assertEquals("operator", row.getManagedUserName());
            assertNotEquals(originalKeyPath.toString(), row.getKeyFile());
            assertArrayEquals(dedicatedKey, Files.readAllBytes(java.nio.file.Paths.get(row.getKeyFile())));
        }
        assertEquals(ADMIN_USER, suppliedAdminUser);
        assertArrayEquals(originalKey, suppliedAdminKey);
        assertNull(suppliedPrevious.getUserId(), "An original administrator is never an existing dedicated identity");
        assertNull(suppliedPrevious.getFingerprint(), "The original administrator key cannot be reused as a dedicated key");
        verify(proxies).findTopByTenantId(101L);
        verify(transactions).commit(any());
        assertFalse(Files.exists(originalKeyPath), "Remove the unreferenced original key only after commit");
        assertNull(ProxyContext.get());
    }

    @Test
    void cloudFailureKeepsTheOriginalCredentialsAndDoesNotStartTheDatabaseWrite() throws Exception {
        doThrow(new ManagedOciIdentityProvisioner.ProvisioningException("synthetic cloud failure"))
                .when(provisioner).provision(any(), anyString(), anyString(), anyString(), any(), any(), anySet(), any());

        assertThrows(IllegalArgumentException.class, () -> downgrade(true));

        assertOriginalCredentialsIntact();
        verify(tenants, never()).saveAll(any());
        assertNull(ProxyContext.get());
    }

    @ParameterizedTest
    @ValueSource(strings = {"same-user", "same-key"})
    void refusesAProvisionedIdentityThatRetainsTheOriginalAdministratorOrPrivateKey(String kind) throws Exception {
        ManagedOciIdentityProvisioner.Result invalid = provisioned();
        if ("same-user".equals(kind)) invalid.setTargetUserId(ADMIN_USER);
        else {
            invalid.setFingerprint(originalFingerprint);
            invalid.setPrivateKeyPem(originalKey.clone());
        }
        doReturn(invalid).when(provisioner).provision(any(), anyString(), anyString(), anyString(), any(), any(), anySet(), any());

        assertThrows(IllegalArgumentException.class, () -> downgrade(true));

        assertOriginalCredentialsIntact();
        verify(tenants, never()).saveAll(any());
    }

    @ParameterizedTest
    @ValueSource(strings = {"save", "commit"})
    void databaseFailureNeverDeletesOrReplacesTheOriginalCredentials(String stage) throws Exception {
        failureAt = stage;

        assertThrows(RuntimeException.class, () -> downgrade(true));

        assertOriginalCredentialsIntact();
        assertNull(ProxyContext.get());
    }

    @ParameterizedTest
    @ValueSource(strings = {"same", "normalized", "symlink"})
    void keepsAnOriginalKeyStillReferencedByAnotherTenant(String reference) throws Exception {
        Tenant other = source(201L, 0L, "eu-frankfurt-1");
        other.setTenancy("ocid1.tenancy.oc1..other");
        if ("normalized".equals(reference)) {
            Files.createDirectory(directory.resolve("alias-directory"));
            other.setKeyFile(directory.resolve("alias-directory/../original-admin.pem").toString());
        } else if ("symlink".equals(reference)) {
            Path alias = directory.resolve("other-tenant-key.pem");
            Files.createSymbolicLink(alias, originalKeyPath);
            other.setKeyFile(alias.toString());
        }
        database.put(201L, other);

        downgrade(true);

        assertEquals(DEDICATED_USER, database.get(101L).getTenantId());
        assertEquals(ADMIN_USER, database.get(201L).getTenantId());
        assertArrayEquals(originalKey, Files.readAllBytes(originalKeyPath));
    }

    @Test
    void keepsAnOriginalKeyOutsideTheConfiguredCredentialDirectory() throws Exception {
        ReflectionTestUtils.setField(service, "baseFile", directory.resolve("owned-credentials").toString());

        downgrade(true);

        assertEquals(DEDICATED_USER, database.get(101L).getTenantId());
        assertArrayEquals(originalKey, Files.readAllBytes(originalKeyPath));
    }

    @Test
    void rejectsSourceCredentialsChangedWhileOracleWasBeingConfigured() throws Exception {
        doAnswer(call -> {
                    database.get(102L).setFingerprint("changed-concurrently");
                    return provisioned();
                }).when(provisioner).provision(any(), anyString(), anyString(), anyString(), any(), any(), anySet(), any());

        assertThrows(IllegalArgumentException.class, () -> downgrade(true));

        assertEquals("changed-concurrently", database.get(102L).getFingerprint());
        assertEquals(ADMIN_USER, database.get(101L).getTenantId());
        assertArrayEquals(originalKey, Files.readAllBytes(originalKeyPath));
        verify(tenants, never()).saveAll(any());
    }

    @ParameterizedTest
    @ValueSource(strings = {"false", "null"})
    void legacyRootHomeFlagDoesNotPreventMigrationWhenItsRegionMatchesOracle(String homeFlag) throws Exception {
        database.get(101L).setIsHomeRegion("null".equals(homeFlag) ? null : false);

        Map<String, Object> result = downgrade(true);

        assertEquals("101", result.get("id"));
        assertEquals(Arrays.asList(101L, 102L), new ArrayList<>(database.keySet()));
        assertEquals(Boolean.TRUE, database.get(101L).getIsHomeRegion());
        assertEquals(DEDICATED_USER, database.get(101L).getTenantId());
    }

    @Test
    void aDifferentOracleHomeRegionCannotReplaceTheExistingParentPrimaryKey() throws Exception {
        ManagedOciIdentityProvisioner.Result differentHome = provisioned();
        differentHome.setHomeRegion("us-phoenix-1");
        differentHome.setRegions(Arrays.asList(
                RegionSubscription.builder().regionName("us-ashburn-1").isHomeRegion(false).build(),
                RegionSubscription.builder().regionName("us-phoenix-1").isHomeRegion(true).build()));
        doReturn(differentHome).when(provisioner).provision(any(), anyString(), anyString(), anyString(), any(), any(), anySet(), any());

        assertThrows(IllegalArgumentException.class, () -> downgrade(true));

        assertOriginalCredentialsIntact();
        verify(tenants, never()).saveAll(any());
    }

    @Test
    void jsonRequestDoesNotImplicitlyConfirmTheCredentialBackup() throws Exception {
        mvc().perform(post("/tenants/restricted/downgrade").contentType("application/json")
                        .content("{\"tenantId\":\"101\",\"managedUserName\":\"operator\",\"permissions\":\"[\\\"BASIC_READ\\\"]\",\"accountScope\":\"{}\"}"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.success").value(false));

        verifyNoInteractions(provisioner);
        assertOriginalCredentialsIntact();
    }

    @Test
    void endpointReturnsOriginalLocalIdAndExplainsWhyASharedPrivateKeyWasKept() throws Exception {
        Tenant other = source(201L, 0L, "eu-frankfurt-1");
        other.setTenancy("ocid1.tenancy.oc1..other");
        database.put(201L, other);

        mvc().perform(post("/tenants/restricted/downgrade").contentType("application/json")
                        .content(confirmedRequest()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.id").value("101"))
                .andExpect(jsonPath("$.data.cleanupWarnings").isNotEmpty())
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("PRIVATE KEY"))));

        assertEquals(DEDICATED_USER, database.get(101L).getTenantId());
        assertArrayEquals(originalKey, Files.readAllBytes(originalKeyPath));
    }

    @Test
    void endpointDoesNotExposeUnexpectedCloudExceptionDetails() throws Exception {
        String secret = "raw-credential-or-cloud-response-must-not-escape";
        doThrow(new IllegalStateException(secret)).when(provisioner)
                .provision(any(), anyString(), anyString(), anyString(), any(), any(), anySet(), any());

        mvc().perform(post("/tenants/restricted/downgrade").contentType("application/json")
                        .content(confirmedRequest()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString(secret))));

        assertOriginalCredentialsIntact();
    }

    private MockMvc mvc() {
        ManagedTenantController controller = new ManagedTenantController();
        ReflectionTestUtils.setField(controller, "managedTenantImportService", service);
        return MockMvcBuilders.standaloneSetup(controller).build();
    }

    private String confirmedRequest() {
        return "{\"tenantId\":\"101\",\"managedUserName\":\"operator\",\"permissions\":\"[\\\"BASIC_READ\\\"]\",\"accountScope\":\"{}\",\"backupConfirmed\":true}";
    }

    private Map<String, Object> downgrade(boolean backupConfirmed) throws Exception {
        return service.downgrade(101L, "operator", "[\"BASIC_READ\"]", "{}", backupConfirmed);
    }

    private void assertOriginalCredentialsIntact() throws Exception {
        for (long id : new long[]{101L, 102L}) {
            assertEquals(ADMIN_USER, database.get(id).getTenantId());
            assertEquals(originalFingerprint, database.get(id).getFingerprint());
            assertEquals(originalKeyPath.toString(), database.get(id).getKeyFile());
        }
        assertArrayEquals(originalKey, Files.readAllBytes(originalKeyPath));
    }

    private Tenant source(long id, long parent, String region) {
        Tenant tenant = new Tenant();
        tenant.setId(id);
        tenant.setIdStr(String.valueOf(id));
        tenant.setParenId(parent);
        tenant.setIsHomeRegion(parent == 0);
        tenant.setCloudType(1);
        tenant.setTenantId(ADMIN_USER);
        tenant.setTenancy(TENANCY);
        tenant.setUserName("original display name");
        tenant.setRegion(region);
        tenant.setFingerprint(originalFingerprint);
        tenant.setKeyFile(originalKeyPath.toString());
        return tenant;
    }

    private ManagedOciIdentityProvisioner.Result provisioned() {
        ManagedOciIdentityProvisioner.Result result = new ManagedOciIdentityProvisioner.Result();
        result.setTargetUserId(DEDICATED_USER);
        result.setFingerprint(dedicatedFingerprint);
        result.setPrivateKeyPem(dedicatedKey.clone());
        result.setGroupId("ocid1.group.oc1..dedicated");
        result.setPolicyId("ocid1.policy.oc1..dedicated");
        result.setHomeRegion("us-ashburn-1");
        result.setRegions(Arrays.asList(
                RegionSubscription.builder().regionName("us-ashburn-1").isHomeRegion(true).build(),
                RegionSubscription.builder().regionName("us-phoenix-1").isHomeRegion(false).build()));
        return result;
    }

    private static Tenant copy(Tenant original) {
        if (original == null) return null;
        Tenant copy = new Tenant();
        BeanUtils.copyProperties(original, copy);
        return copy;
    }

    private static byte[] pem(KeyPair pair) {
        return ("-----BEGIN PRIVATE KEY-----\n" + Base64.getMimeEncoder(64, new byte[]{'\n'})
                .encodeToString(pair.getPrivate().getEncoded()) + "\n-----END PRIVATE KEY-----\n")
                .getBytes(StandardCharsets.UTF_8);
    }

    private static String fingerprint(KeyPair pair) throws Exception {
        StringJoiner encoded = new StringJoiner(":");
        for (byte value : MessageDigest.getInstance("MD5").digest(pair.getPublic().getEncoded())) {
            encoded.add(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
        }
        return encoded.toString();
    }
}
