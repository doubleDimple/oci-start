package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.RegisterDetail;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface RegisterDetailRepository extends JpaRepository<RegisterDetail, Long>, JpaSpecificationExecutor<RegisterDetail> {

    /**
     * 根据租户ID查找注册详情
     */
    Optional<RegisterDetail> findByTenantId(String tenantId);

    List<RegisterDetail> findByTenantIdIn(List<String> tenantIds);
}
