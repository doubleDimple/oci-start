package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.SystemConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import javax.persistence.LockModeType;
import java.util.List;

import java.util.Optional;

public interface SystemConfigRepository extends JpaRepository<SystemConfig, Long> {
    Optional<SystemConfig> findByKey(String key);
    boolean existsByKey(String key);
    List<SystemConfig> findAllByKeyStartingWith(String prefix);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from SystemConfig c where c.key like 'api.token.%' order by c.key")
    List<SystemConfig> lockApiTokenSettings();
}
