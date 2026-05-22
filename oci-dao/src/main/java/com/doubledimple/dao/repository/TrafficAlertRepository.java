package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.TrafficAlert;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface TrafficAlertRepository extends JpaRepository<TrafficAlert, Long> {

    Optional<TrafficAlert> findByTenantId(Long tenantId);

    Optional<TrafficAlert> findByTenancy(String tenancy);

    boolean existsByTenantId(Long tenantId);

}
