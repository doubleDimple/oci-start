package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.InstanceDetails;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.Date;
import java.util.List;

@Repository
public interface OracleInstanceDetailRepository extends JpaRepository<InstanceDetails, Long>, JpaSpecificationExecutor<InstanceDetails> {
    // Additional query methods can be added here if needed

    List<InstanceDetails> findByTenantId(Long tenantId);


    Page<InstanceDetails> getInstanceDetailPageByTenantId(Long tenantId, Pageable pageable);


    void deleteByTenantId(Long tenantId);

    List<InstanceDetails> findByBootVolumeId(String bootVolumeId);


    @Modifying
    @Query("UPDATE InstanceDetails b SET b.remark = :remark WHERE b.id = :id")
    int updateRemarkById(@Param("id") Long id, @Param("remark") String remark);

    InstanceDetails findByInstanceId(String instanceId);

    /**
     * Find the first instance detail with the given tenant ID and architecture type
     *
     * @param tenantId the tenant ID
     * @param architecture the architecture type
     * @return the first matching instance detail, or null if none is found
     */
    InstanceDetails findFirstByTenantIdAndArchitecture(Long tenantId, String architecture);

    /**
     * 根据enablePing和cloudType查询实例列表
     * @param enablePing Ping启用状态 (1=启用, 0=禁用)
     * @param cloudType 云类型
     * @return 实例详情列表
     */
    List<InstanceDetails> findByEnablePingAndCloudType(int enablePing, int cloudType);
    List<InstanceDetails> findByCloudType(int cloudType);

    /**
     * 根据cloudType批量更新enablePing字段
     * @param cloudType 云类型
     * @param enablePing 启用状态 0:关闭 1:开启
     * @return 更新的记录数
     */
    @Modifying
    @Query("UPDATE InstanceDetails i SET i.enablePing = :enablePing WHERE i.cloudType = :cloudType")
    int updateEnablePingByCloudType(@Param("cloudType") int cloudType, @Param("enablePing") int enablePing);

    /**
     * 只更新心跳时间
     */
    @Modifying
    @Transactional
    @Query("update InstanceDetails i set i.lastHeartbeat = ?2 where i.instanceId = ?1")
    void updateHeartbeat(String instanceId, Date time);

    /**
     * 查找离线机器
     * 条件：已安装探针 + (最后心跳时间为空 OR 最后心跳时间 < 阈值)
     */
    @Query("select i from InstanceDetails i where i.monitorInstalled = true and (i.lastHeartbeat is null or i.lastHeartbeat < ?1)")
    List<InstanceDetails> findOfflineInstances(Date threshold);
}
