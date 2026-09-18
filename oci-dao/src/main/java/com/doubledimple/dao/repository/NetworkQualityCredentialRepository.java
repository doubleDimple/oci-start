package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.NetworkQualityCredential;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import javax.persistence.LockModeType;
import java.util.Optional;

public interface NetworkQualityCredentialRepository extends JpaRepository<NetworkQualityCredential, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from NetworkQualityCredential c where c.tokenHash = :hash or c.pendingHash = :hash")
    Optional<NetworkQualityCredential> lockByHash(@Param("hash") String hash);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from NetworkQualityCredential c where c.instanceId = :id")
    Optional<NetworkQualityCredential> lockByInstance(@Param("id") Long id);
}
