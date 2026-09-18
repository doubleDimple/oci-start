package com.doubledimple.ociserver.config;

import cn.dev33.satoken.SaManager;
import cn.dev33.satoken.context.SaTokenContext;
import cn.dev33.satoken.dao.SaTokenDao;
import cn.dev33.satoken.dao.SaTokenDaoDefaultImpl;
import cn.dev33.satoken.spring.SaTokenContextForSpring;
import cn.dev33.satoken.stp.StpUtil;
import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.ociserver.config.annotations.LoginUserAspect;
import com.doubledimple.ociserver.config.context.UserContext;
import com.doubledimple.ociserver.config.exception.GlobalExceptionHandler;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.config.filter.RsaDecryptionFilter;
import com.doubledimple.ociserver.controller.LoginController;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.service.VerifyService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.service.mfa.OTPService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.ResponseEntity;
import org.springframework.aop.aspectj.annotation.AspectJProxyFactory;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.stereotype.Controller;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.crypto.Cipher;
import javax.servlet.http.Cookie;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Collections;
import java.util.Map;

import static com.doubledimple.ocicommon.constant.Constants.RSA_PRIVATE_KEY;
import static com.doubledimple.ocicommon.constant.Constants.RSA_PUBLIC_KEY;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/** Real MVC, RSA and Sa-Token sessions; database, OTP and outbound services are isolated mocks. */
class VueLoginFlowTest {
    private static final String USER = "login-flow-user";
    private static final String PASSWORD = "test-password";
    private static final String TOKEN_NAME = "vue-login-flow-token";
    private static final String MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile";
    private final ObjectMapper json = new ObjectMapper();
    private cn.dev33.satoken.config.SaTokenConfig previousConfig;
    private SaTokenDao previousDao;
    private SaTokenContext previousContext;
    private RequestAttributes previousRequest;
    private SaTokenDaoDefaultImpl testDao;
    private SystemConfigService settings;
    private LoginUserService users;
    private VerifyService verification;
    private OTPService otp;
    private RestTemplate remote;
    private MockMvc mvc;

    @BeforeEach
    void setup() {
        previousConfig = SaManager.getConfig();
        previousDao = SaManager.getSaTokenDao();
        previousContext = SaManager.getSaTokenContext();
        previousRequest = RequestContextHolder.getRequestAttributes();
        SaManager.setConfig(new cn.dev33.satoken.config.SaTokenConfig().setTokenName(TOKEN_NAME)
                .setTimeout(3600).setDataRefreshPeriod(-1).setIsPrint(false).setIsLog(false));
        testDao = new SaTokenDaoDefaultImpl();
        SaManager.setSaTokenDao(testDao);
        SaManager.setSaTokenContext(new SaTokenContextForSpring());

        LoginController controller = new LoginController();
        settings = mock(SystemConfigService.class, RETURNS_DEEP_STUBS);
        users = mock(LoginUserService.class);
        verification = mock(VerifyService.class);
        otp = mock(OTPService.class);
        remote = mock(RestTemplate.class);
        ReflectionTestUtils.setField(controller, "systemConfigService", settings);
        ReflectionTestUtils.setField(controller, "loginUserService", users);
        ReflectionTestUtils.setField(controller, "verifyService", verification);
        ReflectionTestUtils.setField(controller, "otpService", otp);
        ReflectionTestUtils.setField(controller, "objectMapper", json);
        when(settings.getSiteLogoName()).thenReturn("OCI Start");
        LoginUser user = new LoginUser();
        user.setUsername(USER);
        when(users.validateCredentials(USER, PASSWORD)).thenReturn(user);
        mvc = MockMvcBuilders.standaloneSetup(controller, new RestDenialController(), new BrowserDenialController())
                .setControllerAdvice(new GlobalExceptionHandler())
                .addFilter(new RsaDecryptionFilter(settings, remote), "/perform_login")
                .build();
    }

