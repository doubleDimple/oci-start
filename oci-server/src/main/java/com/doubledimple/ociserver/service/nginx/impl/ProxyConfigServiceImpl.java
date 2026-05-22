package com.doubledimple.ociserver.service.nginx.impl;

import com.doubledimple.dao.entity.ProxyConfig;
import com.doubledimple.dao.entity.SslCertificate;
import com.doubledimple.dao.repository.ProxyConfigRepository;
import com.doubledimple.dao.repository.SslCertificateRepository;
import com.doubledimple.ociserver.pojo.request.nginx.ProxyConfigCreateDto;
import com.doubledimple.ociserver.pojo.request.nginx.ProxyConfigUpdateDto;
import com.doubledimple.ociserver.pojo.request.nginx.SslCertificateRequestDto;
import com.doubledimple.ociserver.service.nginx.ProxyConfigService;
import com.doubledimple.ociserver.service.nginx.SslCertificateService;
import com.doubledimple.ociserver.third.dns.CloudflareService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.BeanUtils;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.DefaultResponseErrorHandler;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import java.net.URI;
import java.util.List;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName ProxyConfigServiceImpl
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-23 14:28
 */
@Slf4j
@Service
public class ProxyConfigServiceImpl implements ProxyConfigService {

    private static final RestTemplate TEST_REST_TEMPLATE;

