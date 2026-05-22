package com.doubledimple.ociserver.service.nginx.impl;

import com.doubledimple.dao.entity.SslCertificate;
import com.doubledimple.dao.repository.ProxyConfigRepository;
import com.doubledimple.dao.repository.SslCertificateRepository;
import com.doubledimple.ociserver.pojo.request.nginx.CertificateDTO;
import com.doubledimple.ociserver.pojo.request.nginx.SslCertificateRequestDto;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.nginx.NginxConfigService;
import com.doubledimple.ociserver.service.nginx.ProxyConfigService;
import com.doubledimple.ociserver.service.nginx.SslCertificateService;
import com.doubledimple.ociserver.third.dns.CloudflareService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.shredzone.acme4j.*;
import org.shredzone.acme4j.challenge.Dns01Challenge;
import org.shredzone.acme4j.exception.AcmeException;
import org.shredzone.acme4j.util.CSRBuilder;
import org.shredzone.acme4j.util.KeyPairUtils;
import org.springframework.beans.BeanUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;
import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.KeyPair;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/**
 * SSL证书服务实现类 - 使用ACME4J和CloudflareService
 */
@Slf4j
@Service
public class SslCertificateServiceImpl implements SslCertificateService {

    @Resource
    SslCertificateRepository sslCertificateRepository;

    @Resource
    private ProxyConfigRepository proxyConfigRepository;

    @Resource
    @Lazy
    private ProxyConfigService proxyConfigService;

    @Resource
    private CloudflareService cloudflareService;

    @Resource
    @Lazy
    NginxConfigService nginxConfigService;

    @Value("${baseFile.filePath}")
    private String basePath;

    @Value("${ssl.staging:false}")
    private boolean useStaging;

    private String certPath = "cert";

    /**
     * 旧版本是 JVM 全局 AtomicBoolean —— 申请一张证书会卡住所有人最长 16 分钟。
     * 改成按 domain 加锁,不同域名互不干扰。
     */
    private final ConcurrentHashMap<String, ReentrantLock> domainLocks = new ConcurrentHashMap<>();

    private ReentrantLock lockForDomain(String domain) {
        return domainLocks.computeIfAbsent(domain, k -> new ReentrantLock());
    }

    // Let's Encrypt URLs
    private static final String LETS_ENCRYPT_URL = "acme://letsencrypt.org";
    private static final String LETS_ENCRYPT_STAGING_URL = "acme://letsencrypt.org/staging";

    @PostConstruct
    public void init() {
        // 确保证书存储目录存在
        String fullCertPath = basePath+ certPath;
        File certDir = new File(fullCertPath);
        if (!certDir.exists()) {
            boolean created = certDir.mkdirs();
            if (!created) {
                log.warn("无法创建证书存储目录: {}", fullCertPath);
            }
        }

        log.debug("ACME4J SSL证书服务初始化完成，证书存储路径: {}, 环境: {}",
                fullCertPath, useStaging ? "Staging" : "Production");
    }

    @Override
    @Transactional
    public SslCertificate requestCertificate(SslCertificateRequestDto dto) {
        // 检查现有证书
        Optional<SslCertificate> existingCert = sslCertificateRepository.findByDomain(dto.getDomain());
        if (existingCert.isPresent() && existingCert.get().getStatus() == SslCertificate.CertificateStatus.VALID) {
            log.info("域名已有有效证书，直接返回: {}", dto.getDomain());
            return existingCert.get();
        }
        if (existingCert.isPresent() && existingCert.get().getStatus() == SslCertificate.CertificateStatus.PENDING) {
            log.info("域名已有正在申请中的证书,复用记录: {}", dto.getDomain());
            return existingCert.get();
        }

        // 按 domain 加锁,不再 JVM 全局串行
        ReentrantLock lock = lockForDomain(dto.getDomain());
        if (!lock.tryLock()) {
            throw new RuntimeException("该域名正在申请证书,请稍候再试: " + dto.getDomain());
        }
        try {
            return doRequestCertificate(dto, existingCert.orElse(null));
        } finally {
            lock.unlock();
        }
    }

