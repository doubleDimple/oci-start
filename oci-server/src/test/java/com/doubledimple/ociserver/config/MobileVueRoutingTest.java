package com.doubledimple.ociserver.config;

import cn.dev33.satoken.SaManager;
import cn.dev33.satoken.context.SaTokenContext;
import cn.dev33.satoken.dao.SaTokenDao;
import cn.dev33.satoken.dao.SaTokenDaoDefaultImpl;
import cn.dev33.satoken.spring.SaTokenContextForSpring;
import cn.dev33.satoken.stp.StpUtil;
import com.doubledimple.ociserver.controller.MobileController;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.handler.MappedInterceptor;

import java.net.URL;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/** Routing and authentication only: no Spring application, database, or cloud services. */
class MobileVueRoutingTest {
    private cn.dev33.satoken.config.SaTokenConfig previousConfig;
    private SaTokenDao previousDao;
    private SaTokenContext previousContext;
    private SaTokenDaoDefaultImpl testDao;
    private ClassLoader previousClassLoader;
    private final VueSpaFilter filter = new VueSpaFilter();

    @BeforeEach
    void isolateSessionAndFrontendResources() {
        previousConfig = SaManager.getConfig();
        previousDao = SaManager.getSaTokenDao();
        previousContext = SaManager.getSaTokenContext();
        previousClassLoader = Thread.currentThread().getContextClassLoader();
        SaManager.setConfig(new cn.dev33.satoken.config.SaTokenConfig()
                .setTokenName("mobile-routing-test-token")
                .setDataRefreshPeriod(-1).setIsPrint(false).setIsLog(false));
        testDao = new SaTokenDaoDefaultImpl();
        SaManager.setSaTokenDao(testDao);
        SaManager.setSaTokenContext(new SaTokenContextForSpring());
        frontendPresent(true);
    }

    @AfterEach
    void restoreSessionAndClassLoader() {
        RequestContextHolder.resetRequestAttributes();
        Thread.currentThread().setContextClassLoader(previousClassLoader);
        testDao.destroy();
        SaManager.setSaTokenDao(previousDao);
        SaManager.setSaTokenContext(previousContext);
        SaManager.setConfig(previousConfig);
    }

    @ParameterizedTest
    @ValueSource(strings = {"/m", "/m/", "/m/tenants", "/m/regions", "/m/boot", "/m/add-boot",
            "/m/instances", "/m/oci-instances", "/m/tenant-instances", "/m/import",
            "/m/speedtest", "/m/monitor", "/m/settings", "/m/arm-regions", "/m/cloudflare",
            "/m/ai", "/m/notify-settings", "/m/traffic", "/m/cost", "/m/region-sub",
            "/m/user-mgr", "/m/audit-log", "/m/disk-info", "/m/security-rules",
            "/m/storage-instances", "/m/memo", "/m/mfa", "/m/vnic/manage", "/m/logs",
            "/m/open-logs", "/m/sysHelp"})
    void mobilePagesRequireLoginBeforeServingVue(String path) throws Exception {
        MockHttpServletRequest request = request("GET", path);
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertEquals(302, response.getStatus());
        assertEquals("/m/login", response.getRedirectedUrl());
        assertNull(response.getForwardedUrl());
        assertNull(chain.getRequest());
        assertNull(RequestContextHolder.getRequestAttributes());
    }

    @ParameterizedTest
    @ValueSource(strings = {"/m", "/m/tenants", "/m/regions", "/m/instances", "/m/tenant-instances",
            "/m/mfa", "/m/vnic/manage", "/m/sysHelp"})
    void authenticatedPagesForwardToVueAndRetainRouteParameters(String path) throws Exception {
        MockHttpServletRequest request = request("GET", path);
        request.addHeader(SaManager.getConfig().getTokenName(), loginToken());
        request.setQueryString("instanceId=123&tenantId=456");
        request.addParameter("instanceId", "123");
        request.addParameter("tenantId", "456");
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertEquals("/index.html", response.getForwardedUrl());
        assertNull(response.getRedirectedUrl());
        assertNull(chain.getRequest());
        assertEquals("123", request.getParameter("instanceId"));
        assertEquals("456", request.getParameter("tenantId"));
        assertNull(RequestContextHolder.getRequestAttributes());
    }

    @ParameterizedTest
    @CsvSource({"GET,/m/api/tenants", "GET,/m/api/instances", "GET,/m/api/tenants/123/regions",
            "GET,/m/api/boot/123/subtasks", "POST,/m/api/boot/123/start", "POST,/m/instances",
            "PUT,/m/settings", "DELETE,/m/instances", "OPTIONS,/m/tenants",
            "POST,/perform_login", "GET,/assets/mobile.js",
            "GET,/api/config/mfa-enabled", "GET,/m/unknown-page"})
    void apiAssetsAndMutationRequestsBypassSpa(String method, String path) throws Exception {
        MockHttpServletRequest request = request(method, path);
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertSame(request, chain.getRequest());
        assertNull(response.getForwardedUrl());
        assertNull(response.getRedirectedUrl());
    }

