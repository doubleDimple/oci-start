package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.config.annotations.CheckLoginUser;
import com.doubledimple.ociserver.config.annotations.IpBanAspect;
import com.doubledimple.ociserver.config.annotations.LoginUserAspect;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.service.LoginAttemptService;
import org.aspectj.lang.annotation.Pointcut;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.aop.aspectj.AspectJExpressionPointcut;
import org.springframework.aop.aspectj.annotation.AspectJProxyFactory;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.servlet.http.HttpServletRequest;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Controller methods must remain protected after removing the inherited template model hook. */
class IpBanInheritanceTest {
    private static final String CLIENT_IP = "192.0.2.24";
    private HttpServletRequest request;
    private LoginAttemptService attempts;
    private ResourceController target;
    private ResourceController proxy;

    @BeforeEach
    void setup() {
        request = mock(HttpServletRequest.class);
        when(request.getRemoteAddr()).thenReturn(CLIENT_IP);
        attempts = mock(LoginAttemptService.class);
        IpBanAspect aspect = new IpBanAspect();
        ReflectionTestUtils.setField(aspect, "request", request);
        ReflectionTestUtils.setField(aspect, "loginAttemptService", attempts);

        target = new ResourceController();
        AspectJProxyFactory factory = new AspectJProxyFactory(target);
        factory.setProxyTargetClass(true);
        factory.addAspect(aspect);
        proxy = factory.getProxy();
    }

    @Test
    void activeBanRejectsSubclassApiBeforeBusinessLogicRuns() {
        doThrow(new IpBannedException("banned")).when(attempts).assertAllowed(CLIENT_IP);

        assertThrows(IpBannedException.class, () -> proxy.readResource());

        assertEquals(0, target.invocations);
        verify(attempts).assertAllowed(CLIENT_IP);
    }

    @Test
    void allowedIpCanReachSubclassApi() {
        assertEquals("resource", proxy.readResource());

        assertEquals(1, target.invocations);
        verify(attempts).assertAllowed(CLIENT_IP);
    }

    @ParameterizedTest
    @ValueSource(strings = {"127.0.0.1", "192.0.2.99", "::1", "127.0.0.1, 192.0.2.99"})
    void changingForwardedHeadersCannotBypassTheActualClientsBan(String forgedIp) {
        when(request.getHeader("X-Forwarded-For")).thenReturn(forgedIp);
        when(request.getHeader("X-Real-IP")).thenReturn(forgedIp);
        doThrow(new IpBannedException("banned")).when(attempts).assertAllowed(CLIENT_IP);

        assertThrows(IpBannedException.class, () -> proxy.readResource());

        assertEquals(0, target.invocations);
        verify(attempts).assertAllowed(CLIENT_IP);
        verifyNoMoreInteractions(attempts);
    }

    @Test
    void loginUserAdviceStillMatchesSubclassBusinessMethods() throws Exception {
        assertNotNull(ResourceController.class.getAnnotation(CheckLoginUser.class));
        Pointcut declaration = LoginUserAspect.class.getMethod("loginCheckPointcut").getAnnotation(Pointcut.class);
        AspectJExpressionPointcut pointcut = new AspectJExpressionPointcut();
        pointcut.setExpression(declaration.value());

        assertTrue(pointcut.matches(ResourceController.class.getMethod("readResource"), ResourceController.class));
    }

    public static class ResourceController extends BaseController {
        private int invocations;

        @GetMapping("/test/resources")
        @ResponseBody
        public String readResource() {
            invocations++;
            return "resource";
        }
    }
}
