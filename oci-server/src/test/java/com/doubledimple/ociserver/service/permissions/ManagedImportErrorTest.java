package com.doubledimple.ociserver.service.permissions;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.doubledimple.ociserver.controller.ManagedTenantController;
import com.oracle.bmc.model.BmcException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.nio.charset.StandardCharsets;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class ManagedImportErrorTest {
    private static final String SECRET = "private-key-and-request-body-must-not-be-logged";
    private final Logger logger = (Logger) LoggerFactory.getLogger(ManagedImportDiagnostics.class);
    private final ListAppender<ILoggingEvent> logs = new ListAppender<>();
    private Level previousLevel;

    @BeforeEach
    void captureDiagnostics() {
        previousLevel = logger.getLevel();
        logger.setLevel(Level.TRACE);
        logs.start();
        logger.addAppender(logs);
    }

    @AfterEach
    void restoreLogging() {
        logger.detachAppender(logs);
        logger.setLevel(previousLevel);
        logs.stop();
    }

    @Test
    void domainSynchronizationFailureRetainsItsSpecificSafeMessageThroughTheController() throws Exception {
        String message = "专用用户尚未唯一同步到身份域，请稍后重试。";
        ManagedDomainRoleService.DomainRoleException original =
                new ManagedDomainRoleService.DomainRoleException(message);
        IllegalArgumentException domainFailure = assertThrows(IllegalArgumentException.class,
                () -> ManagedDomainRoleService.safe(ManagedImportDiagnostics.Stage.DOMAIN_AUDIT, () -> {
                    throw original;
                }));
        IllegalArgumentException exposed = ManagedOciIdentityProvisioner.safeFailure(domainFailure);
        assertSame(original, exposed);

        ManagedTenantImportService imports = mock(ManagedTenantImportService.class);
        when(imports.save(anyString(), anyString(), anyString(), anyString(), anyString(), anyString(),
                anyString(), nullable(String.class), any())).thenThrow(exposed);
        ManagedTenantController controller = new ManagedTenantController();
        ReflectionTestUtils.setField(controller, "managedTenantImportService", imports);
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).build();

        mvc.perform(multipart("/tenants/restricted/save")
                        .file(new MockMultipartFile("keyFileStr", "test.pem", "text/plain",
                                SECRET.getBytes(StandardCharsets.UTF_8)))
                        .param("tenantId", "ocid1.user.oc1..test")
                        .param("tenancy", "ocid1.tenancy.oc1..test")
                        .param("fingerprint", "test-fingerprint")
                        .param("region", "test-region")
                        .param("userName", "display-name")
                        .param("managedUserName", "managed-user")
                        .param("permissions", "[\"BASIC_READ\"]"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value(message));

        assertTrue(logText().contains("stage=DOMAIN_AUDIT"));
        assertTrue(logText().contains("type=DomainRoleException"));
        assertPrivateDetailsAbsent();
    }

    @ParameterizedTest
    @ValueSource(ints = {401, 403, 404, 409, 412, 429, 500})
    void sdkFailuresKeepSafeDiagnosticsWithoutLeakingSdkBodies(int status) {
        BmcException failure = new BmcException(status, "NotAuthorizedOrNotFound", SECRET,
                "request-id-123/segment", new IllegalStateException(SECRET));
        IllegalArgumentException domain = assertThrows(IllegalArgumentException.class,
                () -> ManagedDomainRoleService.safe(ManagedImportDiagnostics.Stage.DOMAIN_RECONCILE, () -> {
                    throw failure;
                }));
        IllegalArgumentException exposed = ManagedOciIdentityProvisioner.safeFailure(domain);

        assertSame(domain, exposed);
        assertFalse(exposed.getMessage().contains(SECRET));
        assertNull(exposed.getCause());
        assertTrue(logText().contains("stage=DOMAIN_RECONCILE"));
        assertTrue(logText().contains("status=" + status));
        assertTrue(logText().contains("serviceCode=NotAuthorizedOrNotFound"));
        assertTrue(logText().contains("requestId=request-id-123/segment"));
        assertPrivateDetailsAbsent();
    }

    @Test
    void unexpectedExceptionsAreSanitizedInsteadOfBeingMistakenForSafeBusinessErrors() {
        IllegalArgumentException domain = assertThrows(IllegalArgumentException.class,
                () -> ManagedDomainRoleService.safe(ManagedImportDiagnostics.Stage.DOMAIN_AUDIT, () -> {
                    throw new NullPointerException(SECRET);
                }));
        assertSame(domain, ManagedOciIdentityProvisioner.safeFailure(domain));
        assertFalse(domain.getMessage().contains(SECRET));
        IllegalArgumentException provision = ManagedOciIdentityProvisioner.safeFailure(new IllegalArgumentException(SECRET));
        assertFalse(provision.getMessage().contains(SECRET));
        assertNull(provision.getCause());
        assertTrue(logText().contains("type=NullPointerException"));
        assertTrue(logText().contains("stage=IDENTITY_PROVISION"));
        assertPrivateDetailsAbsent();
    }

    @Test
    void sdkMetadataWithControlCharactersOrBodyContentIsRedacted() {
        BmcException failure = new BmcException(403, "Forbidden\n" + SECRET, SECRET,
                "{\"privateKey\":\"" + SECRET + "\"}");

        IllegalArgumentException exposed = ManagedOciIdentityProvisioner.safeFailure(failure);

        assertFalse(exposed.getMessage().contains(SECRET));
        assertTrue(logText().contains("serviceCode=[redacted]"));
        assertTrue(logText().contains("requestId=[redacted]"));
        assertPrivateDetailsAbsent();
    }

    private String logText() {
        return logs.list.stream().map(ILoggingEvent::getFormattedMessage).collect(Collectors.joining("\n"));
    }

    private void assertPrivateDetailsAbsent() {
        assertFalse(logText().contains(SECRET));
        for (ILoggingEvent event : logs.list) {
            assertNull(event.getThrowableProxy(), "Raw SDK exception/cause must not be attached to logs");
        }
    }
}
