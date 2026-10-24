package com.doubledimple.ociserver.config.security;

import com.doubledimple.ocicommon.utils.IpUtils;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.core.Ordered;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertEquals;

class ClientIpConfigurationTest {
    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withUserConfiguration(ClientIpConfiguration.class)
            .withPropertyValues("server.forward-headers-strategy=none");

    @Test
    void registeredFilterResolvesBothDirectAndLocalProxyRequestsWithTheSameConfiguration() {
        contextRunner.withPropertyValues("client-ip.trusted-proxies=127.0.0.1/32,::1/128").run(context -> {
            assertThat(context).hasNotFailed();
            FilterRegistrationBean<?> registration = context.getBean(FilterRegistrationBean.class);
            assertThat(registration.getOrder()).isLessThan(Ordered.HIGHEST_PRECEDENCE + 30);
            assertThat(registration.getUrlPatterns()).containsExactly("/*");

            MockHttpServletRequest direct = new MockHttpServletRequest();
            direct.setRemoteAddr("198.51.100.20");
            direct.addHeader("X-Forwarded-For", "127.0.0.1");
            registration.getFilter().doFilter(direct, new MockHttpServletResponse(), (request, response) ->
                    assertEquals("198.51.100.20", IpUtils.getClientIpAddress(direct)));

            MockHttpServletRequest proxied = new MockHttpServletRequest();
            proxied.setRemoteAddr("127.0.0.1");
            proxied.addHeader("X-Forwarded-For", "127.0.0.1, 198.51.100.20");
            registration.getFilter().doFilter(proxied, new MockHttpServletResponse(), (request, response) ->
                    assertEquals("198.51.100.20", IpUtils.getClientIpAddress(proxied)));
        });
    }

    @Test
    void absentTrustConfigurationDoesNotTrustEvenLoopbackOrPrivatePeers() {
        contextRunner.run(context -> {
            assertThat(context).hasNotFailed();
            ClientIpResolver resolver = context.getBean(ClientIpResolver.class);
            for (String peer : new String[]{"127.0.0.1", "10.0.0.2", "198.51.100.20"}) {
                MockHttpServletRequest request = new MockHttpServletRequest();
                request.setRemoteAddr(peer);
                request.addHeader("X-Forwarded-For", "192.0.2.99");
                assertEquals(peer, resolver.resolve(request));
            }
        });
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "server.forward-headers-strategy=native",
            "server.forward-headers-strategy=framework",
            "server.tomcat.remoteip.remote-ip-header=X-Forwarded-For",
            "server.tomcat.remoteip.protocol-header=X-Forwarded-Proto"
    })
    void refusesSettingsThatWouldRewriteSocketPeerBeforeTheFilter(String property) {
        contextRunner.withPropertyValues(property).run(context ->
                assertThat(context).hasFailed().getFailure()
                        .hasRootCauseInstanceOf(IllegalStateException.class)
                        .hasStackTraceContaining("Configure client-ip.trusted-proxies instead"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"localhost", "127.0.0.1/33", "0.0.0.0/0", "::/0"})
    void refusesInvalidTrustConfigurationAtStartup(String value) {
        contextRunner.withPropertyValues("client-ip.trusted-proxies=" + value).run(context ->
                assertThat(context).hasFailed().getFailure()
                        .hasRootCauseInstanceOf(IllegalArgumentException.class)
                        .hasStackTraceContaining("client-ip.trusted-proxies"));
    }
}
