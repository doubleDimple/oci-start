package com.doubledimple.ociserver.config.security;

import com.doubledimple.ocicommon.utils.IpUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/** Captures one security identity before application filters can wrap the request. */
public final class ClientIpFilter extends OncePerRequestFilter {
    private final ClientIpResolver resolver;

    public ClientIpFilter(ClientIpResolver resolver) {
        this.resolver = resolver;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        request.setAttribute(IpUtils.RESOLVED_CLIENT_IP_ATTRIBUTE, resolver.resolve(request));
        filterChain.doFilter(request, response);
    }
}