    private SslCertificate doRequestCertificate(SslCertificateRequestDto dto, SslCertificate existingCertOrNull) {

        // 只支持Let's Encrypt证书
        if (!"LETS_ENCRYPT".equals(dto.getCertificateType())) {
            throw new RuntimeException("只支持Let's Encrypt证书申请");
        }

        // 验证DNS服务商配置
        String dnsProvider = dto.getDnsProvider() != null ? dto.getDnsProvider() : "cf";
        validateDnsProviderConfig(dnsProvider);

        // 创建证书记录
        SslCertificate certificate = new SslCertificate();
        BeanUtils.copyProperties(dto, certificate);
        certificate.setStatus(SslCertificate.CertificateStatus.PENDING);
        certificate.setCertificateType(SslCertificate.CertificateType.LETS_ENCRYPT);

        // 设置DNS服务商
        try {
            certificate.setDnsProvider(SslCertificate.DnsProvider.valueOf(dnsProvider.toUpperCase()));
        } catch (IllegalArgumentException e) {
            certificate.setDnsProvider(SslCertificate.DnsProvider.CLOUDFLARE);
        }

        certificate.setAutoRenew(true);
        certificate = sslCertificateRepository.save(certificate);

        // 异步申请证书
        processAcme4jRequestAsync(certificate);

        return certificate;
    }

    /**
     * 验证DNS服务商配置
     */
    private void validateDnsProviderConfig(String dnsProvider) {
        switch (dnsProvider.toLowerCase()) {
            case "cf":
            case "cloudflare":
                if (!cloudflareService.isCloudflareConfigValid()) {
                    throw new RuntimeException("Cloudflare配置无效或未启用，请检查API Token和邮箱配置");
                }
                break;
            default:
                throw new RuntimeException("不支持的DNS服务商: " + dnsProvider + "，目前仅支持Cloudflare");
        }
    }

    /**
     * 异步处理证书申请。整个流程最长 ~20 分钟,因此用 domain 锁,不要拿 JVM 全局锁。
     */
    @Async
    public CompletableFuture<Void> processAcme4jRequestAsync(SslCertificate certificate) {
        ReentrantLock lock = lockForDomain(certificate.getDomain());
        if (!lock.tryLock()) {
            log.warn("证书申请已在进行中,跳过: {}", certificate.getDomain());
            return CompletableFuture.completedFuture(null);
        }
        try {
            log.info("开始ACME4J证书申请流程: {}", certificate.getDomain());

            requestCertificateWithAcme4j(certificate);

            // 更新证书状态为成功，从证书文件中读取真实过期时间
            certificate.setStatus(SslCertificate.CertificateStatus.VALID);
            certificate.setIssueDate(LocalDateTime.now());
            certificate.setExpireDate(readCertificateExpiry(certificate.getCertificatePath()));
            sslCertificateRepository.save(certificate);
            log.info("ACME4J证书申请成功: {}", certificate.getDomain());

            log.info("上传证书到OpenResty: {}", certificate.getDomain());
            ApiResponse apiResponse = nginxConfigService.uploadSslCertificateToOpenResty(certificate);
            if (!apiResponse.isSuccess()){
                log.error("上传证书到OpenResty失败: {}", certificate.getDomain());
            }
        } catch (Exception e) {
            log.error("ACME4J证书申请失败: {}", certificate.getDomain(), e);
            certificate.setStatus(SslCertificate.CertificateStatus.ERROR);
            sslCertificateRepository.save(certificate);
        } finally {
            // 关键：异步申请结束(不论成败)都同步一次 ProxyConfig 的 sslStatus,
            // 让 UI 上"配置中"能转成"已配置/失败",而不是永远卡 PENDING
            try {
                proxyConfigService.syncProxySslStatusByCertificate(certificate.getId());
            } catch (Exception ignore) { log.warn("同步 ProxyConfig SSL 状态失败: {}", ignore.getMessage()); }
            lock.unlock();
        }
        return CompletableFuture.completedFuture(null);
    }

    @Override
    public void onCertificateStatusChanged(Long certificateId) {
        // 任何写完 SslCertificate.status 的地方,都可以调一下让 ProxyConfig 同步
        proxyConfigService.syncProxySslStatusByCertificate(certificateId);
    }