    @AfterEach
    void restoreGlobalSessionState() {
        verifyNoInteractions(remote);
        RequestContextHolder.setRequestAttributes(previousRequest);
        testDao.destroy();
        SaManager.setSaTokenDao(previousDao);
        SaManager.setSaTokenContext(previousContext);
        SaManager.setConfig(previousConfig);
    }

    @ParameterizedTest
    @CsvSource({"false,true,/index", "true,true,/m/tenants", "false,false,/index", "true,false,/m/tenants"})
    void successfulLoginCreatesARealSessionAndKeepsDesktopAndMobileRedirects(boolean mobile, boolean ajax,
                                                                          String target) throws Exception {
        MockHttpServletRequestBuilder request = loginRequest(ajax);
        if (mobile) request.header("User-Agent", MOBILE_UA);

        MockHttpServletResponse response = mvc.perform(request).andReturn().getResponse();

        assertAuthenticated(response);
        if (ajax) {
            assertEquals(200, response.getStatus());
            assertTrue(json.readTree(response.getContentAsString()).get("success").asBoolean());
            assertEquals(target, json.readTree(response.getContentAsString()).get("redirectUrl").asText());
            assertNull(response.getRedirectedUrl());
        } else {
            assertEquals(302, response.getStatus());
            assertEquals(target, response.getRedirectedUrl());
        }
    }

    @ParameterizedTest
    @CsvSource({"on,3600", "true,3600", "1,3600", "off,-1", "false,-1", "0,-1", "missing,-1"})
    void rememberMeControlsWhetherTheLoginCookiePersists(String value, int maxAge) throws Exception {
        MockHttpServletRequestBuilder request = loginRequest(true);
        if (!"missing".equals(value)) request.param("remember-me", value);

        MockHttpServletResponse response = mvc.perform(request).andReturn().getResponse();

        assertAuthenticated(response);
        assertEquals(maxAge, response.getCookie(TOKEN_NAME).getMaxAge());
    }

    @ParameterizedTest
    @CsvSource({
            "false,true,-,654321,false,true,true",
            "false,true,-,000000,false,false,false",
            "false,true,-,-,false,false,false",
            "true,false,123456,-,true,false,true",
            "true,false,000000,-,false,false,false",
            "true,false,-,-,false,false,false",
            "true,true,123456,-,true,false,true",
            "true,true,-,654321,false,true,true",
            "true,true,000000,654321,false,true,true",
            "true,true,000000,000000,false,false,false",
            "true,true,-,-,false,false,false",
            "true,false,-,654321,false,true,false",
            "false,true,123456,-,true,false,false"
    })
    void enabledFactorsAreEnforcedAndEitherConfiguredFactorCanAuthenticate(boolean messageEnabled, boolean mfaEnabled,
            String messageCode, String mfaCode, boolean messageValid, boolean mfaValid, boolean accepted) throws Exception {
        when(verification.isMessageEnabled()).thenReturn(messageEnabled);
        when(settings.getMfaConfig().isEnabled()).thenReturn(mfaEnabled);
        if (!messageValid) {
            doThrow(new IllegalArgumentException("invalid message code"))
                    .when(verification).checkCodeForLogin(anyString(), anyString());
        }
        when(otp.verifyMfaCode(anyString())).thenReturn(mfaValid);
        MockHttpServletRequestBuilder request = loginRequest(true);
        if (!"-".equals(messageCode)) request.param("verificationCode", messageCode);
        if (!"-".equals(mfaCode)) request.param("mfaCode", mfaCode);

        MockHttpServletResponse response = mvc.perform(request).andReturn().getResponse();

        assertEquals(accepted ? 200 : 401, response.getStatus());
        assertEquals(accepted, json.readTree(response.getContentAsString()).get("success").asBoolean());
        if (accepted) assertAuthenticated(response);
        else assertNull(response.getCookie(TOKEN_NAME));
        if (messageEnabled && !"-".equals(messageCode)) verify(verification).checkCodeForLogin(USER, messageCode);
        else verify(verification, never()).checkCodeForLogin(anyString(), anyString());
        boolean messagePassed = messageEnabled && !"-".equals(messageCode) && messageValid;
        if (mfaEnabled && !"-".equals(mfaCode) && !messagePassed) verify(otp).verifyMfaCode(mfaCode);
        else verify(otp, never()).verifyMfaCode(anyString());
    }

