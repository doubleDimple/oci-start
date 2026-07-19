package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.VpnProxyTenantBind;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.List;

@Repository
public interface VpnProxyTenantBindRepository extends JpaRepository<VpnProxyTenantBind, Long> {

    List<VpnProxyTenantBind> findByProxyId(Long proxyId);

    List<VpnProxyTenantBind> findByProxyIdIn(Collection<Long> proxyIds);

    VpnProxyTenantBind findTopByTenantId(Long tenantId);

    List<VpnProxyTenantBind> findByTenantIdIn(Collection<Long> tenantIds);

    @Modifying
    @Transactional
    void deleteByProxyId(Long proxyId);

    @Modifying
    @Transactional
    void deleteByTenantId(Long tenantId);

    @Modifying
    @Transactional
    @Query("DELETE FROM VpnProxyTenantBind b WHERE b.tenantId IN :tenantIds AND b.proxyId <> :excludeProxyId")
    int deleteByTenantIdInAndProxyIdNot(@Param("tenantIds") Collection<Long> tenantIds,
                                        @Param("excludeProxyId") Long excludeProxyId);

    @Query("SELECT DISTINCT b.tenantId FROM VpnProxyTenantBind b")
    List<Long> findAllBoundTenantIds();
}