    @Test
    void mvcAuthenticationStillProtectsApisWhenFrontendIsAbsent() throws Exception {
        frontendPresent(false);
        MappedInterceptor authentication = authenticationInterceptor();
        for (String path : Arrays.asList("/m/api/tenants", "/m/api/boot/123/start")) {
            MockHttpServletRequest request = request(path.endsWith("/start") ? "POST" : "GET", path);
            request.addHeader("Accept", "application/json");
            MockHttpServletResponse response = new MockHttpServletResponse();
            MockFilterChain chain = new MockFilterChain();
            filter.doFilter(request, response, chain);
            assertSame(request, chain.getRequest());
            assertTrue(authentication.matches(path, new AntPathMatcher()), path);
            RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request, response));
            try {
                assertFalse(authentication.preHandle(request, response, new Object()));
                assertEquals(401, response.getStatus());
                assertTrue(response.getContentAsString().contains("\"code\":401"));
                assertNull(response.getForwardedUrl());
            } finally {
                RequestContextHolder.resetRequestAttributes();
            }
        }
    }

    @Test
    void loginAliasesAndForbiddenPageArePublic() {
        MappedInterceptor authentication = authenticationInterceptor();
        for (String path : Arrays.asList("/login", "/m/login", "/forbidden", "/perform_login")) {
            assertFalse(authentication.matches(path, new AntPathMatcher()), path);
        }
    }

    @ParameterizedTest
    @CsvSource({"GET,/login", "HEAD,/login", "GET,/m/login", "HEAD,/m/login",
            "GET,/forbidden", "HEAD,/forbidden", "GET,/login/"})
    void publicPagesServeVueWithoutAuthentication(String method, String path) throws Exception {
        MockHttpServletRequest request = request(method, path);
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertEquals("/index.html", response.getForwardedUrl());
        assertNull(response.getRedirectedUrl());
        assertNull(chain.getRequest());
    }

    @ParameterizedTest
    @CsvSource({"HEAD,/m/tenants,/m/login", "HEAD,/tenants/list,/login",
            "GET,/about/author,/login", "HEAD,/about/author,/login",
            "GET,/tenants/list/,/login", "HEAD,/oci/console/terminal/123,/login"})
    void legacyRoutesAndHeadRequestsRequireAuthentication(String method, String path, String loginPath) throws Exception {
        MockHttpServletRequest request = request(method, path);
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertEquals(loginPath, response.getRedirectedUrl());
        assertNull(chain.getRequest());
    }

    @ParameterizedTest
    @CsvSource({"HEAD,/m/tenants", "HEAD,/tenants/list", "GET,/about/author",
            "HEAD,/about/author", "GET,/tenants/list/", "HEAD,/oci/console/terminal/123"})
    void authenticatedLegacyRoutesAndHeadRequestsServeVue(String method, String path) throws Exception {
        MockHttpServletRequest request = request(method, path);
        request.addHeader(SaManager.getConfig().getTokenName(), loginToken());
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();
        ServletRequestAttributes previous = new ServletRequestAttributes(request, response);
        RequestContextHolder.setRequestAttributes(previous);

        filter.doFilter(request, response, chain);

        assertEquals("/index.html", response.getForwardedUrl());
        assertNull(chain.getRequest());
        assertSame(previous, RequestContextHolder.getRequestAttributes());
    }

    @ParameterizedTest
    @CsvSource({"GET,/m/tenants", "HEAD,/m/tenants", "GET,/tenants/list", "GET,/main",
            "GET,/about/author", "GET,/login", "HEAD,/login", "GET,/forbidden"})
    void missingFrontendReturnsServiceUnavailableWithoutFallingBackToTemplates(String method, String path) throws Exception {
        frontendPresent(false);
        MockHttpServletRequest request = request(method, path);
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertEquals(503, response.getStatus());
        assertEquals("no-store", response.getHeader("Cache-Control"));
        assertNull(chain.getRequest());
        assertNull(response.getForwardedUrl());
        assertNull(response.getRedirectedUrl());
        assertEquals("HEAD".equals(method) ? "" : "Web interface is unavailable.", response.getContentAsString());
    }

    @Test
    void retiredRescueControllerRedirectsWithoutLookingUpOrMutatingAnInstance() throws Exception {
        MobileController controller = new MobileController();
        assertEquals("redirect:/m/instances", controller.sysHelpPage());
        assertArrayEquals(new String[]{"/sysHelp"}, MobileController.class.getMethod("sysHelpPage")
                .getAnnotation(GetMapping.class).value());
    }

    private MockHttpServletRequest request(String method, String path) {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setServletPath(path);
        return request;
    }

    private String loginToken() {
        MockHttpServletRequest request = request("POST", "/test-only-login");
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request, new MockHttpServletResponse()));
        try {
            StpUtil.login("mobile-routing-user");
            return StpUtil.getTokenValue();
        } finally {
            RequestContextHolder.resetRequestAttributes();
        }
    }

    private MappedInterceptor authenticationInterceptor() {
        TestInterceptorRegistry registry = new TestInterceptorRegistry();
        new SaTokenConfig().addInterceptors(registry);
        List<Object> interceptors = registry.interceptors();
        assertEquals(1, interceptors.size());
        return (MappedInterceptor) interceptors.get(0);
    }

    private void frontendPresent(final boolean present) {
        // VueSpaFilter only checks existence. Use a test-class resource, so no
        // frontend build or production static files are created by these tests.
        final URL fixture = MobileVueRoutingTest.class.getResource("MobileVueRoutingTest.class");
        assertNotNull(fixture);
        Thread.currentThread().setContextClassLoader(new ClassLoader(previousClassLoader) {
            @Override
            public URL getResource(String name) {
                return "static/index.html".equals(name) ? present ? fixture : null : super.getResource(name);
            }
        });
    }

    private static class TestInterceptorRegistry extends InterceptorRegistry {
        List<Object> interceptors() { return getInterceptors(); }
    }
}
