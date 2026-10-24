package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.ociserver.config.ProxyContext;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.http.client.HttpClient;
import com.oracle.bmc.http.client.HttpRequest;
import com.oracle.bmc.http.client.HttpResponse;
import com.oracle.bmc.http.client.Method;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.ByteArrayInputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class ManagedDomainGrantClientTest {
    @AfterEach
    void clearProxy() {
        ProxyContext.clear();
    }

    /** The SDK's real ClientCall runs against an in-memory transport; no HTTP request can leave this test. */
    @ParameterizedTest
    @EnumSource(value = Method.class, names = {"GET", "POST", "DELETE"})
    void rawGrantCallsHaveTheRequiredLoggerAndReachTheTransport(Method method) throws Exception {
        ProxyContext.clear();
        HttpClient transport = mock(HttpClient.class);
        HttpRequest request = mock(HttpRequest.class, RETURNS_SELF);
        HttpResponse response = mock(HttpResponse.class);
        Map<String, List<String>> headers = new LinkedHashMap<>();
        headers.put("opc-request-id", Collections.singletonList("test-request-id"));
        when(transport.createRequest(method)).thenReturn(request);
        when(request.method()).thenReturn(method);
        when(request.uri()).thenReturn(URI.create("https://unit-test.invalid/admin/v1/Grants"));
        when(request.headers()).thenReturn(headers);
        when(request.execute()).thenReturn(CompletableFuture.completedFuture(response));
        when(response.status()).thenReturn(method == Method.DELETE ? 204 : 200);
        when(response.headers()).thenReturn(Collections.singletonMap("etag", Collections.singletonList("version-1")));
        JsonNode body = new ObjectMapper().readTree("{\"Resources\":[],\"totalResults\":0,\"startIndex\":1}");
        when(response.body(JsonNode.class)).thenReturn(CompletableFuture.completedFuture(body));

        try (ManagedDomainGrantClient client = new ManagedDomainGrantClient(provider(), "https://unit-test.invalid")) {
            // Replace and close the dormant SDK transport before making any operation call.
            HttpClient dormant = (HttpClient) ReflectionTestUtils.getField(client, "httpClient");
            assertNotNull(dormant);
            dormant.close();
            ReflectionTestUtils.setField(client, "httpClient", transport);
            ReflectionTestUtils.setField(client, "circuitBreaker", null);

            ManagedDomainGrantClient.RawResponse result = client.request(method,
                    "Grants", method == Method.GET ? null : "grant-1",
                    Collections.singletonMap("filter", "grantee.value eq \"test-user\""),
                    method == Method.POST ? Collections.singletonMap("grantee", "test-user") : null,
                    method == Method.DELETE ? "version-1" : null, null);

            assertEquals(method == Method.DELETE ? 204 : 200, result.get__httpStatusCode__());
            if (method == Method.DELETE) assertNull(result.body);
            else assertSame(body, result.body);
            assertEquals("version-1", result.header("ETag"));
            verify(request).execute();
            verify(request).appendPathPart("admin");
            verify(request).appendPathPart("v1");
            verify(request).appendPathPart("Grants");
            if (method == Method.POST) {
                verify(request, atLeastOnce()).body(Collections.singletonMap("grantee", "test-user"));
            }
            if (method == Method.DELETE) {
                verify(request).header("if-match", "version-1");
            }
        }
        verify(transport).close();
    }

    private static SimpleAuthenticationDetailsProvider provider() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        String key = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(generator.generateKeyPair().getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----\n";
        byte[] bytes = key.getBytes(StandardCharsets.US_ASCII);
        return SimpleAuthenticationDetailsProvider.builder()
                .tenantId("ocid1.tenancy.oc1..unit-test")
                .userId("ocid1.user.oc1..unit-test")
                .fingerprint("00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00")
                .privateKeySupplier(() -> new ByteArrayInputStream(bytes))
                .region(Region.US_ASHBURN_1).build();
    }
}
