package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.DbConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DbConfigRepository extends JpaRepository<DbConfig, Long>, JpaSpecificationExecutor<DbConfig> {

    // 根据租户ID、云厂商类型和数据库类型查询配置
    List<DbConfig> findByTenantIdAndCloudTypeAndDbType(Long tenantId, int cloudType, int dbType);

    DbConfig findByTenantIdAndDbIdAndCloudType(Long tenantId, String dbId, Integer cloudType);
}