    @Test
    void encryptedLoginUsesBootstrapSessionAndClearsOnlyTheRsaKeysOnSuccess() throws Exception {
        MvcResult bootstrap = mvc.perform(get("/api/auth/bootstrap")).andReturn();
        MockHttpSession session = (MockHttpSession) bootstrap.getRequest().getSession(false);
        String publicKey = json.readTree(bootstrap.getResponse().getContentAsString()).get("publicKey").asText();
        assertNotNull(session.getAttribute(RSA_PRIVATE_KEY));
        session.setAttribute("unrelated-setting", "keep");

        MockHttpServletResponse response = mvc.perform(loginRequest(true, encrypt(PASSWORD, publicKey))
                .session(session)).andReturn().getResponse();

        assertAuthenticated(response);
        verify(users).validateCredentials(USER, PASSWORD);
        assertNull(session.getAttribute(RSA_PRIVATE_KEY));
        assertNull(session.getAttribute(RSA_PUBLIC_KEY));
        assertEquals("keep", session.getAttribute("unrelated-setting"));
    }

    @Test
    void failedEncryptedLoginRetainsBootstrapKeysForRetry() throws Exception {
        MvcResult bootstrap = mvc.perform(get("/api/auth/bootstrap")).andReturn();
        MockHttpSession session = (MockHttpSession) bootstrap.getRequest().getSession(false);
        Object privateKey = session.getAttribute(RSA_PRIVATE_KEY);
        String publicKey = (String) session.getAttribute(RSA_PUBLIC_KEY);
        when(users.validateCredentials(USER, PASSWORD)).thenThrow(new IllegalArgumentException("invalid credentials"));

        MockHttpServletResponse response = mvc.perform(loginRequest(true, encrypt(PASSWORD, publicKey))
                .session(session)).andReturn().getResponse();

        assertEquals(401, response.getStatus());
        assertNull(response.getCookie(TOKEN_NAME));
        assertEquals(privateKey, session.getAttribute(RSA_PRIVATE_KEY));
        assertEquals(publicKey, session.getAttribute(RSA_PUBLIC_KEY));
    }

