package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.VpnProxyRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface VpnProxyRecordRepository
        extends JpaRepository<VpnProxyRecord, Long>, JpaSpecificationExecutor<VpnProxyRecord> {


    VpnProxyRecord findTopByProxyHost(String proxyHost);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("UPDATE VpnProxyRecord p SET p.forceProxy = :forceProxy, p.updateTime = :updatedAt WHERE p.id = :id")
    int updateForce(@Param("id") Long id, @Param("forceProxy") Integer forceProxy,
                    @Param("updatedAt") LocalDateTime updatedAt);

    /** Never merge an old probe entity: it may have been edited or deleted while network I/O was in flight. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("UPDATE VpnProxyRecord p SET p.availableStatus = :status, p.updateTime = :updatedAt "
            + "WHERE p.id = :id AND p.proxyType = :type AND p.proxyHost = :host AND p.proxyPort = :port "
            + "AND (p.proxyUsername = :username OR (p.proxyUsername IS NULL AND :username IS NULL)) "
            + "AND (p.proxyPassword = :password OR (p.proxyPassword IS NULL AND :password IS NULL))")
    int updateProbeStatus(@Param("id") Long id, @Param("type") String type, @Param("host") String host,
                          @Param("port") Integer port, @Param("username") String username,
                          @Param("password") String password, @Param("status") Integer status,
                          @Param("updatedAt") LocalDateTime updatedAt);

    List<VpnProxyRecord> findAllByAvailableStatus(Integer availableStatus);

    /**
     * 全局可用代理（未绑定租户）随机一条：
     * tenant_id 为空，且不在 bind 表中出现。
     */
    @Query(value = "SELECT * FROM vpn_proxy_record p WHERE p.available_status = :status "
            + "AND p.tenant_id IS NULL "
            + "AND NOT EXISTS (SELECT 1 FROM vpn_proxy_tenant_bind b WHERE b.proxy_id = p.id) "
            + "ORDER BY RAND() LIMIT 1", nativeQuery = true)
    VpnProxyRecord findRandomAvailableGlobal(@Param("status") Integer status);

    /**
     * 兼容旧调用：任意可用代理随机一条（含已绑定租户的）
     */
    @Query(value = "SELECT * FROM vpn_proxy_record WHERE available_status = :status ORDER BY RAND() LIMIT 1", nativeQuery = true)
    VpnProxyRecord findRandomAvailableRecord(@Param("status") Integer status);

    /**
     * 指定父租户绑定的可用代理（优先 bind 表，兼容旧 tenant_id 列）
     */
    @Query(value = "SELECT p.* FROM vpn_proxy_record p "
            + "WHERE p.available_status = :status AND ("
            + "  p.id IN (SELECT b.proxy_id FROM vpn_proxy_tenant_bind b WHERE b.tenant_id = :tenantId) "
            + "  OR p.tenant_id = :tenantId"
            + ") ORDER BY p.id DESC LIMIT 1", nativeQuery = true)
    VpnProxyRecord findAvailableByTenantId(@Param("tenantId") Long tenantId, @Param("status") Integer status);

    /**
     * 指定父租户绑定的代理（不限可用状态，用于强制代理判断）
     */
    @Query(value = "SELECT p.* FROM vpn_proxy_record p "
            + "WHERE ("
            + "  p.id IN (SELECT b.proxy_id FROM vpn_proxy_tenant_bind b WHERE b.tenant_id = :tenantId) "
            + "  OR p.tenant_id = :tenantId"
            + ") ORDER BY p.id DESC LIMIT 1", nativeQuery = true)
    VpnProxyRecord findTopByTenantId(@Param("tenantId") Long tenantId);

    /**
     * 全局强制代理（任意一条）：无 bind、tenant_id 为空、force=1
     */
    @Query(value = "SELECT * FROM vpn_proxy_record p WHERE p.tenant_id IS NULL AND p.force_proxy = 1 "
            + "AND NOT EXISTS (SELECT 1 FROM vpn_proxy_tenant_bind b WHERE b.proxy_id = p.id) "
            + "ORDER BY p.id DESC LIMIT 1", nativeQuery = true)
    VpnProxyRecord findForceGlobal();

    /**
     * 已绑定代理的父租户 ID（兼容旧列 + bind 表，用于列表护盾）
     */
    @Query(value = "SELECT DISTINCT tenant_id FROM ("
            + "  SELECT tenant_id FROM vpn_proxy_record WHERE tenant_id IS NOT NULL "
            + "  UNION "
            + "  SELECT tenant_id FROM vpn_proxy_tenant_bind"
            + ") t", nativeQuery = true)
    List<Long> findBoundTenantIds();

    /**
     * 所有已绑定租户的代理（列表护盾：区分强制/普通）。
     * 返回含 tenant_id 的旧记录；多租户绑定由 Service 再合并 bind 表。
     */
    @Query("SELECT v FROM VpnProxyRecord v WHERE v.tenantId IS NOT NULL")
    List<VpnProxyRecord> findAllBoundRecords();
}
