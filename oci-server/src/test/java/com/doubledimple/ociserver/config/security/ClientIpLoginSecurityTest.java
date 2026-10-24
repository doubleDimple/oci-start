package com.doubledimple.ociserver.config.security;

import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.entity.LoginFailureState;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.dao.repository.LoginFailureStateRepository;
import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.service.LoginAttemptService;
import com.doubledimple.ociserver.service.login.LoginFailureGuard;
import com.doubledimple.ociserver.service.security.LoginIpTransactions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletRequestWrapper;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.Executor;
import java.util.function.Function;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/** Exercises the real resolver, filter, guard and failure counters without a database or notifications. */
class ClientIpLoginSecurityTest {
    private static final String CLIENT_IP = "203.0.113.80";
    private final Map<String, LoginFailureState> failures = new HashMap<>();
    private final Map<String, BanRecord> bans = new HashMap<>();
    private final ClientIpFilter filter = new ClientIpFilter(new ClientIpResolver("127.0.0.1/32,::1/128"));
    private LoginFailureGuard guard;

    @BeforeEach
    void setup() {
        LoginFailureStateRepository failureRepository = mock(LoginFailureStateRepository.class);
        BanRecordRepository banRepository = mock(BanRecordRepository.class);
        LoginIpTransactions transactions = mock(LoginIpTransactions.class);
        doAnswer(invocation -> {
            String ip = invocation.getArgument(0);
            Function<String, Object> operation = invocation.getArgument(1);
            return operation.apply(LoginIpTransactions.normalizeIp(ip));
        }).when(transactions).execute(anyString(), any());
        when(failureRepository.findById(anyString())).thenAnswer(invocation ->
                Optional.ofNullable(failures.get(invocation.getArgument(0))));
        when(failureRepository.save(any(LoginFailureState.class))).thenAnswer(invocation -> {
            LoginFailureState state = invocation.getArgument(0);
            failures.put(state.getIpAddress(), state);
            return state;
        });
        when(banRepository.findTopByIpAddressAndStatusOrderByIdDesc(anyString(), eq(1)))
                .thenAnswer(invocation -> bans.get(invocation.getArgument(0)));
        when(banRepository.save(any(BanRecord.class))).thenAnswer(invocation -> {
            BanRecord ban = invocation.getArgument(0);
            bans.put(ban.getIpAddress(), ban);
            return ban;
        });
        guard = new LoginFailureGuard();
        ReflectionTestUtils.setField(guard, "loginAttemptService",
                new LoginAttemptService(failureRepository, banRepository, transactions));
        ReflectionTestUtils.setField(guard, "notificationExecutor", (Executor) command -> { });
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void changingForgedHeadersCannotSplitFailureCountsOrEvadeTheResultingBan(boolean proxied) throws Exception {
        failLogin(request(CLIENT_IP, proxied, "127.0.0.1"), false);
        failLogin(request(CLIENT_IP, proxied, "192.0.2.99"), false);

        assertThrows(IpBannedException.class,
                () -> failLogin(request(CLIENT_IP, proxied, "2001:db8:3::9"), false));
        assertThrows(IpBannedException.class,
                () -> assertAllowed(request(CLIENT_IP, proxied, "192.0.2.100")));

        assertEquals(1, failures.size());
        assertEquals(3, failures.get(CLIENT_IP).getWrongPasswordCount());
        assertEquals(1, bans.size());
        assertTrue(bans.containsKey(CLIENT_IP));
        assertFalse(bans.containsKey("127.0.0.1"));
        assertFalse(bans.containsKey("192.0.2.99"));
    }

    @Test
    void directAndLocalProxyAccessShareTheSameClientsFailureLimit() throws Exception {
        failLogin(request(CLIENT_IP, false, "127.0.0.1"), true);

        assertThrows(IpBannedException.class,
                () -> failLogin(request(CLIENT_IP, true, "192.0.2.99"), true));
        assertThrows(IpBannedException.class,
                () -> assertAllowed(request(CLIENT_IP, false, "192.0.2.100")));
        assertThrows(IpBannedException.class,
                () -> assertAllowed(request(CLIENT_IP, true, "192.0.2.101")));

        assertEquals(2, failures.get(CLIENT_IP).getUnknownUsernameCount());
        assertEquals(1, bans.size());
    }

    @Test
    void oneBannedProxyClientDoesNotBanTheProxyOrAnUnrelatedClient() throws Exception {
        failLogin(request(CLIENT_IP, true, "127.0.0.1"), true);
        assertThrows(IpBannedException.class,
                () -> failLogin(request(CLIENT_IP, true, "192.0.2.99"), true));

        assertDoesNotThrow(() -> assertAllowed(request("203.0.113.81", true, CLIENT_IP)));
        assertFalse(bans.containsKey("127.0.0.1"));
        assertFalse(bans.containsKey("203.0.113.81"));
    }

    @Test
    void missingProxyForwardingInformationIsRejectedWithoutCountingAgainstLoopback() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr("127.0.0.1");
        request.addHeader("X-Real-IP", CLIENT_IP);

        assertThrows(IpBannedException.class, () -> failLogin(request, true));
        assertTrue(failures.isEmpty());
        assertTrue(bans.isEmpty());
    }

    @Test
    void utilityFallbackWithoutTheFilterStillIgnoresClientSuppliedHeaders() {
        MockHttpServletRequest request = request(CLIENT_IP, false, "127.0.0.1");

        assertEquals(CLIENT_IP, IpUtils.getClientIpAddress(request));
        assertEquals(CLIENT_IP, guard.assertAllowed(request));
    }

    @Test
    void securityChecksKeepTheAddressCapturedBeforeLaterRequestWrappers() throws Exception {
        MockHttpServletRequest request = request(CLIENT_IP, true, "127.0.0.1");
        filter.doFilter(request, new MockHttpServletResponse(), (incoming, response) -> {
            HttpServletRequestWrapper wrapper = new HttpServletRequestWrapper((HttpServletRequest) incoming) {
                @Override
                public String getRemoteAddr() { return "192.0.2.99"; }

                @Override
                public String getHeader(String name) { return "127.0.0.1"; }
            };
            assertEquals(CLIENT_IP, IpUtils.getClientIpAddress(wrapper));
            assertEquals(CLIENT_IP, guard.assertAllowed(wrapper));
        });
    }

    private void failLogin(MockHttpServletRequest request, boolean unknownUsername) throws Exception {
        filter.doFilter(request, new MockHttpServletResponse(), (incoming, response) -> {
            String clientIp = guard.assertAllowed((HttpServletRequest) incoming);
            guard.failed(clientIp, "invalid-login-user", unknownUsername);
        });
    }

    private void assertAllowed(MockHttpServletRequest request) throws Exception {
        filter.doFilter(request, new MockHttpServletResponse(),
                (incoming, response) -> guard.assertAllowed((HttpServletRequest) incoming));
    }

    private static MockHttpServletRequest request(String clientIp, boolean proxied, String forgedIp) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr(proxied ? "127.0.0.1" : clientIp);
        request.addHeader("X-Forwarded-For", proxied ? forgedIp + ", " + clientIp : forgedIp);
        request.addHeader("X-Real-IP", forgedIp);
        request.addHeader("Proxy-Client-IP", forgedIp);
        return request;
    }
}
