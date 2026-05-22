package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.ProxyConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ProxyConfigRepository extends JpaRepository<ProxyConfig, Long>, JpaSpecificationExecutor<ProxyConfig> {

    Optional<ProxyConfig> findByDomain(String domain);

    boolean existsByDomain(String domain);

    List<ProxyConfig> findByConfigStatusNot(ProxyConfig.ConfigStatus status);

    /** 是否还有 Proxy 在引用某张证书,删除证书前用来做引用检查 */
    boolean existsBySslCertificateId(Long sslCertificateId);

    /** 找到所有引用此证书的 Proxy,用于级联清理 SSL 状态 */
    List<ProxyConfig> findBySslCertificateId(Long sslCertificateId);
}