    /**
     * 使用ACME4J申请证书的核心逻辑
     */
    private void requestCertificateWithAcme4j(SslCertificate certificate) throws Exception {
        String domain = certificate.getDomain();
        String email = certificate.getEmail();

        log.info("创建ACME会话: {}", useStaging ? "Staging" : "Production");

        // 1. 创建ACME会话
        Session session = new Session(useStaging ? LETS_ENCRYPT_STAGING_URL : LETS_ENCRYPT_URL);

        // 2. 生成或加载账户密钥对
        KeyPair accountKeyPair = loadOrGenerateAccountKeyPair();

        // 3. 创建或登录账户
        Account account = createOrLoginAccount(session, accountKeyPair, email);
        log.info("账户创建/登录成功");

        // 4. 创建证书订单
        log.info("创建证书订单: {}", domain);
        Order order = account.newOrder().domain(domain).create();

        // 5. 处理DNS挑战
        for (Authorization auth : order.getAuthorizations()) {
            log.info("处理域名授权: {}", auth.getIdentifier().getDomain());
            processDnsChallenge(auth, certificate.getDnsProvider().toString().toLowerCase());
        }

        // 6. 生成域名密钥对和CSR
        log.info("生成域名密钥对");
        KeyPair domainKeyPair = KeyPairUtils.createKeyPair(2048);
        CSRBuilder csrBuilder = new CSRBuilder();
        csrBuilder.addDomain(domain);
        csrBuilder.sign(domainKeyPair);

        // 7. 提交CSR并等待证书生成
        log.info("提交CSR并等待证书生成");
        order.execute(csrBuilder.getEncoded());

        // 8. 等待订单完成
        waitForOrderCompletion(order);

        // 9. 下载并保存证书
        log.info("下载证书");
        Certificate acmeCertificate = order.getCertificate();
        saveCertificateFiles(certificate, acmeCertificate, domainKeyPair);

        log.info("证书保存完成: {}", domain);
    }

    /**
     * 加载或生成账户密钥对
     */
    private KeyPair loadOrGenerateAccountKeyPair() throws Exception {
        String accountKeyPath = basePath + "account.key";
        File keyFile = new File(accountKeyPath);

        if (keyFile.exists()) {
            log.info("加载现有账户密钥");
            try (FileReader fr = new FileReader(keyFile)) {
                return KeyPairUtils.readKeyPair(fr);
            }
        } else {
            log.info("生成新的账户密钥对");
            KeyPair keyPair = KeyPairUtils.createKeyPair(2048);

            // 保存密钥对
            try (FileWriter fw = new FileWriter(keyFile)) {
                KeyPairUtils.writeKeyPair(keyPair, fw);
            }

            return keyPair;
        }
    }

    /**
     * 创建或登录账户
     */
    private Account createOrLoginAccount(Session session, KeyPair accountKeyPair, String email) throws Exception {
        try {
            // 尝试使用现有密钥登录账户
            return new AccountBuilder()
                    .useKeyPair(accountKeyPair)
                    .onlyExisting()  // 只查找现有账户
                    .create(session);
        } catch (AcmeException e) {
            // 如果账户不存在，创建新账户
            log.info("账户不存在，创建新的Let's Encrypt账户");
            AccountBuilder accountBuilder = new AccountBuilder()
                    .useKeyPair(accountKeyPair)
                    .agreeToTermsOfService();

            if (email != null && !email.trim().isEmpty()) {
                accountBuilder.addContact("mailto:" + email.trim());
            }

            return accountBuilder.create(session);
        }
    }

    /**
     * 处理DNS挑战
     */
    private void processDnsChallenge(Authorization auth, String dnsProvider) throws Exception {
        Dns01Challenge challenge = auth.findChallenge(Dns01Challenge.TYPE);
        if (challenge == null) {
            throw new AcmeException("找不到DNS挑战");
        }

        String domain = auth.getIdentifier().getDomain();
        String recordName = "_acme-challenge." + domain;
        String recordValue = challenge.getDigest();

        log.info("添加DNS TXT记录: {} = {} (Provider: {})", recordName, recordValue, dnsProvider);

        String recordId = null;
        try {
            // 添加DNS记录
            recordId = addDnsRecord(dnsProvider, domain, recordName, recordValue);

            // 等待DNS传播
            log.info("等待DNS记录传播...");
            waitForDnsPropagation(recordName, recordValue);

            // 触发挑战验证
            log.info("触发ACME挑战验证");
            challenge.trigger();

            // 等待验证完成
            waitForChallengeCompletion(challenge);
            log.info("DNS挑战验证成功");

        } finally {
            // 清理DNS记录
            if (recordId != null) {
                try {
                    removeDnsRecord(dnsProvider, domain, recordId);
                    log.info("清理DNS记录完成");
                } catch (Exception e) {
                    log.warn("清理DNS记录失败: {}", e.getMessage());
                }
            }
        }
    }

