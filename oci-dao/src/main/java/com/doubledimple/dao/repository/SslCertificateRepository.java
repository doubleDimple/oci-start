package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.SslCertificate;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface SslCertificateRepository extends JpaRepository<SslCertificate, Long>, JpaSpecificationExecutor<SslCertificate> {
    Optional<SslCertificate> findByDomain(String domain);

    @Query("SELECT s FROM SslCertificate s WHERE s.expireDate <= :date AND s.status = 'VALID'")
    List<SslCertificate> findExpiringCertificates(LocalDateTime date);

    @Query("SELECT s FROM SslCertificate s WHERE s.autoRenew = true AND s.expireDate <= :date " +
            "AND s.status IN ('VALID', 'EXPIRING_SOON') " +
            "ORDER BY s.expireDate ASC")
    List<SslCertificate> findCertificatesForAutoRenewal(LocalDateTime date);

    /**
     * 查询所有有效的证书(未过期且未删除)
     */
    @Query("SELECT c FROM SslCertificate c WHERE c.status = 'VALID' AND c.expireDate > CURRENT_TIMESTAMP ORDER BY c.expireDate DESC")
    List<SslCertificate> findAllActive();

}
