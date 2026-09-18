package com.doubledimple.ociserver.config;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.ocicommon.utils.RsaUtils;
import com.doubledimple.ociserver.config.filter.RsaDecryptionFilter;
import com.doubledimple.ociserver.controller.LoginController;
import com.doubledimple.ociserver.service.VerifyService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.service.mfa.OTPService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import javax.crypto.Cipher;
import javax.servlet.http.HttpServletRequest;
import java.security.KeyFactory;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Map;

import static com.doubledimple.ocicommon.constant.Constants.RSA_PRIVATE_KEY;
import static com.doubledimple.ocicommon.constant.Constants.RSA_PUBLIC_KEY;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Real session keys and servlet responses, with no database or external authentication calls. */
class VueAuthenticationTest {
    private final ObjectMapper json = new ObjectMapper();
    private LoginController controller;
    private SystemConfigService settings;
    private LoginUserService users;
    private VerifyService verification;
    private OTPService otp;

    @BeforeEach
    void setup() {
        controller = new LoginController();
        settings = mock(SystemConfigService.class, RETURNS_DEEP_STUBS);
        users = mock(LoginUserService.class);
        verification = mock(VerifyService.class);
        otp = mock(OTPService.class);
        ReflectionTestUtils.setField(controller, "systemConfigService", settings);
        ReflectionTestUtils.setField(controller, "loginUserService", users);
        ReflectionTestUtils.setField(controller, "verifyService", verification);
        ReflectionTestUtils.setField(controller, "otpService", otp);
        ReflectionTestUtils.setField(controller, "objectMapper", json);
        when(settings.getSiteLogoName()).thenReturn("OCI Start");
    }

    @Test
    void bootstrapReusesSessionKeysAndExposesOnlyPublicConfiguration() throws Exception {
        when(settings.getTurnstileConfig().isEnabled()).thenReturn(true);
        when(settings.getTurnstileConfig().getSiteKey()).thenReturn("public-site-key");
        when(settings.getTurnstileConfig().getSecretKey()).thenReturn("private-turnstile-secret");
        when(settings.getMfaConfig().isEnabled()).thenReturn(true);
        when(verification.isMessageEnabled()).thenReturn(true);
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/auth/bootstrap");
        ResponseEntity<Map<String, Object>> first = controller.bootstrap(request);
        assertEquals(200, first.getStatusCodeValue());
        assertEquals("no-store", first.getHeaders().getCacheControl());
        assertEquals(true, first.getBody().get("allowRegister"));
        assertEquals(true, first.getBody().get("messageEnabled"));
        assertEquals(true, first.getBody().get("mfaEnabled"));
        assertEquals("public-site-key", first.getBody().get("turnstileSiteKey"));
        String publicKey = (String) first.getBody().get("publicKey");
        String privateKey = (String) request.getSession().getAttribute(RSA_PRIVATE_KEY);
        assertEquals(publicKey, request.getSession().getAttribute(RSA_PUBLIC_KEY));
        assertEquals(publicKey, controller.bootstrap(request).getBody().get("publicKey"));
        String payload = json.writeValueAsString(first.getBody());
        assertFalse(payload.contains(privateKey));
        assertFalse(payload.contains("private-turnstile-secret"));
        // Same public key returned to Vue must decrypt with the session used by the login filter.
        assertEquals("test-password", RsaUtils.decrypt(encrypt("test-password", publicKey), privateKey));
    }

    @Test
    void bootstrapHidesRegistrationAfterSetupAndRepairsIncompleteSessionKeys() {
        when(users.existsAnyUser()).thenReturn(true);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.getSession().setAttribute(RSA_PUBLIC_KEY, "orphaned-public-key");
        Map<String, Object> body = controller.bootstrap(request).getBody();
        assertEquals(false, body.get("allowRegister"));
        assertNotEquals("orphaned-public-key", body.get("publicKey"));
        assertNotNull(request.getSession().getAttribute(RSA_PRIVATE_KEY));
        assertEquals("", body.get("turnstileSiteKey"));
    }