    static {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5000);
        factory.setReadTimeout(5000);
        TEST_REST_TEMPLATE = new RestTemplate(factory);
        // 不要把 4xx/5xx 当异常抛——只要 TCP/HTTP 协议层有响应就算"通"
        TEST_REST_TEMPLATE.setErrorHandler(new DefaultResponseErrorHandler() {
            @Override public boolean hasError(org.springframework.http.client.ClientHttpResponse r) { return false; }
        });
    }

    @Resource
    private  ProxyConfigRepository proxyConfigRepository;

    @Resource
    private SslCertificateRepository sslCertificateRepository;

    @Resource
    @Lazy
    private SslCertificateService sslCertificateService;

    @Resource
    private CloudflareService cloudflareService;

    @Override
    @Transactional
    public ProxyConfig createProxyConfig(ProxyConfigCreateDto dto) {
        // 检查域名是否已存在
        if (proxyConfigRepository.existsByDomain(dto.getDomain())) {
            throw new RuntimeException("域名已存在: " + dto.getDomain());
        }

        ProxyConfig config = new ProxyConfig();
        BeanUtils.copyProperties(dto, config);
        // SSL状态默认未配置，通过applySslConfig接口申请后才会更新
        config.setSslStatus(ProxyConfig.SslStatus.NOT_CONFIGURED);
        config = proxyConfigRepository.save(config);

        // DNS 写入是外部副作用，放在事务提交后单独做：
        // 失败也不要回滚 ProxyConfig 持久化，避免一边 DB 没记录、一边 Cloudflare 已经留下半截 DNS 记录的脏状态
        if (StringUtils.isNotBlank(dto.getDomain()) && cloudflareService.isCloudflareConfigValid()) {
            try {
                cloudflareService.createSimpleARecord(dto.getDomain());
            } catch (Exception e) {
                log.warn("创建 Cloudflare A 记录失败,domain={}, reason={}（ProxyConfig 已保存,可在 DNS 管理页手动补建）",
                        dto.getDomain(), e.getMessage());
            }
        }
        return config;
    }

    @Override
    @Transactional
    public ProxyConfig updateProxyConfig(ProxyConfigUpdateDto dto) {
        ProxyConfig config = getProxyConfigById(dto.getId());

        // 检查域名是否被其他配置使用
        boolean domainChanged = !config.getDomain().equals(dto.getDomain());
        if (domainChanged && proxyConfigRepository.existsByDomain(dto.getDomain())) {
            throw new RuntimeException("域名已存在: " + dto.getDomain());
        }

        BeanUtils.copyProperties(dto, config, "id", "createTime", "sslCertificateId", "sslStatus");
        config.setConfigStatus(ProxyConfig.ConfigStatus.PENDING);

        // 域名换了之后,旧证书已经不再适用,必须强制重置 SSL 关联,
        // 否则 generateServerBlock 会拿旧证书路径配新域名 → 握手失败
        if (domainChanged) {
            config.setSslCertificateId(null);
            config.setEnableSsl(false);
            config.setSslStatus(ProxyConfig.SslStatus.NOT_CONFIGURED);
        }

        return proxyConfigRepository.save(config);
    }

    @Override
    @Transactional
    public void deleteProxyConfig(Long id) {
        ProxyConfig config = getProxyConfigById(id);
        proxyConfigRepository.delete(config);
        log.info("删除反向代理配置: {}", config.getDomain());
    }

    @Override
    public Page<ProxyConfig> getProxyConfigs(Pageable pageable) {
        return proxyConfigRepository.findAll(pageable);
    }

    @Override
    public ProxyConfig getProxyConfigById(Long id) {
        return proxyConfigRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("配置不存在: " + id));
    }

    @Override
    @Transactional
    public void applySslConfig(Long proxyId, String email) {
        ProxyConfig config = getProxyConfigById(proxyId);

        // 创建SSL证书申请
        SslCertificateRequestDto certDto = new SslCertificateRequestDto();
        certDto.setDomain(config.getDomain());
        certDto.setEmail(email);
        certDto.setAutoRenew(true);

        try {
            SslCertificate cert = sslCertificateService.requestCertificate(certDto);
            // 关键：必须把证书 id 写回 ProxyConfig，否则 generateServerBlock 会因为
            // sslCertificateId == null 抛"已启用SSL但未关联证书"
            config.setSslCertificateId(cert.getId());
            config.setSslStatus(ProxyConfig.SslStatus.PENDING);
            config.setEnableSsl(true);
            proxyConfigRepository.save(config);
        } catch (Exception e) {
            config.setSslStatus(ProxyConfig.SslStatus.ERROR);
            proxyConfigRepository.save(config);
            throw new RuntimeException("SSL配置失败: " + e.getMessage());
        }
    }

    @Override
    @Transactional
    public void syncProxySslStatusByCertificate(Long sslCertificateId) {
        if (sslCertificateId == null) return;
        Optional<SslCertificate> opt = sslCertificateRepository.findById(sslCertificateId);
        if (!opt.isPresent()) return;
        SslCertificate cert = opt.get();

        ProxyConfig.SslStatus target;
        switch (cert.getStatus()) {
            case VALID:
            case EXPIRING_SOON:
                target = ProxyConfig.SslStatus.CONFIGURED;
                break;
            case ERROR:
            case EXPIRED:
                target = ProxyConfig.SslStatus.ERROR;
                break;
            case PENDING:
            default:
                target = ProxyConfig.SslStatus.PENDING;
                break;
        }
        List<ProxyConfig> proxies = proxyConfigRepository.findBySslCertificateId(sslCertificateId);
        for (ProxyConfig p : proxies) {
            if (p.getSslStatus() != target) {
                p.setSslStatus(target);
                proxyConfigRepository.save(p);
                log.info("同步 ProxyConfig SSL 状态: domain={}, certId={}, -> {}",
                        p.getDomain(), sslCertificateId, target);
            }
        }
    }

    @Override
    @Transactional
    public void fixProxyConfig(Long id) {
        ProxyConfig config = getProxyConfigById(id);
        config.setConfigStatus(ProxyConfig.ConfigStatus.PENDING);
        proxyConfigRepository.save(config);
        log.info("修复代理配置: {}", config.getDomain());
    }

    @Override
    public List<ProxyConfig> getAllActiveConfigs() {
        return proxyConfigRepository.findByConfigStatusNot(ProxyConfig.ConfigStatus.DISABLED);
    }

    @Override
    @Transactional
    public void toggleProxyConfig(Long id, Boolean enabled) {
        ProxyConfig config = getProxyConfigById(id);
        if (enabled) {
            config.setConfigStatus(ProxyConfig.ConfigStatus.PENDING);
        } else {
            config.setConfigStatus(ProxyConfig.ConfigStatus.DISABLED);
        }
        proxyConfigRepository.save(config);
        log.info("切换代理配置状态: {} - {}", config.getDomain(), enabled ? "启用" : "禁用");
    }

    @Override
    public boolean testConnection(Long id) {
        ProxyConfig config = getProxyConfigById(id);
        // 直接做 TCP 层连接性探测：能 connect 上就算"通"
        // 只走 HTTP GET / 在大量 API 后端会因为 4xx/5xx 误判（已通过 ResponseErrorHandler 解决），
        // 这里再加一次 TCP 兜底，更稳。
        try {
            URI uri = URI.create(config.getProtocol() + "://" + config.getTargetHost() + ":" + config.getTargetPort());
            try (java.net.Socket sock = new java.net.Socket()) {
                sock.connect(new java.net.InetSocketAddress(uri.getHost(), uri.getPort()), 5000);
                return true;
            }
        } catch (Exception tcpFail) {
            log.warn("TCP 连接失败,domain={}, target={}:{}, reason:{}",
                    config.getDomain(), config.getTargetHost(), config.getTargetPort(), tcpFail.getMessage());
            return false;
        }
    }
}