    @Test
    void inheritedLoginAspectPreservesAccountContextAndClearsItAfterSuccessOrFailure() throws Exception {
        MockHttpServletResponse login = mvc.perform(loginRequest(true)).andReturn().getResponse();
        assertAuthenticated(login);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(TOKEN_NAME, login.getCookie(TOKEN_NAME).getValue());
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request, new MockHttpServletResponse()));
        AspectJProxyFactory factory = new AspectJProxyFactory(new AccountContextController());
        factory.addAspect(new LoginUserAspect());
        AccountContextController proxy = factory.getProxy();
        try {
            assertNull(UserContext.getUsername());
            assertEquals(USER, proxy.currentUsername());
            assertNull(UserContext.getUsername());
            IllegalStateException failure = assertThrows(IllegalStateException.class, proxy::failingOperation);
            assertEquals(USER, failure.getMessage());
            assertNull(UserContext.getUsername());
        } finally {
            UserContext.clear();
        }
    }

    @ParameterizedTest
    @CsvSource({"false,/login", "true,/m/login"})
    void oldBrowserFormsKeepTheirEncodedFailureRedirect(boolean mobile, String target) throws Exception {
        String message = "登录失败 \"quoted\" & retry";
        when(users.validateCredentials(USER, PASSWORD)).thenThrow(new IllegalArgumentException(message));
        MockHttpServletRequestBuilder request = loginRequest(false);
        if (mobile) request.header("User-Agent", MOBILE_UA);

        MockHttpServletResponse response = mvc.perform(request).andReturn().getResponse();

        assertEquals(302, response.getStatus());
        assertEquals(target + "?error=" + URLEncoder.encode(message, StandardCharsets.UTF_8.name()),
                response.getRedirectedUrl());
        assertNull(response.getCookie(TOKEN_NAME));
    }

    @ParameterizedTest
    @ValueSource(strings = {"/legacy/rest/denied", "/legacy/method/denied", "/legacy/entity/denied", "/api/denied"})
    void bannedRestEndpointsReturnJsonWithoutRequiringSpecialClientHeaders(String path) throws Exception {
        MockHttpServletResponse response = mvc.perform(get(path).servletPath(path)).andReturn().getResponse();

        assertEquals(403, response.getStatus());
        assertEquals(403, json.readTree(response.getContentAsString()).get("code").asInt());
        assertNull(response.getRedirectedUrl());
        assertFalse(response.getContentAsString().contains("private ban detail"));
    }

    @Test
    void anOrdinaryRest403IsPreservedAndDoesNotRedirectToTheBrowserErrorPage() throws Exception {
        MockHttpServletResponse response = mvc.perform(get("/legacy/rest/permission"))
                .andReturn().getResponse();

        assertEquals(403, response.getStatus());
        assertEquals("permission_denied", json.readTree(response.getContentAsString()).get("code").asText());
        assertNull(response.getRedirectedUrl());
    }

    @Test
    void aBannedBrowserPageStillRedirectsToThePublicErrorRoute() throws Exception {
        MockHttpServletResponse response = mvc.perform(get("/legacy/browser/denied").accept("text/html"))
                .andReturn().getResponse();

        assertEquals(302, response.getStatus());
        assertEquals("/forbidden", response.getRedirectedUrl());
    }

    private MockHttpServletRequestBuilder loginRequest(boolean ajax) {
        return loginRequest(ajax, PASSWORD);
    }

    private MockHttpServletRequestBuilder loginRequest(boolean ajax, String password) {
        return post("/perform_login").servletPath("/perform_login")
                .accept(ajax ? "application/json" : "text/html")
                .param("username", USER).param("password", password);
    }

    private void assertAuthenticated(MockHttpServletResponse response) throws Exception {
        Cookie cookie = response.getCookie(TOKEN_NAME);
        assertNotNull(cookie, response.getContentAsString());
        assertEquals(USER, StpUtil.getLoginIdByToken(cookie.getValue()));
    }

    private String encrypt(String password, String publicKey) throws Exception {
        Cipher cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding");
        cipher.init(Cipher.ENCRYPT_MODE, KeyFactory.getInstance("RSA").generatePublic(
                new X509EncodedKeySpec(Base64.getDecoder().decode(publicKey))));
        return Base64.getEncoder().encodeToString(cipher.doFinal(password.getBytes(StandardCharsets.UTF_8)));
    }

    @RestController
    public static class RestDenialController {
        @GetMapping("/legacy/rest/denied")
        public Map<String, Object> denied() { throw new IpBannedException("private ban detail"); }

        @GetMapping("/legacy/rest/permission")
        public ResponseEntity<Map<String, String>> permission() {
            return ResponseEntity.status(403).body(Collections.singletonMap("code", "permission_denied"));
        }
    }

    public static class AccountContextController extends BaseController {
        public String currentUsername() { return UserContext.getUsername(); }
        public void failingOperation() { throw new IllegalStateException(UserContext.getUsername()); }
    }

    @Controller
    public static class BrowserDenialController {
        @GetMapping({"/legacy/method/denied", "/api/denied"})
        @ResponseBody
        public Map<String, Object> apiDenied() { throw new IpBannedException("private ban detail"); }

        @GetMapping("/legacy/entity/denied")
        public ResponseEntity<Map<String, Object>> entityDenied() { throw new IpBannedException("private ban detail"); }

        @GetMapping("/legacy/browser/denied")
        public String browserDenied() { throw new IpBannedException("private ban detail"); }
    }
}