    @Test
    void bootstrapFailureIsNotCachedAndContainsNoInternalError() {
        when(settings.getSiteLogoName()).thenThrow(new IllegalStateException("internal credentials"));
        ResponseEntity<Map<String, Object>> response = controller.bootstrap(new MockHttpServletRequest());
        assertEquals(503, response.getStatusCodeValue());
        assertEquals("no-store", response.getHeaders().getCacheControl());
        assertFalse(response.getBody().containsKey("publicKey"));
        assertFalse(response.getBody().toString().contains("internal credentials"));
    }

    @Test
    void failedAjaxLoginProducesValidJsonEvenForQuotedMultilineMessages() throws Exception {
        String message = "登录失败\n\"quoted\"\\reason";
        when(users.validateCredentials(anyString(), anyString())).thenThrow(new IllegalArgumentException(message));
        MockHttpServletResponse response = new MockHttpServletResponse();
        controller.performLogin(loginRequest(), response);
        assertEquals(401, response.getStatus());
        assertNull(response.getRedirectedUrl());
        assertEquals(message, json.readTree(response.getContentAsString()).get("message").asText());
    }

    @Test
    void configuredMessageFactorCannotBeSkippedByVueOrNativeClients() throws Exception {
        when(users.validateCredentials(anyString(), anyString())).thenReturn(new LoginUser());
        when(verification.isMessageEnabled()).thenReturn(true);
        MockHttpServletResponse response = new MockHttpServletResponse();
        controller.performLogin(loginRequest(), response);
        assertEquals(401, response.getStatus());
        assertFalse(json.readTree(response.getContentAsString()).get("success").asBoolean());
        verifyNoInteractions(otp);
    }

    @Test
    void rsaFilterDecryptsPasswordFromBootstrapSession() throws Exception {
        MockHttpServletRequest bootstrap = new MockHttpServletRequest();
        String publicKey = (String) controller.bootstrap(bootstrap).getBody().get("publicKey");
        MockHttpServletRequest request = loginRequest();
        request.setSession((MockHttpSession) bootstrap.getSession());
        request.setParameter("password", encrypt("encrypted-password", publicKey));
        MockFilterChain chain = new MockFilterChain();
        new RsaDecryptionFilter(settings, mock(RestTemplate.class))
                .doFilter(request, new MockHttpServletResponse(), chain);
        assertEquals("encrypted-password", ((HttpServletRequest) chain.getRequest()).getParameter("password"));
    }

    @Test
    void missingTurnstileTokenStopsAjaxLoginWithJsonInsteadOfRedirect() throws Exception {
        when(settings.getTurnstileConfig().isEnabled()).thenReturn(true);
        when(settings.getTurnstileConfig().getSecretKey()).thenReturn("test-secret");
        MockFilterChain chain = new MockFilterChain();
        MockHttpServletResponse response = new MockHttpServletResponse();
        RestTemplate remote = mock(RestTemplate.class);
        new RsaDecryptionFilter(settings, remote).doFilter(loginRequest(), response, chain);
        assertEquals(403, response.getStatus());
        assertEquals("TURNSTILE_FAILED", json.readTree(response.getContentAsString()).get("code").asText());
        assertNull(response.getRedirectedUrl());
        assertNull(chain.getRequest());
        verifyNoInteractions(remote);
    }

    @Test
    void unavailableChallengeConfigurationCannotSilentlyAuthenticate() throws Exception {
        when(settings.getTurnstileConfig()).thenThrow(new IllegalStateException("unavailable"));
        MockFilterChain chain = new MockFilterChain();
        MockHttpServletResponse response = new MockHttpServletResponse();
        new RsaDecryptionFilter(settings, mock(RestTemplate.class)).doFilter(loginRequest(), response, chain);
        assertEquals(503, response.getStatus());
        assertNull(chain.getRequest());
    }

    private MockHttpServletRequest loginRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/perform_login");
        request.setServletPath("/perform_login");
        request.addHeader("Accept", "application/json");
        request.addParameter("username", "test-user");
        request.addParameter("password", "test-password");
        return request;
    }

    private String encrypt(String password, String publicKey) throws Exception {
        String encoded = publicKey.replaceAll("-----[A-Z ]+-----", "").replaceAll("\\s", "");
        Cipher cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding");
        cipher.init(Cipher.ENCRYPT_MODE, KeyFactory.getInstance("RSA")
                .generatePublic(new X509EncodedKeySpec(Base64.getDecoder().decode(encoded))));
        return Base64.getEncoder().encodeToString(cipher.doFinal(password.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
    }
}
