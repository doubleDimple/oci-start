package com.doubledimple.ociserver.config;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.config.context.RequestContextHolder;
import com.doubledimple.ociserver.config.interceptor.RequestContextInterceptor;
import com.doubledimple.ociserver.controller.ManagedTenantController;
import com.doubledimple.ociserver.pojo.request.RequestContext;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.service.permissions.ManagedTenantImportService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.oracle.bmc.http.ClientConfigurator;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import javax.servlet.DispatcherType;
import java.nio.charset.StandardCharsets;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class RequestContextInterceptorTest {
    private static final String OCI_USER = "ocid1.user.oc1..requestcontextregression";
    private static final String OCI_TENANCY = "ocid1.tenancy.oc1..requestcontextregression";
    private final ObjectMapper json = new ObjectMapper();
    private RequestContextInterceptor interceptor;
    private TenantService tenants;

    @BeforeEach
    void setup() {
        clearThreadState();
        tenants = mock(TenantService.class);
        interceptor = new RequestContextInterceptor();
        ReflectionTestUtils.setField(interceptor, "tenantService", tenants);
    }

    @AfterEach
    void clearThreadState() {
        RequestContextHolder.clear();
        TenantProxyBinder.clear();
    }

    @ParameterizedTest
    @CsvSource({
            "'', /tenants/restricted/save",
            "'', /tenants/restricted/save/",
            "/oci-start, /tenants/restricted/save",
            "/oci-start, /tenants/restricted/save/"
    })
    void multipartRestrictedImportReachesTheRealControllerWithTheOriginalOcid(
            String contextPath, String path) throws Exception {
        ManagedTenantImportService imports = mock(ManagedTenantImportService.class);
        ManagedTenantController controller = new ManagedTenantController();
        ReflectionTestUtils.setField(controller, "managedTenantImportService", imports);
        MockMultipartFile key = new MockMultipartFile("keyFileStr", "admin.pem", "application/x-pem-file",
                "dummy-private-key-for-mocked-import".getBytes(StandardCharsets.UTF_8));
        String permissions = "[\"instances.read\"]";
        String accountScope = "{\"mode\":\"all\"}";
        when(imports.save(OCI_USER, OCI_TENANCY, "test-fingerprint", "test-region", "display-name",
                "managed-user", permissions, accountScope, key)).thenReturn(Collections.singletonMap("id", "42"));
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).addInterceptors(interceptor).build();
        MockMultipartHttpServletRequestBuilder request = multipart(contextPath + path).file(key);
        request.contextPath(contextPath)
                .header("X-Tenant-Id", "ocid1.user.oc1..header-is-not-a-local-id")
                .param("tenantId", OCI_USER)
                .param("tenancy", OCI_TENANCY)
                .param("fingerprint", "test-fingerprint")
                .param("region", "test-region")
                .param("userName", "display-name")
                .param("managedUserName", "managed-user")
                .param("permissions", permissions)
                .param("accountScope", accountScope);

        mvc.perform(request)
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.id").value("42"));

        verify(imports).save(OCI_USER, OCI_TENANCY, "test-fingerprint", "test-region", "display-name",
                "managed-user", permissions, accountScope, key);
        verifyNoMoreInteractions(imports);
        verifyNoInteractions(tenants);
        assertNull(RequestContextHolder.get());
        assertNull(ProxyContext.get());
    }

    @ParameterizedTest
    @ValueSource(strings = {"/tenants/save", "/tenants/save/", "/tenants/restricted/save", "/tenants/restricted/save/"})
    void onlyExactPostImportPathsSkipLocalIdResolutionAndClearStaleState(String path) throws Exception {
        for (String contextPath : new String[]{"", "/oci-start"}) {
            MockHttpServletRequest request = new MockHttpServletRequest("POST", contextPath + path);
            request.setContextPath(contextPath);
            request.addParameter("tenantId", OCI_USER);
            request.addHeader("X-Tenant-Id", OCI_USER);
            seedStaleState();

            assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

            assertNull(RequestContextHolder.get());
            assertNull(ProxyContext.get());
        }
        verifyNoInteractions(tenants);
    }

    @ParameterizedTest
    @ValueSource(strings = {"/tenants/save-extra", "/tenants/restricted/save-other",
            "/tenants/restricted/save/preview", "/other/tenants/restricted/save"})
    void similarlyNamedRoutesDoNotGainTheImportExemption(String path) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
        request.addParameter("tenantId", OCI_USER);

        rejectInvalidId(request);

        verifyNoInteractions(tenants);
    }

    @ParameterizedTest
    @ValueSource(strings = {"GET", "PUT", "DELETE"})
    void importPathExemptionDoesNotApplyToOtherMethods(String method) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, "/tenants/restricted/save");
        request.addParameter("tenantId", OCI_USER);

        rejectInvalidId(request);

        verifyNoInteractions(tenants);
    }

    @Test
    void headerHasPriorityAndNumericWhitespaceIsTrimmed() throws Exception {
        Tenant tenant = new Tenant();
        tenant.setId(42L);
        when(tenants.getById(42L)).thenReturn(tenant);
        MockHttpServletRequest request = normalRequest();
        request.addHeader("X-Tenant-Id", " 42 ");
        request.addParameter("tenantId", OCI_USER);

        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

        assertSame(tenant, RequestContextHolder.get().getTenant());
        verify(tenants).getById(42L);
        verifyNoMoreInteractions(tenants);
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "\t"})
    void missingOrBlankHeaderFallsBackToTrimmedParameter(String header) throws Exception {
        Tenant tenant = new Tenant();
        tenant.setId(73L);
        when(tenants.getById(73L)).thenReturn(tenant);
        MockHttpServletRequest request = normalRequest();
        if (header != null) request.addHeader("X-Tenant-Id", header);
        request.addParameter("tenantId", " 73 ");

        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

        assertSame(tenant, RequestContextHolder.get().getTenant());
        verify(tenants).getById(73L);
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "-1", "9223372036854775807", "-9223372036854775808"})
    void validLongRangeKeepsExistingLookupBehavior(String value) throws Exception {
        MockHttpServletRequest request = normalRequest();
        request.addParameter("tenantId", value);

        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

        verify(tenants).getById(Long.valueOf(value));
        assertNotNull(RequestContextHolder.get());
        assertNull(RequestContextHolder.get().getTenant());
    }

    @Test
    void invalidHeaderDoesNotFallBackToAnOtherwiseValidParameter() throws Exception {
        MockHttpServletRequest request = normalRequest();
        request.addHeader("X-Tenant-Id", OCI_USER);
        request.addParameter("tenantId", "42");

        rejectInvalidId(request);

        verifyNoInteractions(tenants);
    }

    @ParameterizedTest
    @ValueSource(strings = {"ocid1.user.oc1..invalid-local-id", "not-a-number", "1.5", "123abc",
            "9223372036854775808", "-9223372036854775809", "<script>invalid-id</script>"})
    void invalidIdsReturnTheSameSafeJsonWithoutLookupOrEcho(String invalidId) throws Exception {
        MockHttpServletRequest request = normalRequest();
        request.addParameter("tenantId", invalidId);
        seedStaleState();

        String message = rejectInvalidId(request);

        MockHttpServletRequest otherInvalidRequest = normalRequest();
        otherInvalidRequest.addParameter("tenantId", "different-secret-invalid-id");
        assertEquals(message, rejectInvalidId(otherInvalidRequest));
        assertFalse(message.contains(invalidId));
        assertNull(RequestContextHolder.get());
        assertNull(ProxyContext.get());
        verifyNoInteractions(tenants);
    }

    @Test
    void requestWithoutTenantIdClearsStateLeftByAnotherRequest() throws Exception {
        seedStaleState();
        MockHttpServletRequest request = normalRequest();
        request.addParameter("tenantId", " ");

        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

        assertNull(RequestContextHolder.get());
        assertNull(ProxyContext.get());
        verifyNoInteractions(tenants);
    }

    @Test
    void errorDispatchSkipsIdParsingAndClearsStaleThreadState() throws Exception {
        seedStaleState();
        MockHttpServletRequest request = normalRequest();
        request.setDispatcherType(DispatcherType.ERROR);
        request.addParameter("tenantId", OCI_USER);

        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

        assertNull(RequestContextHolder.get());
        assertNull(ProxyContext.get());
        verifyNoInteractions(tenants);
    }

    @Test
    void asyncDispatchKeepsExistingContextWithoutParsingTheIdAgain() throws Exception {
        seedStaleState();
        RequestContext previous = RequestContextHolder.get();
        ClientConfigurator previousProxy = ProxyContext.get();
        MockHttpServletRequest request = normalRequest();
        request.setDispatcherType(DispatcherType.ASYNC);
        request.addParameter("tenantId", OCI_USER);

        assertTrue(interceptor.preHandle(request, new MockHttpServletResponse(), new Object()));

        assertSame(previous, RequestContextHolder.get());
        assertSame(previousProxy, ProxyContext.get());
        verifyNoInteractions(tenants);
    }

    @Test
    void completionClearsBothContextAndProxyEvenAfterHandlerFailure() throws Exception {
        seedStaleState();

        interceptor.afterCompletion(normalRequest(), new MockHttpServletResponse(), new Object(),
                new IllegalStateException("controller failure"));

        assertNull(RequestContextHolder.get());
        assertNull(ProxyContext.get());
    }

    private String rejectInvalidId(MockHttpServletRequest request) throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        assertFalse(interceptor.preHandle(request, response, new Object()));
        assertEquals(400, response.getStatus());
        assertNotNull(response.getContentType());
        assertTrue(MediaType.APPLICATION_JSON.isCompatibleWith(MediaType.parseMediaType(response.getContentType())));
        JsonNode body = json.readTree(response.getContentAsString());
        assertFalse(body.path("success").asBoolean(true));
        assertEquals(400, body.path("code").asInt());
        assertTrue(body.path("message").isTextual());
        assertFalse(body.path("message").asText().trim().isEmpty());
        return body.path("message").asText();
    }

    private static MockHttpServletRequest normalRequest() {
        return new MockHttpServletRequest("GET", "/instances/list");
    }

    private static void seedStaleState() {
        RequestContext context = new RequestContext();
        context.setTenant(new Tenant());
        RequestContextHolder.set(context);
        ProxyContext.set(mock(ClientConfigurator.class));
    }
}
