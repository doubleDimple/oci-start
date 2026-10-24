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

    Optional<RegisterDetail> findFirstByTenantPrvIdOrderByIdDesc(Long tenantPrvId);

    List<RegisterDetail> findByTenantPrvIdIn(List<Long> tenantPrvIds);

    /** 降权会更换 OCI 用户，注册信息仍属于原本地租户记录。 */
    default Optional<RegisterDetail> findForTenant(Long localId, String userId) {
        Optional<RegisterDetail> local = localId == null ? Optional.empty()
                : findFirstByTenantPrvIdOrderByIdDesc(localId);
        return local.isPresent() ? local : userId == null ? Optional.empty() : findByTenantId(userId);
    }

    List<RegisterDetail> findByTenantIdIn(List<String> tenantIds);
}
