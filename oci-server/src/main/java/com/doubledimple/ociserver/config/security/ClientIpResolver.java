package com.doubledimple.ociserver.config.security;

import com.google.common.net.InetAddresses;

import javax.servlet.http.HttpServletRequest;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;

/** Resolves only IP literals and only follows forwarding headers across explicitly trusted peers. */
public final class ClientIpResolver {
    private static final String UNKNOWN = "unknown";
    private static final int MAX_FORWARDED_LENGTH = 8192;
    private static final int MAX_FORWARDED_HOPS = 64;

    private final List<Subnet> trustedProxies;

    public ClientIpResolver(String trustedProxies) {
        List<Subnet> subnets = new ArrayList<>();
        if (trustedProxies != null && !trustedProxies.trim().isEmpty()) {
            for (String entry : trustedProxies.split(",", -1)) {
                subnets.add(Subnet.parse(entry.trim()));
            }
        }
        this.trustedProxies = Collections.unmodifiableList(subnets);
    }

    public String resolve(HttpServletRequest request) {
        InetAddress peer = request == null ? null : parseLiteral(request.getRemoteAddr());
        if (peer == null) {
            return UNKNOWN;
        }
        if (!isTrusted(peer)) {
            // Public and private peers alike must be explicitly trusted before any header is read.
            return InetAddresses.toAddrString(peer);
        }

        Enumeration<String> headers = request.getHeaders("X-Forwarded-For");
        List<String> hops = new ArrayList<>();
        int length = 0;
        while (headers != null && headers.hasMoreElements()) {
            String header = headers.nextElement();
            if (header == null || header.length() > MAX_FORWARDED_LENGTH - length) {
                return UNKNOWN;
            }
            length += header.length();
            String[] values = header.split(",", -1);
            if (values.length > MAX_FORWARDED_HOPS - hops.size()) {
                return UNKNOWN;
            }
            Collections.addAll(hops, values);
        }

        // The rightmost hop was supplied by our trusted peer. Stop at the first untrusted hop;
        // anything to its left could have been invented by that client, including malformed text.
        for (int i = hops.size() - 1; i >= 0; i--) {
            InetAddress hop = parseLiteral(hops.get(i));
            if (hop == null) {
                return UNKNOWN;
            }
            if (!isTrusted(hop)) {
                return InetAddresses.toAddrString(hop);
            }
        }
        // Missing/malformed forwarding data must not merge every visitor into the proxy's ban key.
        // No fallback to X-Real-IP or historical vendor headers: they may still be client supplied.
        return UNKNOWN;
    }

    private boolean isTrusted(InetAddress address) {
        for (Subnet subnet : trustedProxies) {
            if (subnet.contains(address)) {
                return true;
            }
        }
        return false;
    }

    private static InetAddress parseLiteral(String value) {
        if (value == null) {
            return null;
        }
        String literal = value.trim();
        // No zone IDs, brackets, ports, hostnames or DNS lookups in security decisions.
        if (literal.isEmpty() || literal.length() > 45 || literal.indexOf('%') >= 0) {
            return null;
        }
        try {
            return InetAddresses.forString(literal);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static final class Subnet {
        private final byte[] address;
        private final int prefix;

        private Subnet(byte[] address, int prefix) {
            this.address = address;
            this.prefix = prefix;
        }

        private static Subnet parse(String value) {
            String[] parts = value.split("/", -1);
            InetAddress ip = parseLiteral(parts[0]);
            if (parts.length > 2 || ip == null) {
                throw invalidConfiguration(value);
            }
            byte[] address = ip.getAddress();
            boolean mappedIpv4 = parts[0].contains(":") && address.length == 4;
            int bits = mappedIpv4 ? 128 : address.length * 8;
            int prefix = bits;
            if (parts.length == 2) {
                if (!parts[1].matches("[0-9]{1,3}")) {
                    throw invalidConfiguration(value);
                }
                prefix = Integer.parseInt(parts[1]);
            }
            if (prefix <= 0 || prefix > bits || (mappedIpv4 && prefix <= 96)) {
                throw invalidConfiguration(value);
            }
            // Guava canonicalizes IPv4-mapped IPv6 literals to four bytes.
            return new Subnet(address, mappedIpv4 ? prefix - 96 : prefix);
        }

        private boolean contains(InetAddress candidate) {
            byte[] other = candidate.getAddress();
            if (address.length != other.length) {
                return false;
            }
            int wholeBytes = prefix / 8;
            for (int i = 0; i < wholeBytes; i++) {
                if (address[i] != other[i]) {
                    return false;
                }
            }
            int remaining = prefix % 8;
            int mask = 0xff << (8 - remaining);
            return remaining == 0 || (address[wholeBytes] & mask) == (other[wholeBytes] & mask);
        }

        private static IllegalArgumentException invalidConfiguration(String value) {
            return new IllegalArgumentException("Invalid client-ip.trusted-proxies entry: " + value
                    + ". Use an explicit proxy IP or CIDR; trusting all addresses is not allowed.");
        }
    }
}
