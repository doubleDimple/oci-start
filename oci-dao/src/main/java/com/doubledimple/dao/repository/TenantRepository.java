package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.Tenant;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

/**
 * @author doubleDimple
 * @date 2024:10:07日 13:52
 */
public interface TenantRepository extends JpaRepository<Tenant, Long> {

    List<Tenant> findByTenancy(String tenancy);

    /**
    * 根据tenancy查询租户
    */
    @Query("SELECT t FROM Tenant t WHERE t.tenancy = :tenancy AND (t.parenId IS NULL OR t.parenId = 0)")
    List<Tenant> findByTenancyAndNoParent(String tenancy);

    Page<Tenant> findByParenIdIsNullOrParenIdAndCloudType(Long parentId,Integer cloudType, Pageable pageable);

    @Query("select t from Tenant t " +
            "where (t.parenId is null or t.parenId = 0) " +
            "and t.cloudType = :cloudType")
    Page<Tenant> findParentTenant(@Param("cloudType") int cloudType, Pageable pageable);

    List<Tenant> findByParenId(Long parentId);


    @Query("SELECT COUNT(b.tenantId) FROM Tenant b")
    Long queryDistinctByTenantId();

    List<Tenant> queryByUserName(String userName);


    @Query(value = "SELECT t.id AS tenant_id, t.tenantId AS tenant_external_id, " +
            "t.userName AS tenant_user_name, t.fingerprint AS tenant_fingerprint, " +
            "t.tenancy AS tenant_tenancy, t.region AS tenant_region, t.keyFile AS tenant_key_file, " +
            "b.id AS boot_instance_id, b.bootId AS boot_instance_external_id, b.ocpu AS boot_instance_ocpu, " +
            "b.memory AS boot_instance_memory, b.disk AS boot_instance_disk, b.loopTime AS boot_instance_loop_time, " +
            "b.instanceCount AS boot_instance_count, b.status AS boot_instance_status, " +
            "b.architecture AS boot_instance_architecture, b.rootPassword AS boot_instance_root_password, " +
            "b.publicIp AS boot_instance_public_ip FROM Tenant t LEFT JOIN BootInstance b ON t.id = b.tenantId " +
            "WHERE t.cloudType = 1")
    List<Map<String, Object>> fetchTenantAndBootInstanceData();



    /**
     * 根据租户名或区域进行模糊搜索，并指定父ID条件
     */
    @Query("SELECT t FROM Tenant t WHERE (t.parenId IS NULL OR t.parenId = :parenId) AND " +
            "t.cloudType = :cloudType AND " +
            "(LOWER(t.tenancyName) LIKE LOWER(CONCAT('%', :keyword, '%')) OR " +
            "LOWER(t.region) LIKE LOWER(CONCAT('%', :keyword, '%')))")
    Page<Tenant> searchByKeyword(@Param("keyword") String keyword,@Param("cloudType") Integer cloudType, @Param("parenId") Long parenId, Pageable pageable);

    List<Tenant> findByTenantId(String tenantId);

    /** 按 OCI Tenancy OCID 只查父记录（parenId IS NULL 或 0），避免子域干扰 */
    @Query("SELECT t FROM Tenant t WHERE t.tenantId = :tenantId AND (t.parenId IS NULL OR t.parenId = 0)")
    List<Tenant> findParentByTenancyOcid(@Param("tenantId") String tenantId);



    /**
     * 根据tenantId查询其父级记录
     * @param tenantId 租户ID
     * @return 父级租户记录，如果没有父级则返回null
     */
    default Tenant findParentByChildTenantId(String tenantId) {
        Tenant tenantResult = null;
        // 先查找当前租户
        List<Tenant> byTenantId = findByTenantId(tenantId);

        // 如果租户不存在，直接返回null
        if (byTenantId == null || byTenantId.isEmpty()) {
            return null;
        }

        // 如果租户没有父级ID或父级ID为0，表示是顶级租户
        for (Tenant tenant : byTenantId) {
            if (tenant.getParenId() == null || tenant.getParenId() == 0L) {
                if (!tenant.getIsHomeRegion()){
                    //证明此处是旧数据,不处理了
                    return null;
                }
                return tenant;
            }

            // 使用父级ID查找父级租户
            tenantResult = findById(tenant.getParenId()).orElse(null);
        }
        return tenantResult;
    }

    @Query("SELECT t FROM Tenant t WHERE (t.parenId IS NULL OR t.parenId = 0) AND t.cloudType = :cloudType AND t.emailEnable = :emailEnable")
    Page<Tenant> findByCloudTypeAndEmailEnable(@Param("cloudType") Integer cloudType, @Param("emailEnable") int emailEnable, Pageable pageable);

    @Query("SELECT t FROM Tenant t WHERE (t.parenId IS NULL OR t.parenId = 0) AND t.cloudType = :cloudType AND t.emailEnable = :emailEnable AND (LOWER(t.tenancyName) LIKE LOWER(CONCAT('%', :keyword, '%')) OR LOWER(t.region) LIKE LOWER(CONCAT('%', :keyword, '%')))")
    Page<Tenant> findByCloudTypeAndEmailEnableAndKeyword(@Param("cloudType") Integer cloudType, @Param("emailEnable") int emailEnable, @Param("keyword") String keyword, Pageable pageable);

    /**
     * 批量将账号标记为失效状态
     * @param ids 需要标记为失效的租户ID列表
     */
    @Transactional
    @Modifying
    @Query("UPDATE Tenant t SET t.isActive = false WHERE t.id IN :ids")
    void batchUpdateStatusToInactive(@Param("ids") List<Long> ids);

}
