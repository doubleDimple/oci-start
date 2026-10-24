package com.doubledimple.ociserver.config.security;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ClientIpResolverTest {
    private static final String CLIENT_IP = "203.0.113.80";
    private static final String LOCAL_PROXIES = "127.0.0.1/32,::1/128";

    @ParameterizedTest
    @ValueSource(strings = {"X-Forwarded-For", "X-Real-IP", "Proxy-Client-IP", "WL-Proxy-Client-IP",
            "HTTP_CLIENT_IP", "HTTP_X_FORWARDED_FOR", "Forwarded"})
    void publicDirectAccessIgnoresEveryClientSuppliedIpHeader(String header) {
        MockHttpServletRequest request = request(CLIENT_IP);
        request.addHeader(header, "127.0.0.1");

        assertEquals(CLIENT_IP, new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void emptyTrustConfigurationDoesNotImplicitlyTrustLoopback() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", CLIENT_IP);

        assertEquals("127.0.0.1", new ClientIpResolver("").resolve(request));
    }

    @Test
    void privateAddressesAreNotImplicitlyTrusted() {
        MockHttpServletRequest request = request("10.2.3.4");
        request.addHeader("X-Forwarded-For", "127.0.0.1");

        assertEquals("10.2.3.4", new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void nginxAppendedAddressWinsOverForgedLeftmostLoopback() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", "127.0.0.1, " + CLIENT_IP);
        request.addHeader("X-Real-IP", "192.0.2.99");

        assertEquals(CLIENT_IP, new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void walksOnlyTheTrustedSuffixOfAMultipleProxyChain() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", "192.0.2.99, " + CLIENT_IP + ", 10.3.4.5, 2001:db8:1::5");

        assertEquals(CLIENT_IP,
                new ClientIpResolver(LOCAL_PROXIES + ",10.3.4.0/24,2001:db8:1::/48").resolve(request));
    }

    @Test
    void untrustedIntermediateProxyTerminatesTheTrustChain() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", CLIENT_IP + ", 10.4.5.6, 10.3.4.5");

        assertEquals("10.4.5.6", new ClientIpResolver(LOCAL_PROXIES + ",10.3.4.5").resolve(request));
    }

    @Test
    void doesNotParseAttackerControlledTextBeforeTheFirstUntrustedHop() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", "garbage, unknown, , " + CLIENT_IP);

        assertEquals(CLIENT_IP, new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void repeatedHeaderLinesPreserveTheirOrder() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", "127.0.0.1");
        request.addHeader("X-Forwarded-For", CLIENT_IP + ", 10.3.4.5");

        assertEquals(CLIENT_IP, new ClientIpResolver(LOCAL_PROXIES + ",10.3.4.5").resolve(request));
    }

    @Test
    void malformedFinalHeaderLineCannotBeIgnoredInFavorOfAnEarlierLine() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", CLIENT_IP);
        request.addHeader("X-Forwarded-For", "unknown");

        assertEquals("unknown", new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "unknown", "localhost", "203.0.113.80, unknown",
            "203.0.113.80, 127.0.0.1:9856", "203.0.113.80, [::1]", "203.0.113.80,",
            "203.0.113.80, 999.0.0.1", "203.0.113.80, ::1%lo0"})
    void malformedOrMissingTrustedProxyHeadersCannotFallBackToTheProxyIp(String forwardedFor) {
        MockHttpServletRequest request = request("127.0.0.1");
        if (forwardedFor != null) request.addHeader("X-Forwarded-For", forwardedFor);
        request.addHeader("X-Real-IP", CLIENT_IP);
        request.addHeader("Proxy-Client-IP", CLIENT_IP);

        assertEquals("unknown", new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void chainContainingOnlyTrustedAddressesDoesNotIdentifyAClient() {
        MockHttpServletRequest request = request("127.0.0.1");
        request.addHeader("X-Forwarded-For", "::1, 127.0.0.1");

        assertEquals("unknown", new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void ipv4CidrMatchesOnlyAddressesInsideItsBitBoundary() {
        ClientIpResolver resolver = new ClientIpResolver("10.0.0.128/25");
        MockHttpServletRequest trusted = request("10.0.0.129");
        MockHttpServletRequest untrusted = request("10.0.0.127");
        trusted.addHeader("X-Forwarded-For", CLIENT_IP);
        untrusted.addHeader("X-Forwarded-For", "127.0.0.1");

        assertEquals(CLIENT_IP, resolver.resolve(trusted));
        assertEquals("10.0.0.127", resolver.resolve(untrusted));
    }

    @Test
    void ipv6CidrMatchesOnlyAddressesInsideItsBitBoundary() {
        ClientIpResolver resolver = new ClientIpResolver("2001:db8::/65");
        MockHttpServletRequest trusted = request("2001:db8:0:0:7fff::1");
        MockHttpServletRequest untrusted = request("2001:db8:0:0:8000::1");
        trusted.addHeader("X-Forwarded-For", CLIENT_IP);
        untrusted.addHeader("X-Forwarded-For", "127.0.0.1");

        assertEquals(CLIENT_IP, resolver.resolve(trusted));
        assertEquals("2001:db8::8000:0:0:1", resolver.resolve(untrusted));
    }

    @Test
    void expandedIpv6SocketAndForwardedAddressesAreCanonicalized() {
        ClientIpResolver resolver = new ClientIpResolver(LOCAL_PROXIES);
        MockHttpServletRequest proxied = request("0:0:0:0:0:0:0:1");
        proxied.addHeader("X-Forwarded-For", " 2001:0db8:0002:0000:0000:0000:0000:0012 ");

        assertEquals("2001:db8:2::12", resolver.resolve(proxied));
        assertEquals("2001:db8:2::12", resolver.resolve(request("2001:0db8:0002:0000:0000:0000:0000:0012")));
    }

    @Test
    void ipv4MappedIpv6ProxiesMatchTheirIpv4EquivalentWithoutBroadeningTheSubnet() {
        ClientIpResolver resolver = new ClientIpResolver("::ffff:127.0.0.1/128");
        MockHttpServletRequest ipv4Proxy = request("127.0.0.1");
        MockHttpServletRequest mappedProxy = request("::ffff:127.0.0.1");
        MockHttpServletRequest otherPeer = request("127.0.0.2");
        ipv4Proxy.addHeader("X-Forwarded-For", "::ffff:203.0.113.80");
        mappedProxy.addHeader("X-Forwarded-For", CLIENT_IP);
        otherPeer.addHeader("X-Forwarded-For", CLIENT_IP);

        assertEquals(CLIENT_IP, resolver.resolve(ipv4Proxy));
        assertEquals(CLIENT_IP, resolver.resolve(mappedProxy));
        assertEquals("127.0.0.2", resolver.resolve(otherPeer));
    }

    @Test
    void rejectsExcessiveHopCountsBeforeAttemptingToTrustTheLastAddress() {
        ClientIpResolver resolver = new ClientIpResolver(LOCAL_PROXIES);
        MockHttpServletRequest allowed = request("127.0.0.1");
        MockHttpServletRequest excessive = request("127.0.0.1");
        allowed.addHeader("X-Forwarded-For", String.join(",", Collections.nCopies(64, CLIENT_IP)));
        excessive.addHeader("X-Forwarded-For", String.join(",", Collections.nCopies(65, CLIENT_IP)));

        assertEquals(CLIENT_IP, resolver.resolve(allowed));
        assertEquals("unknown", resolver.resolve(excessive));
    }

    @Test
    void forwardingHeaderSizeLimitIncludesAllHeaderLines() {
        ClientIpResolver resolver = new ClientIpResolver(LOCAL_PROXIES);
        MockHttpServletRequest allowed = request("127.0.0.1");
        MockHttpServletRequest excessive = request("127.0.0.1");
        String prefix = String.join("", Collections.nCopies(8192 - CLIENT_IP.length() - 1, "x"));
        allowed.addHeader("X-Forwarded-For", prefix + "," + CLIENT_IP);
        excessive.addHeader("X-Forwarded-For", prefix);
        excessive.addHeader("X-Forwarded-For", "xx" + CLIENT_IP);

        assertEquals(CLIENT_IP, resolver.resolve(allowed));
        assertEquals("unknown", resolver.resolve(excessive));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"localhost", "unknown", "203.0.113.80:9856", "127.0.0.1,203.0.113.80"})
    void invalidSocketAddressCannotBeReplacedByAForwardingHeader(String peer) {
        MockHttpServletRequest request = request(peer);
        request.addHeader("X-Forwarded-For", CLIENT_IP);

        assertEquals("unknown", new ClientIpResolver(LOCAL_PROXIES).resolve(request));
    }

    @Test
    void absentRequestHasNoIdentifiableClient() {
        assertEquals("unknown", new ClientIpResolver(LOCAL_PROXIES).resolve(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {"localhost", "*.example.com", "127.0.0.1/33", "::1/129", "127.0.0.1/-1",
            "10.0.0.0/not-a-prefix", "10.0.0.0/24/1", "10.0.0.999/24", "[::1]", "::1%lo0",
            "0.0.0.0/0", "::/0", "::ffff:127.0.0.1/96", "::ffff:127.0.0.1/95"})
    void invalidProxyConfigurationFailsInsteadOfSilentlyWideningTrust(String configuration) {
        assertThrows(IllegalArgumentException.class, () -> new ClientIpResolver(configuration));
    }

    private static MockHttpServletRequest request(String peer) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr(peer);
        return request;
    }
}
