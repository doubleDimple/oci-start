package com.doubledimple.ociserver.config.security;

import com.doubledimple.ociserver.config.filter.RsaDecryptionFilter;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpEntity;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import javax.servlet.FilterChain;
import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class RsaClientIpTest {
    private static final String CLIENT_IP = "203.0.113.80";
    private static final String VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
    private final ClientIpFilter clientIpFilter =
            new ClientIpFilter(new ClientIpResolver("127.0.0.1/32,::1/128"));
    private RestTemplate remote;
    private RsaDecryptionFilter rsaFilter;

    @BeforeEach
    void setup() {
        SystemConfigService settings = mock(SystemConfigService.class);
        TurnstileConfig challenge = new TurnstileConfig();
        challenge.setEnabled(true);
        challenge.setSecretKey("test-turnstile-secret");
        when(settings.getTurnstileConfig()).thenReturn(challenge);
        remote = mock(RestTemplate.class);
        ResponseEntity<Map> verified = ResponseEntity.ok(Collections.singletonMap("success", true));
        when(remote.postForEntity(eq(VERIFY_URL), any(HttpEntity.class), eq(Map.class))).thenReturn(verified);
        rsaFilter = new RsaDecryptionFilter(settings, remote);
    }

    @Test
    void localReverseProxySubmitsTheResolvedClientAddressToTurnstile() throws Exception {
        MultiValueMap<String, String> body = verifyChallenge("127.0.0.1", "127.0.0.1, " + CLIENT_IP);

        assertEquals(Collections.singletonList(CLIENT_IP), body.get("remoteip"));
    }

    @Test
    void directAccessIgnoresForgedHeadersWhenSubmittingTurnstileAddress() throws Exception {
        MultiValueMap<String, String> body = verifyChallenge(CLIENT_IP, "127.0.0.1");

        assertEquals(Collections.singletonList(CLIENT_IP), body.get("remoteip"));
    }

    @Test
    void unidentifiedProxyClientOmitsOptionalRemoteIpInsteadOfSubmittingTheProxy() throws Exception {
        MultiValueMap<String, String> body = verifyChallenge("127.0.0.1", null);

        assertFalse(body.containsKey("remoteip"));
    }

    @SuppressWarnings("unchecked")
    private MultiValueMap<String, String> verifyChallenge(String peer, String forwardedFor) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/perform_login");
        request.setServletPath("/perform_login");
        request.setRemoteAddr(peer);
        request.addParameter("cf-turnstile-response", "test-challenge-response");
        if (forwardedFor != null) request.addHeader("X-Forwarded-For", forwardedFor);
        request.addHeader("X-Real-IP", "192.0.2.99");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain login = mock(FilterChain.class);

        clientIpFilter.doFilter(request, response,
                (resolved, outgoing) -> rsaFilter.doFilter(resolved, outgoing, login));

        ArgumentCaptor<HttpEntity> submitted = ArgumentCaptor.forClass(HttpEntity.class);
        verify(remote).postForEntity(eq(VERIFY_URL), submitted.capture(), eq(Map.class));
        verifyNoMoreInteractions(remote);
        verify(login).doFilter(any(), any());
        assertEquals(200, response.getStatus());
        assertEquals(MediaType.APPLICATION_FORM_URLENCODED, submitted.getValue().getHeaders().getContentType());
        MultiValueMap<String, String> body = (MultiValueMap<String, String>) submitted.getValue().getBody();
        assertNotNull(body);
        assertEquals("test-turnstile-secret", body.getFirst("secret"));
        assertEquals("test-challenge-response", body.getFirst("response"));
        return body;
    }
}
