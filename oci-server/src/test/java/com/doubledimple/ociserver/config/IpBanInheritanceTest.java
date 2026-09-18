package com.doubledimple.ociserver.config;

import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.ociserver.config.annotations.CheckLoginUser;
import com.doubledimple.ociserver.config.annotations.IpBanAspect;
import com.doubledimple.ociserver.config.annotations.LoginUserAspect;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.controller.BaseController;
import org.aspectj.lang.annotation.Pointcut;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullSource;
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
    private BanRecordRepository bans;
    private ResourceController target;
    private ResourceController proxy;

    @BeforeEach
    void setup() {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getRemoteAddr()).thenReturn(CLIENT_IP);
        bans = mock(BanRecordRepository.class);
        IpBanAspect aspect = new IpBanAspect();
        ReflectionTestUtils.setField(aspect, "request", request);
        ReflectionTestUtils.setField(aspect, "banRecordRepository", bans);

        target = new ResourceController();
        AspectJProxyFactory factory = new AspectJProxyFactory(target);
        factory.setProxyTargetClass(true);
        factory.addAspect(aspect);
        proxy = factory.getProxy();
    }

    @Test
    void activeBanRejectsSubclassApiBeforeBusinessLogicRuns() {
        BanRecord ban = new BanRecord();
        ban.setStatus(1);
        when(bans.findTopByIpAddress(CLIENT_IP)).thenReturn(ban);

        assertThrows(IpBannedException.class, () -> proxy.readResource());

        assertEquals(0, target.invocations);
        verify(bans).findTopByIpAddress(CLIENT_IP);
    }

    @ParameterizedTest
    @NullSource
    @ValueSource(ints = 0)
    void missingOrInactiveBanAllowsSubclassApi(Integer status) {
        BanRecord ban = null;
        if (status != null) {
            ban = new BanRecord();
            ban.setStatus(status);
        }
        when(bans.findTopByIpAddress(CLIENT_IP)).thenReturn(ban);

        assertEquals("resource", proxy.readResource());

        assertEquals(1, target.invocations);
        verify(bans).findTopByIpAddress(CLIENT_IP);
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