    /**
     * 添加DNS记录
     */
    private String addDnsRecord(String dnsProvider, String domain, String recordName, String recordValue) throws Exception {
        switch (dnsProvider.toLowerCase()) {
            case "cf":
            case "cloudflare":
                return cloudflareService.addAcmeTxtRecord(domain, recordName, recordValue);
            default:
                throw new RuntimeException("不支持的DNS服务商: " + dnsProvider);
        }
    }

    /**
     * 删除DNS记录
     */
    private void removeDnsRecord(String dnsProvider, String domain, String recordId) throws Exception {
        switch (dnsProvider.toLowerCase()) {
            case "cf":
            case "cloudflare":
                cloudflareService.removeAcmeTxtRecord(domain, recordId);
                break;
            default:
                log.warn("不支持的DNS服务商清理: {}", dnsProvider);
        }
    }

    /**
     * 等待DNS传播。改用 JDK 自带 JNDI 直接查 8.8.8.8 / 1.1.1.1 的 TXT 记录,
     * 不再依赖本机 nslookup 命令(容器/精简镜像里可能没有)。
     */
    private void waitForDnsPropagation(String recordName, String expectedValue) throws Exception {
        int maxAttempts = 24;
        int attemptInterval = 15000;
        // 直接查权威外部 resolver,绕过本机 DNS 缓存
        String[] resolvers = {"dns://8.8.8.8", "dns://1.1.1.1"};

        for (int i = 0; i < maxAttempts; i++) {
            for (String resolver : resolvers) {
                try {
                    java.util.Hashtable<String, String> env = new java.util.Hashtable<>();
                    env.put(javax.naming.Context.INITIAL_CONTEXT_FACTORY, "com.sun.jndi.dns.DnsContextFactory");
                    env.put(javax.naming.Context.PROVIDER_URL, resolver);
                    env.put("com.sun.jndi.dns.timeout.initial", "3000");
                    env.put("com.sun.jndi.dns.timeout.retries", "2");

                    javax.naming.directory.DirContext ctx = new javax.naming.directory.InitialDirContext(env);
                    try {
                        javax.naming.directory.Attributes attrs = ctx.getAttributes(recordName, new String[]{"TXT"});
                        javax.naming.directory.Attribute txt = attrs.get("TXT");
                        if (txt != null) {
                            for (int k = 0; k < txt.size(); k++) {
                                String value = String.valueOf(txt.get(k)).replace("\"", "").trim();
                                if (value.contains(expectedValue)) {
                                    log.info("DNS记录传播完成 (resolver={})", resolver);
                                    return;
                                }
                            }
                        }
                    } finally {
                        try { ctx.close(); } catch (Exception ignore) {}
                    }
                } catch (Exception e) {
                    log.debug("DNS检查失败 resolver={}, reason:{}", resolver, e.getMessage());
                }
            }

            if (i < maxAttempts - 1) {
                log.info("等待DNS传播... ({}/{})", i + 1, maxAttempts);
                Thread.sleep(attemptInterval);
            }
        }

        log.warn("DNS传播检查超时,继续证书申请流程(可能因传播延迟导致首次验证失败)");
    }

    /**
     * 等待挑战完成
     */
    private void waitForChallengeCompletion(Dns01Challenge challenge) throws Exception {
        int maxAttempts = 30; // 5分钟超时

        for (int i = 0; i < maxAttempts; i++) {
            challenge.update();

            if (challenge.getStatus() == Status.VALID) {
                return;
            } else if (challenge.getStatus() == Status.INVALID) {
                throw new AcmeException("DNS挑战验证失败: " + challenge.getError());
            }

            Thread.sleep(10000); // 等待10秒
            log.info("等待挑战验证... ({}/{})", i + 1, maxAttempts);
        }

        throw new AcmeException("DNS挑战验证超时");
    }

