package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.config.exception.GlobalExceptionHandler;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.*;

class GlobalExceptionHandlerTest {
    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();
    private final IpBannedException exception = new IpBannedException("private ban reason for 192.0.2.1");

    @ParameterizedTest
    @CsvSource({"/api/auth/bootstrap,none", "/m/api/tenants,none",
            "/perform_login,application/json", "/perform_login,xhr"})
    void blockedApiRequestsReturn403WithoutPrivateDetails(String path, String responseType) throws Exception {
        MockHttpServletRequest request = request("POST", path);
        if ("xhr".equals(responseType)) {
            request.addHeader("X-Requested-With", "XMLHttpRequest");
        } else if (!"none".equals(responseType)) {
            request.addHeader("Accept", responseType);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();

        handler.handleIpBannedException(exception, request, response);

        assertEquals(403, response.getStatus());
        assertEquals("no-store", response.getHeader("Cache-Control"));
        assertEquals("application/json;charset=UTF-8", response.getContentType());
        assertEquals("{\"code\":403,\"message\":\"访问被拒绝\"}", response.getContentAsString());
        assertNull(response.getRedirectedUrl());
    }

    @Test
    void blockedBrowserRequestsRedirectToPublicErrorRouteWithoutPrivateDetails() throws Exception {
        MockHttpServletRequest request = request("GET", "/login");
        request.setContextPath("/oci");
        request.addHeader("Accept", "text/html");
        MockHttpServletResponse response = new MockHttpServletResponse();

        handler.handleIpBannedException(exception, request, response);

        assertEquals(302, response.getStatus());
        assertEquals("/oci/forbidden", response.getRedirectedUrl());
        assertEquals("", response.getContentAsString());
        assertNull(response.getForwardedUrl());
    }

    @Test
    void blockedHeadRequestsHaveNoResponseBody() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        handler.handleIpBannedException(exception, request("HEAD", "/api/auth/bootstrap"), response);

        assertEquals(403, response.getStatus());
        assertEquals("", response.getContentAsString());
    }

    private MockHttpServletRequest request(String method, String path) {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setServletPath(path);
        return request;
    }
}
