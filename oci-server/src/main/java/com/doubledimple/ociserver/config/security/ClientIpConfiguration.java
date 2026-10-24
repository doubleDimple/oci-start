package com.doubledimple.ociserver.config.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.web.ServerProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.util.StringUtils;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(ServerProperties.class)
public class ClientIpConfiguration {
    @Bean
    public ClientIpResolver clientIpResolver(
            @Value("${client-ip.trusted-proxies:}") String trustedProxies, ServerProperties serverProperties) {
        // Tomcat's valve runs before servlet filters and can erase the socket peer. In Boot 2.7,
        // explicitly setting either remoteip header also enables the valve even with strategy=none.
        ServerProperties.Tomcat.Remoteip remoteip = serverProperties.getTomcat().getRemoteip();
        if (serverProperties.getForwardHeadersStrategy() != ServerProperties.ForwardHeadersStrategy.NONE
                || StringUtils.hasText(remoteip.getRemoteIpHeader())
                || StringUtils.hasText(remoteip.getProtocolHeader())) {
            throw new IllegalStateException("Client IP security requires server.forward-headers-strategy=none"
                    + " and no server.tomcat.remoteip.remote-ip-header/protocol-header."
                    + " Configure client-ip.trusted-proxies instead.");
        }
        return new ClientIpResolver(trustedProxies);
    }

    @Bean
    public FilterRegistrationBean<ClientIpFilter> clientIpFilter(ClientIpResolver resolver) {
        FilterRegistrationBean<ClientIpFilter> registration = new FilterRegistrationBean<>(new ClientIpFilter(resolver));
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 5);
        registration.addUrlPatterns("/*");
        return registration;
    }
}