    /**
     * 等待订单完成
     */
    private void waitForOrderCompletion(Order order) throws Exception {
        int maxAttempts = 30;

        for (int i = 0; i < maxAttempts; i++) {
            order.update();

            if (order.getStatus() == Status.VALID) {
                log.info("证书订单完成");
                return;
            } else if (order.getStatus() == Status.INVALID) {
                throw new AcmeException("证书订单失败");
            }

            Thread.sleep(10000);
            log.info("等待证书生成... ({}/{})", i + 1, maxAttempts);
        }

        throw new AcmeException("证书生成超时");
    }

    /**
     * 保存证书文件
     */
    private void saveCertificateFiles(SslCertificate certificate, Certificate acmeCertificate, KeyPair domainKeyPair) throws Exception {
        String domain = certificate.getDomain();
        String destDir = basePath + certPath + "/" + domain;
        File domainDir = new File(destDir);
        if (!domainDir.exists()) {
            domainDir.mkdirs();
        }

        // 保存证书文件（包含完整证书链）
        Path certFile = Paths.get(destDir, "fullchain.pem");
        try (FileWriter fw = new FileWriter(certFile.toFile())) {
            acmeCertificate.writeCertificate(fw);
        }

        // 保存私钥文件
        Path keyFile = Paths.get(destDir, "privkey.pem");
        try (FileWriter fw = new FileWriter(keyFile.toFile())) {
            KeyPairUtils.writeKeyPair(domainKeyPair, fw);
        }

        // 更新数据库记录
        certificate.setCertificatePath(certFile.toString());
        certificate.setPrivateKeyPath(keyFile.toString());

        log.info("证书文件保存成功: {}", destDir);
    }

    @Override
    @Transactional
    public void renewCertificate(Long certificateId) {
        SslCertificate certificate = sslCertificateRepository.findById(certificateId)
                .orElseThrow(() -> new RuntimeException("证书不存在: " + certificateId));

        // 只支持Let's Encrypt证书续期
        if (certificate.getCertificateType() != SslCertificate.CertificateType.LETS_ENCRYPT) {
            throw new RuntimeException("只支持Let's Encrypt证书续期");
        }

        // 同 domain 锁占用就拒绝,不再卡 JVM 全局
        if (lockForDomain(certificate.getDomain()).isLocked()) {
            throw new RuntimeException("该域名证书正在申请/续期中,请稍候: " + certificate.getDomain());
        }

        certificate.setStatus(SslCertificate.CertificateStatus.PENDING);
        sslCertificateRepository.save(certificate);

        // 异步处理续期 - 续期实际上就是重新申请
        processAcme4jRequestAsync(certificate);

        log.info("开始Let's Encrypt证书续期: {}", certificate.getDomain());
    }

    @Override
    @Transactional
    public void deleteCertificate(Long certificateId) {
        SslCertificate certificate = sslCertificateRepository.findById(certificateId)
                .orElseThrow(() -> new RuntimeException("证书不存在: " + certificateId));

        // 引用检查:不允许删掉正在被 ProxyConfig 引用的证书,
        // 否则下次 generateNginxConfig 会因为找不到证书直接抛错
        if (proxyConfigRepository.existsBySslCertificateId(certificateId)) {
            List<com.doubledimple.dao.entity.ProxyConfig> refs = proxyConfigRepository.findBySslCertificateId(certificateId);
            String domains = refs.stream().map(com.doubledimple.dao.entity.ProxyConfig::getDomain)
                    .reduce((a, b) -> a + ", " + b).orElse("");
            throw new RuntimeException("证书正在被反向代理使用,请先解除关联或停用代理: " + domains);
        }

        // 如果是Let's Encrypt证书且状态有效，先撤销证书
        if (certificate.getCertificateType() == SslCertificate.CertificateType.LETS_ENCRYPT
                && certificate.getStatus() == SslCertificate.CertificateStatus.VALID) {
            try {
                revokeCertificateWithAcme4j(certificate);
                log.info("Let's Encrypt证书撤销成功: {}", certificate.getDomain());
            } catch (Exception e) {
                log.warn("Let's Encrypt证书撤销失败，继续删除本地文件: {} - {}",
                        certificate.getDomain(), e.getMessage());
            }
        }

        // 删除证书文件
        try {
            String certDir = basePath+ certPath + "/" + certificate.getDomain();
            File domainDir = new File(certDir);
            if (domainDir.exists() && domainDir.isDirectory()) {
                deleteDirectory(domainDir);
                log.info("删除证书目录: {}", certDir);
            }
        } catch (Exception e) {
            log.warn("删除证书文件失败: {}", e.getMessage());
        }

        // 删除数据库记录
        sslCertificateRepository.delete(certificate);
        log.info("删除证书记录: {}", certificate.getDomain());
    }

