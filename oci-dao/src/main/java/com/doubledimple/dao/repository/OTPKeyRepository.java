package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.OTPKey;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import javax.persistence.LockModeType;
import java.util.Optional;

@Repository
public interface OTPKeyRepository extends JpaRepository<OTPKey, Long>, JpaSpecificationExecutor<OTPKey> {

    // 根据 name 删除一条记录
    void deleteByKeyName(String keyName);

    OTPKey queryOTPKeyByKeyName(String keyName);

    OTPKey findByKeyName(String keyName);

    OTPKey findBySecretKey(String secretKey);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select k from OTPKey k where k.id = :id")
    Optional<OTPKey> lockById(@Param("id") Long id);
}
