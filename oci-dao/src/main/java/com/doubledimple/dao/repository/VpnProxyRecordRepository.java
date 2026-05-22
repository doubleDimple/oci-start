package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.VpnProxyRecord;
import org.apache.catalina.LifecycleState;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface VpnProxyRecordRepository
        extends JpaRepository<VpnProxyRecord, Long>, JpaSpecificationExecutor<VpnProxyRecord> {


    VpnProxyRecord findTopByProxyHost(String proxyHost);

    List<VpnProxyRecord> findAllByAvailableStatus(Integer availableStatus);

    @Query(value = "SELECT * FROM vpn_proxy_record WHERE available_status = :status ORDER BY RAND() LIMIT 1", nativeQuery = true)
    VpnProxyRecord findRandomAvailableRecord(@Param("status") Integer status);
}
