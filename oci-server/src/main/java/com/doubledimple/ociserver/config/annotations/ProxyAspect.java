package com.doubledimple.ociserver.config.annotations;

import com.doubledimple.dao.entity.VpnProxyRecord;
import com.doubledimple.dao.repository.VpnProxyRecordRepository;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.utils.SocksProxyUtils;
import com.oracle.bmc.http.ClientConfigurator;
import com.oracle.bmc.http.client.jersey.JerseyClientProperty;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.glassfish.jersey.client.ClientProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.net.URI;
import java.net.URISyntaxException;

/**
 * @version 1.0.0
 * @ClassName SocksProxyAspect
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-01 11:50
 */
@Slf4j
@Aspect
@Component
public class ProxyAspect {

    @Autowired
    private SystemConfigService systemConfigService;

    @Resource
    VpnProxyRecordRepository vpnProxyRecordRepository;

    @Around("@annotation(useSocksProxy)")
    public Object around(ProceedingJoinPoint joinPoint, UseSocksProxy useSocksProxy) throws Throwable {

        VpnProxyRecord proxyConfig = vpnProxyRecordRepository.findRandomAvailableRecord(1);
        if (null == proxyConfig){
            log.debug("未获取到可用的 VPN 代理，使用直连");
            return joinPoint.proceed();
        }
        boolean proxyApplied = false;
        try {
            if (proxyConfig.getAvailableStatus() == 1) {
                boolean available = SocksProxyUtils.isProxyAvailable(proxyConfig);
                if (available) {
                    applyProxy(proxyConfig);
                    proxyApplied = true;
                    log.info("代理启用成功：{}:{} [{}]", proxyConfig.getProxyHost(), proxyConfig.getProxyPort(), proxyConfig.getProxyType());
                } else {
                    log.warn("代理不可用：{}:{}，跳过代理", proxyConfig.getProxyHost(), proxyConfig.getProxyPort());
                }
            } else {
                log.debug("代理已禁用，走直连");
            }
            return joinPoint.proceed();
        } finally {
            if (proxyApplied) {
                clearProxy();
                log.debug("代理配置已清理");
            }
        }
    }

    private void clearProxy() {
        ClientConfigurator clientConfigurator = ProxyContext.get();
        if (clientConfigurator != null){
            ProxyContext.clear();
        }
    }

    private void applyProxy(VpnProxyRecord proxyConfig) {
        try {
            String host = proxyConfig.getProxyHost();
            int port = proxyConfig.getProxyPort();
            String proxyUsername = proxyConfig.getProxyUsername();
            String proxyPassword = proxyConfig.getProxyPassword();
            String proxyType = proxyConfig.getProxyType().toLowerCase();
            URI proxyUri = new URI(proxyType, null, host, port, null, null, null);
            String url = proxyUri.toString(); // http://127.0.0.1:10809
            ClientConfigurator proxyConfigurator = clientBuilder -> {
                clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_URI), url);
                if (proxyUsername != null && proxyPassword != null){
                    clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_USERNAME), proxyUsername);
                    clientBuilder.property(JerseyClientProperty.create(ClientProperties.PROXY_PASSWORD), proxyPassword);
                }
            };
            ProxyContext.set(proxyConfigurator);
        } catch (URISyntaxException e) {
            log.warn("代理配置错误：{}", e.getMessage());
        }
    }
}