    /**
     * 使用ACME4J撤销证书
     */
    private void revokeCertificateWithAcme4j(SslCertificate certificate) throws Exception {
        String domain = certificate.getDomain();
        String certFilePath = certificate.getCertificatePath();

        // 检查证书文件是否存在
        if (certFilePath == null || !new File(certFilePath).exists()) {
            throw new RuntimeException("证书文件不存在，无法撤销: " + certFilePath);
        }

        log.info("使用ACME4J撤销证书: {}", domain);

        try {
            // 创建ACME会话
            Session session = new Session(useStaging ? LETS_ENCRYPT_STAGING_URL : LETS_ENCRYPT_URL);

            // 加载账户密钥对
            KeyPair accountKeyPair = loadOrGenerateAccountKeyPair();

            // 登录账户获取Account URL
            Account account = new AccountBuilder()
                    .useKeyPair(accountKeyPair)
                    .onlyExisting()
                    .create(session);

            // 读取证书文件并解析为X509Certificate
            X509Certificate mainCert = readCertificateFromPem(certFilePath);

            // 创建Login对象
            Login login = new Login(account.getLocation(), accountKeyPair, session);

            // 使用静态方法撤销证书
            Certificate.revoke(login, mainCert, RevocationReason.UNSPECIFIED);

            log.info("ACME4J证书撤销成功: {}", domain);

        } catch (Exception e) {
            log.error("ACME4J证书撤销失败: {} - {}", domain, e.getMessage());
            throw new RuntimeException("证书撤销失败: " + e.getMessage());
        }
    }

    /**
     * 从PEM文件读取X509证书
     */
    private X509Certificate readCertificateFromPem(String certPath) throws Exception {
        try (FileInputStream fis = new FileInputStream(certPath)) {
            CertificateFactory cf = CertificateFactory.getInstance("X.509");
            return (X509Certificate) cf.generateCertificate(fis);
        }
    }

    /**
     * 从证书文件读取实际过期时间，读取失败时回退到90天
     */
    private LocalDateTime readCertificateExpiry(String certFilePath) {
        if (certFilePath == null) {
            return LocalDateTime.now().plusDays(90);
        }
        try {
            X509Certificate x509 = readCertificateFromPem(certFilePath);
            return x509.getNotAfter().toInstant()
                    .atZone(java.time.ZoneId.systemDefault())
                    .toLocalDateTime();
        } catch (Exception e) {
            log.warn("读取证书过期时间失败，使用默认90天: {}", e.getMessage());
            return LocalDateTime.now().plusDays(90);
        }
    }

    @Override
    @Transactional
    public void toggleAutoRenew(Long certificateId, Boolean enabled) {
        SslCertificate certificate = sslCertificateRepository.findById(certificateId)
                .orElseThrow(() -> new RuntimeException("证书不存在: " + certificateId));

        certificate.setAutoRenew(enabled);
        sslCertificateRepository.save(certificate);

        log.info("切换自动续期状态: {} -> {}", certificate.getDomain(), enabled);
    }

    @Override
    public Page<SslCertificate> getCertificates(Pageable pageable) {
        return sslCertificateRepository.findAll(pageable);
    }

    @Override
    public List<SslCertificate> checkExpiringCertificates() {
        LocalDateTime thirtyDaysFromNow = LocalDateTime.now().plusDays(30);
        return sslCertificateRepository.findExpiringCertificates(thirtyDaysFromNow);
    }

