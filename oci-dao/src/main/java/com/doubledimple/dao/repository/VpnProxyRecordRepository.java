package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.VpnProxyRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Repository
public interface VpnProxyRecordRepository
        extends JpaRepository<VpnProxyRecord, Long>, JpaSpecificationExecutor<VpnProxyRecord> {


    VpnProxyRecord findTopByProxyHost(String proxyHost);

    List<VpnProxyRecord> findAllByAvailableStatus(Integer availableStatus);

    /**
     * 全局可用代理（未绑定租户）随机一条
     */
    @Query(value = "SELECT * FROM vpn_proxy_record WHERE available_status = :status AND tenant_id IS NULL ORDER BY RAND() LIMIT 1", nativeQuery = true)
    VpnProxyRecord findRandomAvailableGlobal(@Param("status") Integer status);

    /**
     * 兼容旧调用：任意可用代理随机一条（含已绑定租户的）
     */
    @Query(value = "SELECT * FROM vpn_proxy_record WHERE available_status = :status ORDER BY RAND() LIMIT 1", nativeQuery = true)
    VpnProxyRecord findRandomAvailableRecord(@Param("status") Integer status);

    /**
     * 指定父租户绑定的可用代理
     */
    @Query(value = "SELECT * FROM vpn_proxy_record WHERE available_status = :status AND tenant_id = :tenantId ORDER BY RAND() LIMIT 1", nativeQuery = true)
    VpnProxyRecord findAvailableByTenantId(@Param("tenantId") Long tenantId, @Param("status") Integer status);

    /**
     * 一个父租户只保留一条绑定：解绑其余
     */
    @Modifying
    @Transactional
    @Query("UPDATE VpnProxyRecord v SET v.tenantId = null WHERE v.tenantId = :tenantId AND v.id <> :excludeId")
    int clearTenantBindingExcept(@Param("tenantId") Long tenantId, @Param("excludeId") Long excludeId);
}
