package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.SystemConfig;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SystemConfigRepository extends JpaRepository<SystemConfig, Long> {
    Optional<SystemConfig> findByKey(String key);
    boolean existsByKey(String key);
}