    @Override
    public void processAutoRenewal() {
        // 现在改成按 domain 加锁,可以并发跑多张续期了。
        // 仍按到期时间 ASC 排序(repository 已加),先到期的优先续。
        LocalDateTime sevenDaysFromNow = LocalDateTime.now().plusDays(7);
        List<SslCertificate> certificatesForRenewal =
                sslCertificateRepository.findCertificatesForAutoRenewal(sevenDaysFromNow);

        if (certificatesForRenewal.isEmpty()) return;
        log.info("准备自动续期 {} 张证书", certificatesForRenewal.size());

        for (SslCertificate certificate : certificatesForRenewal) {
            try {
                if (certificate.getCertificateType() == SslCertificate.CertificateType.LETS_ENCRYPT) {
                    // 每张证书都尝试续期;同 domain 已在申请会被锁住返回,不会重复触发
                    ReentrantLock lock = lockForDomain(certificate.getDomain());
                    if (!lock.tryLock()) {
                        log.info("自动续期跳过(domain 锁占用中): {}", certificate.getDomain());
                        continue;
                    }
                    try {
                        renewCertificate(certificate.getId());
                        log.info("自动续期证书已提交: {}", certificate.getDomain());
                    } finally {
                        lock.unlock();
                    }
                }
            } catch (Exception e) {
                log.error("自动续期失败: {} - {}", certificate.getDomain(), e.getMessage());
            }
        }
    }

    /**
     * 递归删除目录
     */
    private void deleteDirectory(File directory) {
        if (directory.isDirectory()) {
            File[] files = directory.listFiles();
            if (files != null) {
                for (File file : files) {
                    deleteDirectory(file);
                }
            }
        }
        directory.delete();
    }

    @Override
    public Map<String, Object> downloadCertificate(Long certificateId) throws Exception {
        SslCertificate certificate = sslCertificateRepository.findById(certificateId)
                .orElseThrow(() -> new RuntimeException("证书不存在: " + certificateId));

        String certFilePath = certificate.getCertificatePath();
        String keyPath = certificate.getPrivateKeyPath();

        // 检查证书文件是否存在
        if (certFilePath == null || !new File(certFilePath).exists()) {
            throw new RuntimeException("证书文件不存在");
        }
        if (keyPath == null || !new File(keyPath).exists()) {
            throw new RuntimeException("私钥文件不存在");
        }

        log.info("开始打包证书文件: {}", certificate.getDomain());

        // 使用ByteArrayOutputStream创建ZIP
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        try (ZipOutputStream zos = new ZipOutputStream(baos)) {

            // 添加证书文件
            addFileToZip(zos, new File(certFilePath), "fullchain.pem");

            // 添加私钥文件
            addFileToZip(zos, new File(keyPath), "privkey.pem");

            // 添加README说明文件
            addReadmeToZip(zos, certificate);
        }

        byte[] zipContent = baos.toByteArray();
        String zipFileName = certificate.getDomain().replace(".", "_") + "_ssl_certificate.zip";

        log.info("证书文件打包完成: {}", zipFileName);

        Map<String, Object> result = new HashMap<>();
        result.put("content", zipContent);
        result.put("fileName", zipFileName);
        result.put("contentType", "application/zip");

        return result;
    }

    /**
     * 添加文件到ZIP
     */
    private void addFileToZip(ZipOutputStream zos, File file, String entryName) throws IOException {
        ZipEntry entry = new ZipEntry(entryName);
        zos.putNextEntry(entry);

        try (FileInputStream fis = new FileInputStream(file)) {
            byte[] buffer = new byte[1024];
            int length;
            while ((length = fis.read(buffer)) > 0) {
                zos.write(buffer, 0, length);
            }
        }

        zos.closeEntry();
    }

