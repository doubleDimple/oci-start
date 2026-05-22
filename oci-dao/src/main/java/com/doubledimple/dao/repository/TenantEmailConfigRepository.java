package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.TenantEmailConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface TenantEmailConfigRepository extends JpaRepository<TenantEmailConfig, Long>, JpaSpecificationExecutor<TenantEmailConfig> {


    Optional<TenantEmailConfig> findByDomainName(String domainName);

    List<TenantEmailConfig> findByTenantId(Long tenantId);
}
