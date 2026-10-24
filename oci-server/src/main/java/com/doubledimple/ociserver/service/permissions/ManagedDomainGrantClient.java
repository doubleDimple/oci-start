package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.ociserver.config.ProxyContext;
import com.fasterxml.jackson.databind.JsonNode;
import com.oracle.bmc.ClientConfiguration;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.http.client.Method;
import com.oracle.bmc.http.internal.ClientCall;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.requests.BmcRequest;
import com.oracle.bmc.responses.BmcResponse;
import org.slf4j.helpers.NOPLogger;

import java.util.List;
import java.util.Map;

/**
 * The 3.92 SDK omits IDCSAppRoleGrants and its appRoleLimitedTo extension.
 * Use the SDK transport, signing and configured proxy for this documented API.
 * No caller-supplied host or arbitrary resource path is accepted here.
 */
final class ManagedDomainGrantClient extends IdentityDomainsClient {
    ManagedDomainGrantClient(SimpleAuthenticationDetailsProvider provider, String endpoint) {
        super(provider, ClientConfiguration.builder().build(), ProxyContext.get());
        setEndpoint(endpoint);
    }

    RawResponse request(Method method, String resource, String id,
                        Map<String, Object> query, Map<String, Object> body,
                        String ifMatch, String retryToken) {
        if (!"IDCSAppRoleGrants".equals(resource) && !"Grants".equals(resource)) {
            throw new IllegalArgumentException("不支持的身份域授权资源。");
        }
        if (id != null && !id.matches("[A-Za-z0-9._:-]{1,255}")) {
            throw new IllegalArgumentException("身份域授权标识无效。");
        }
        RawRequest request = new RawRequest(body);
        ClientCall<RawRequest, RawResponse, RawResponse.Builder> call =
                clientCall(request, RawResponse.Builder::new)
                        // ClientCall requires a logger even when logging is disabled. Its DEBUG/TRACE
                        // logs include request URIs and SDK errors, so keep this credentialed transport quiet.
                        .logger(NOPLogger.NOP_LOGGER, "ManagedDomainGrant")
                        .serviceDetails("IdentityDomains", "ManagedDomainGrant", "")
                        .method(method)
                        .requestBuilder(RawRequest.Builder::new)
                        .basePath("")
                        .appendPathPart("admin")
                        .appendPathPart("v1")
                        .appendPathPart(resource)
                        .accept("application/json", "application/scim+json");
        if (id != null) {
            call.appendPathParam(id);
        }
        if (query != null) {
            query.forEach(call::appendQueryParam);
        }
        if (ifMatch != null) {
            call.appendHeader("if-match", ifMatch);
        }
        if (retryToken != null) {
            call.appendHeader("opc-retry-token", retryToken);
        }
        if (body != null) {
            call.hasBody();
        }
        // DELETE responses have no representation.
        if (method != Method.DELETE) {
            call.handleBody(JsonNode.class, (builder, value) -> builder.body = value);
        }
        return call.callSync();
    }

    private static final class RawRequest extends BmcRequest<Map<String, Object>> {
        private final Map<String, Object> body;

        private RawRequest(Map<String, Object> body) {
            this.body = body;
        }

        @Override
        public Map<String, Object> getBody$() {
            return body;
        }

        private static final class Builder implements BmcRequest.Builder<RawRequest, Map<String, Object>> {
            private Map<String, Object> body;
            private RawRequest original;

            @Override
            public Builder body$(Map<String, Object> value) {
                body = value;
                return this;
            }

            @Override
            public Builder copy(RawRequest value) {
                original = value;
                body = value.body;
                return this;
            }

            @Override
            public RawRequest build() {
                RawRequest result = new RawRequest(body);
                if (original != null) {
                    result.setInvocationCallback(original.getInvocationCallback());
                    result.setRetryConfiguration(original.getRetryConfiguration());
                }
                return result;
            }
        }
    }

    static final class RawResponse extends BmcResponse {
        final JsonNode body;

        private RawResponse(int status, Map<String, List<String>> headers, JsonNode body) {
            super(status, headers);
            this.body = body;
        }

        String header(String name) {
            if (getHeaders() == null) {
                return null;
            }
            for (Map.Entry<String, List<String>> entry : getHeaders().entrySet()) {
                if (name.equalsIgnoreCase(entry.getKey())
                        && entry.getValue() != null && !entry.getValue().isEmpty()) {
                    return entry.getValue().get(0);
                }
            }
            return null;
        }

        private static final class Builder implements BmcResponse.Builder<RawResponse> {
            private int status;
            private Map<String, List<String>> headers;
            private JsonNode body;

            @Override
            public Builder __httpStatusCode__(int value) {
                status = value;
                return this;
            }

            @Override
            public Builder headers(Map<String, List<String>> value) {
                headers = value;
                return this;
            }

            @Override
            public Builder copy(RawResponse value) {
                status = value.get__httpStatusCode__();
                headers = value.getHeaders();
                body = value.body;
                return this;
            }

            @Override
            public RawResponse build() {
                return new RawResponse(status, headers, body);
            }
        }
    }
}