    /**
     * 添加README说明文件到ZIP
     */
    private void addReadmeToZip(ZipOutputStream zos, SslCertificate certificate) throws IOException {
        StringBuilder readme = new StringBuilder();
        readme.append("SSL Certificate Package\n");
        readme.append("========================\n\n");
        readme.append("Domain: ").append(certificate.getDomain()).append("\n");
        readme.append("Issue Date: ").append(certificate.getIssueDate()).append("\n");
        readme.append("Expire Date: ").append(certificate.getExpireDate()).append("\n");
        readme.append("Certificate Type: ").append(certificate.getCertificateType()).append("\n\n");
        readme.append("Files:\n");
        readme.append("- fullchain.pem: Full certificate chain (certificate + intermediate certificates)\n");
        readme.append("- privkey.pem: Private key file\n\n");
        readme.append("Usage in Nginx:\n");
        readme.append("ssl_certificate /path/to/fullchain.pem;\n");
        readme.append("ssl_certificate_key /path/to/privkey.pem;\n\n");
        readme.append("WARNING: Keep the private key file secure and never share it!\n");

        ZipEntry entry = new ZipEntry("README.txt");
        zos.putNextEntry(entry);
        zos.write(readme.toString().getBytes());
        zos.closeEntry();
    }

    /**
     * 根据域名查找匹配的证书
     * 支持精确匹配和通配符匹配
     *
     * @param domain 域名,例如: api.example.com
     * @return 匹配的证书列表
     */
    public List<CertificateDTO> findCertificatesByDomain(String domain) {
        if (domain == null || domain.trim().isEmpty()) {
            return new ArrayList<>();
        }

        // 规范化域名(转小写,去除前后空格)
        domain = domain.trim().toLowerCase();

        // 从数据库获取所有有效的证书
        List<SslCertificate> allCertificates = sslCertificateRepository.findAllActive();

        List<CertificateDTO> matchedCertificates = new ArrayList<>();

        for (SslCertificate cert : allCertificates) {
            if (isDomainMatch(domain, cert.getDomain())) {
                CertificateDTO dto = new CertificateDTO();
                dto.setId(cert.getId());
                dto.setName(cert.getDomain());
                dto.setDomain(cert.getDomain());
                dto.setCertPath(cert.getCertificatePath());
                dto.setKeyPath(cert.getPrivateKeyPath());
                dto.setExpiryDate(cert.getExpireDate());
                matchedCertificates.add(dto);
            }
        }

        return matchedCertificates;
    }

    /**
     * 判断域名是否匹配证书
     * 支持以下匹配规则:
     * 1. 精确匹配: example.com 匹配 example.com
     * 2. 通配符匹配: *.example.com 匹配 api.example.com, www.example.com
     * 3. 多域名证书: 一个证书可能包含多个域名
     *
     * @param requestDomain 请求的域名
     * @param certDomain 证书中的域名(可能包含通配符)
     * @return 是否匹配
     */
    private boolean isDomainMatch(String requestDomain, String certDomain) {
        if (certDomain == null || certDomain.trim().isEmpty()) {
            return false;
        }
        if (requestDomain == null || requestDomain.trim().isEmpty()) {
            return false;
        }

        requestDomain = requestDomain.trim().toLowerCase();
        certDomain = certDomain.trim().toLowerCase();

        log.debug("域名匹配检查: request=[{}], cert=[{}]", requestDomain, certDomain);

        // 精确匹配
        if (requestDomain.equals(certDomain)) {
            log.debug("匹配方式: 精确匹配");
            return true;
        }

        // 通配符匹配
        if (certDomain.startsWith("*.")) {
            String baseDomain = certDomain.substring(2);
            String expectedEnding = "." + baseDomain;
            boolean endsWithBase = requestDomain.endsWith(expectedEnding);

            if (endsWithBase) {
                int subDomainLength = requestDomain.length() - baseDomain.length() - 1;
                String subDomain = requestDomain.substring(0, subDomainLength);
                boolean hasMultipleLevel = subDomain.contains(".");

                if (!hasMultipleLevel) {
                    log.debug("匹配方式: 通配符匹配(一级子域名), subDomain=[{}]", subDomain);
                    return true;
                }
                return false;
            }

            // 检查是否匹配基础域名本身
            if (requestDomain.equals(baseDomain)) {
                log.debug("匹配方式: 通配符匹配(基础域名)");
                return true;
            }
        }

        // 多域名证书
        if (certDomain.contains(",")) {
            String[] domains = certDomain.split(",");
            for (String domain : domains) {
                if (isDomainMatch(requestDomain, domain.trim())) {
                    return true;
                }
            }
        }

        return false;
    }
}