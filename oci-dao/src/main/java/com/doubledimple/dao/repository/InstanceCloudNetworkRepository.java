package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.InstanceCloudNetWork;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface InstanceCloudNetworkRepository extends JpaRepository<InstanceCloudNetWork, Long> {

    // 根据VCN ID查找
    Optional<InstanceCloudNetWork> findByVcnId(String vcnId);

    // 根据子网ID查找
    Optional<InstanceCloudNetWork> findBySubnetId(String subnetId);

    // 根据租户ID查找
    List<InstanceCloudNetWork> findByTenantId(String tenantId);

    // 根据区域查找
    List<InstanceCloudNetWork> findByRegion(String region);

    // 根据租户和区域查找
    List<InstanceCloudNetWork> findByTenantIdAndRegion(String tenantId, String region);

    // 根据状态查找

    // 根据租户id和区域查询
    @Query(value = "SELECT * FROM instance_cloud_network n WHERE " +
            "(:tenantId IS NULL OR n.tenant_id = :tenantId) AND " +
            "(:region IS NULL OR n.region = :region) " +
            "LIMIT 1", nativeQuery = true)
    Optional<InstanceCloudNetWork> findFirstByConditions(
            @Param("tenantId") String tenantId,
            @Param("region") String region
    );


    // 根据tenantId、vcnId、region和subnetId查询唯一记录
    Optional<InstanceCloudNetWork> findByTenantIdAndVcnIdAndRegionAndSubnetId(
            String tenantId,
            String vcnId,
            String region,
            String subnetId
    );

    //这里的tenantId是provider的tenantId
    // 根据tenantId和region查询最新的一条记录
    Optional<InstanceCloudNetWork> findFirstByTenantIdAndRegionOrderByCreatedAtDesc(
            String tenantId,
            String region
    );
}
