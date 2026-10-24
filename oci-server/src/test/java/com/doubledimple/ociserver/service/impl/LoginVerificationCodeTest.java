package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.controller.ApiController;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.login.LoginFailureGuard;
import com.doubledimple.ociserver.service.login.GlobalLoginGuard;
import com.doubledimple.ociserver.service.login.GlobalLoginGuardTestSupport;
import com.doubledimple.ociserver.service.message.MessageService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.google.common.base.Ticker;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class LoginVerificationCodeTest {
    private static final String USER = "verification-user";
    private static final String IP = "198.51.100.42";
    private final List<String> delivered = new ArrayList<>();
    private VerifyServiceImpl service;
    private MessageService messages;
    private LoginUserRepository users;
    private LoginFailureGuard guard;
    private GlobalLoginGuard globalGuard;
    private MockHttpServletRequest request;
    private ManualTicker clock;

    @BeforeEach
    void setUp() {
        users = mock(LoginUserRepository.class);
        LoginUser user = new LoginUser();
        user.setUsername(USER);
        when(users.findByUsername(USER)).thenReturn(Optional.of(user));
        guard = mock(LoginFailureGuard.class);
        when(guard.assertAllowed(any())).thenReturn(IP);
        messages = mock(MessageService.class);
        doAnswer(call -> { delivered.add(call.getArgument(1)); return null; })
                .when(messages).sendVerificationCodeMessage(eq(USER), anyString());
        MessageFactory factory = mock(MessageFactory.class);
        when(factory.getType(MessageEnum.TELEGRAM)).thenReturn(messages);
        service = new VerifyServiceImpl();
        ReflectionTestUtils.setField(service, "loginUserRepository", users);
        ReflectionTestUtils.setField(service, "loginFailureGuard", guard);
        globalGuard = mock(GlobalLoginGuard.class);
        ReflectionTestUtils.setField(service, "globalLoginGuard", globalGuard);
        ReflectionTestUtils.setField(service, "messageFactory", factory);
        service.init();
        // Drive the production cache's actual expiration policy without waiting or replacing that policy.
        Object cache = ReflectionTestUtils.getField(service, "verificationCodeCache");
        Object localCache = ReflectionTestUtils.getField(cache, "localCache");
        clock = new ManualTicker();
        ReflectionTestUtils.setField(localCache, "ticker", clock);
        request = new MockHttpServletRequest("POST", "/api/send-verification-code");
        request.setRemoteAddr(IP);
    }

    @Test
    void deliveredLoginCodesUseEightUppercaseLettersAndDigitsWithBothKindsPresent() {
        for (int attempt = 0; attempt < 32; attempt++) {
            service.sendVerificationCodeForLogin(USER, request);
        }

        assertEquals(32, delivered.size());
        for (String code : delivered) {
            assertTrue(code.matches("[A-Z0-9]{8}"));
            assertTrue(code.matches(".*[A-Z].*"));
            assertTrue(code.matches(".*[0-9].*"));
        }
        assertTrue(new HashSet<>(delivered).size() > 1, "A fixed code must never be sent for every request");
        verify(guard, times(32)).assertAllowed(request);
    }

    @Test
    void aDeliveredCodeAcceptsLowercaseAndWhitespaceButCanOnlyBeUsedOnce() {
        String code = issueCode();

        assertDoesNotThrow(() -> service.checkCodeForLogin(USER, "  " + code.toLowerCase(Locale.ROOT) + "  "));
        assertThrows(IllegalStateException.class, () -> service.checkCodeForLogin(USER, code));
    }

    @ParameterizedTest
    @ValueSource(strings = {"123456", "ABCDEFGH", "12345678", "AB!12CD3", "AB12CD345", "", "İ1234567"})
    void aWrongCodeCannotAuthenticateOrConsumeTheValidCode(String wrongCode) {
        String code = issueCode();

        assertThrows(IllegalStateException.class, () -> service.checkCodeForLogin(USER, wrongCode));
        assertDoesNotThrow(() -> service.checkCodeForLogin(USER, code));
    }

    @Test
    void aCodeIsBoundToItsUsername() {
        String code = issueCode();

        assertThrows(IllegalStateException.class, () -> service.checkCodeForLogin("another-user", code));
        assertDoesNotThrow(() -> service.checkCodeForLogin(USER, code));
    }

    @Test
    void theExistingFiveMinuteExpirationStillApplies() {
        String beforeExpiry = issueCode();
        clock.advance(5, TimeUnit.MINUTES);
        clock.advance(-1, TimeUnit.NANOSECONDS);
        assertDoesNotThrow(() -> service.checkCodeForLogin(USER, beforeExpiry));

        String atExpiry = issueCode();
        clock.advance(5, TimeUnit.MINUTES);
        assertThrows(IllegalStateException.class, () -> service.checkCodeForLogin(USER, atExpiry));
    }

    @Test
    void issuingANewCodeInvalidatesThePreviousCode() {
        String oldCode = issueCode();
        String currentCode = issueCode();

        assertNotEquals(oldCode, currentCode);
        assertThrows(IllegalStateException.class, () -> service.checkCodeForLogin(USER, oldCode));
        assertDoesNotThrow(() -> service.checkCodeForLogin(USER, currentCode));
    }

    @Test
    void aBannedAddressCannotLookUpTheUserOrSendACode() {
        doThrow(new IpBannedException("blocked")).when(guard).assertAllowed(any());

        assertThrows(IpBannedException.class, () -> service.sendVerificationCodeForLogin(USER, request));

        verifyNoInteractions(users, messages);
        assertTrue(delivered.isEmpty());
    }

    @Test
    void anUnknownUserStillRegistersTheExistingSecurityFailureAndSendsNothing() {
        when(users.findByUsername(USER)).thenReturn(Optional.empty());

        assertThrows(IllegalStateException.class, () -> service.sendVerificationCodeForLogin(USER, request));

        verify(guard).failed(IP, USER, true);
        verifyNoInteractions(messages);
    }

    @Test
    void codesUsedByPasswordResetAndInstanceOperationsRemainSixDigits() {
        for (int attempt = 0; attempt < 8; attempt++) {
            assertTrue(service.generateVerificationCode().matches("[0-9]{6}"));
        }
    }

    @Test
    void theRealApiCanSendAndVerifyAnEightCharacterCodeWithoutNumericCoercion() throws Exception {
        ApiController controller = new ApiController();
        ReflectionTestUtils.setField(controller, "verifyService", service);
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).build();
        mvc.perform(post("/api/send-verification-code").contentType("application/json")
                        .content("{\"username\":\"" + USER + "\"}"))
                .andExpect(status().isOk());
        String code = delivered.get(0);
        String body = "{\"username\":\"" + USER + "\",\"verificationCode\":\"" + code.toLowerCase(Locale.ROOT) + "\"}";

        mvc.perform(post("/api/verify-code-login").contentType("application/json").content(body))
                .andExpect(status().isOk());
        mvc.perform(post("/api/verify-code-login").contentType("application/json").content(body))
                .andExpect(status().isBadRequest());
    }

    @Test
    void aGlobalBlockStopsLoginCodeSendingBeforeAccountLookupOrMessageDelivery() throws Exception {
        doThrow(GlobalLoginGuardTestSupport.blockedException()).when(globalGuard).assertAllowed();
        ApiController controller = new ApiController();
        ReflectionTestUtils.setField(controller, "verifyService", service);
        MockMvc mvc = MockMvcBuilders.standaloneSetup(controller).build();

        org.springframework.mock.web.MockHttpServletResponse response = mvc.perform(post("/api/send-verification-code").contentType("application/json")
                        .content("{\"username\":\"" + USER + "\"}"))
                .andExpect(status().isForbidden()).andReturn().getResponse();

        assertNull(response.getHeader("Retry-After"));
        assertFalse(response.getContentAsString().contains("2026-10-25T00:00"));
        verifyNoInteractions(users, messages, guard);
        assertTrue(delivered.isEmpty());
    }

    private String issueCode() {
        service.sendVerificationCodeForLogin(USER, request);
        return delivered.get(delivered.size() - 1);
    }

    private static final class ManualTicker extends Ticker {
        private long nanos;
        @Override public long read() { return nanos; }
        void advance(long amount, TimeUnit unit) { nanos += unit.toNanos(amount); }
    }
}
