package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.NginxConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface NginxConfigRepository extends JpaRepository<NginxConfig, Long>, JpaSpecificationExecutor<NginxConfig> {

    Optional<NginxConfig> findByIsCurrentTrue();

    Optional<NginxConfig> findFirstByOrderByConfigVersionDesc();
}
