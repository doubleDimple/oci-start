package com.doubledimple.ociserver.config;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.doubledimple.dao.entity.AuditLog;
import com.doubledimple.ociserver.config.annotations.AuditLogAspect;
import com.doubledimple.ociserver.pojo.request.PasswordUpdateRequest;
import com.doubledimple.ociserver.service.AuditLogService;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.reflect.MethodSignature;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AuditLogRedactionTest {

    @Test
    void redactsQueryFormAndNestedRequestSecretsWhileKeepingUsefulFields() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setQueryString("username=alice&password=query-secret&verificationCode=784329");
        request.addParameter("username", "alice");
        request.addParameter("password", "query-secret");
        request.addParameter("verificationCode", "784329");
        request.addParameter("mfaCode", "164982");
        request.addParameter("private_key", "private-key-secret");

        PasswordUpdateRequest update = new PasswordUpdateRequest();
        update.setCurrentPassword("old-password-secret");
        update.setNewPassword("new-password-secret");
        Map<String, Object> nested = new LinkedHashMap<>();
        nested.put("resetToken", "token-secret");
        nested.put("api-key", "api-secret");
        nested.put("code", "625891");
        nested.put("region", "ap-singapore-1");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("account", update);
        body.put("items", Arrays.asList(nested));

        String result = ReflectionTestUtils.invokeMethod(new AuditLogAspect(), "extractSafeParams",
                request, joinPoint(new Object[]{body}, new String[]{"request"}));

        assertNotNull(result);
        for (String secret : new String[]{"query-secret", "784329", "164982", "private-key-secret",
                "old-password-secret", "new-password-secret", "token-secret", "api-secret", "625891"}) {
            assertFalse(result.contains(secret), result);
        }
        JSONObject parsed = JSON.parseObject(result);
        assertTrue(result.contains("alice"));
        assertTrue(result.contains("ap-singapore-1"));
        assertEquals("******", parsed.getJSONObject("_parameters").getString("password"));
        assertEquals("******", parsed.getJSONObject("request").getJSONObject("account").getString("currentPassword"));
    }

    @Test
    void auditFailureRecordsDoNotStoreExceptionMessagesContainingCredentials() throws Throwable {
        AuditLogService service = mock(AuditLogService.class);
        AuditLogAspect aspect = new AuditLogAspect();
        ReflectionTestUtils.setField(aspect, "auditLogService", service);
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/perform_login");
        request.addParameter("username", "alice");
        request.setRemoteAddr("127.0.0.1");
        ProceedingJoinPoint joinPoint = joinPoint(new Object[0], new String[0]);
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        when(signature.getMethod()).thenReturn(Endpoint.class.getMethod("login"));
        when(signature.getName()).thenReturn("login");
        when(joinPoint.getTarget()).thenReturn(new Endpoint());
        IllegalStateException failure = new IllegalStateException("password=cleartext-secret");
        when(joinPoint.proceed()).thenThrow(failure);
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request));
        try {
            assertSame(failure, assertThrows(IllegalStateException.class, () -> aspect.doAround(joinPoint)));
        } finally {
            RequestContextHolder.resetRequestAttributes();
        }
        ArgumentCaptor<AuditLog> record = ArgumentCaptor.forClass(AuditLog.class);
        verify(service).saveAuditLog(record.capture());
        assertEquals("IllegalStateException", record.getValue().getErrorMsg());
        assertFalse(JSON.toJSONString(record.getValue()).contains("cleartext-secret"));
    }

    private ProceedingJoinPoint joinPoint(Object[] args, String[] names) {
        ProceedingJoinPoint point = mock(ProceedingJoinPoint.class);
        MethodSignature signature = mock(MethodSignature.class);
        when(point.getSignature()).thenReturn(signature);
        when(point.getArgs()).thenReturn(args);
        when(signature.getParameterNames()).thenReturn(names);
        return point;
    }

    public static class Endpoint {
        public void login() {}
    }
}
