package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.OtherBootInstance;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * OtherBootInstance数据访问层
 */
@Repository
public interface OtherBootInstanceRepository extends JpaRepository<OtherBootInstance, Long> {

    /**
     * 根据bootId和cloudType查找实例
     */
    OtherBootInstance findByBootIdAndCloudType(String bootId, Integer cloudType);

    /**
     * 根据租户ID和云厂商类型查找实例
     */
    List<OtherBootInstance> findByTenantIdAndCloudType(Long tenantId, Integer cloudType);

    /**
     * 根据状态和云厂商类型查找实例
     */
    List<OtherBootInstance> findByStatusAndCloudType(Integer status, Integer cloudType);

    /**
     * 根据租户ID和云厂商类型查找实例（分页）
     */
    Page<OtherBootInstance> findByTenantIdAndCloudType(Long tenantId, Integer cloudType, Pageable pageable);

    Page<OtherBootInstance> findByCloudType(Integer cloudType, Pageable pageable);

    /**
     * 根据租户ID、状态和云厂商类型查找实例
     */
    List<OtherBootInstance> findByTenantIdAndStatusAndCloudType(Long tenantId, Integer status, Integer cloudType);

    /**
     * 根据租户ID、云厂商类型和状态查找实例
     */
    List<OtherBootInstance> findByTenantIdAndCloudTypeAndStatus(Long tenantId, Integer cloudType, Integer status);

    /**
     * 统计租户在指定云厂商的实例数量
     */
    @Query("SELECT COUNT(o) FROM OtherBootInstance o WHERE o.tenantId = :tenantId AND o.cloudType = :cloudType")
    Long countByTenantIdAndCloudType(@Param("tenantId") Long tenantId, @Param("cloudType") Integer cloudType);

    /**
     * 统计租户在指定云厂商的运行中实例数量
     */
    @Query("SELECT COUNT(o) FROM OtherBootInstance o WHERE o.tenantId = :tenantId AND o.cloudType = :cloudType AND o.status = 2")
    Long countRunningInstancesByTenantIdAndCloudType(@Param("tenantId") Long tenantId, @Param("cloudType") Integer cloudType);

    /**
     * 统计指定云厂商的实例数量
     */
    @Query("SELECT COUNT(o) FROM OtherBootInstance o WHERE o.cloudType = :cloudType")
    Long countByCloudType(@Param("cloudType") Integer cloudType);

    /**
     * 删除指定租户在指定云厂商的所有实例
     */
    void deleteByTenantIdAndCloudType(Long tenantId, Integer cloudType);

    /**
     * 根据架构类型和云厂商类型查找实例
     */
    List<OtherBootInstance> findByArchitectureAndCloudType(String architecture, Integer cloudType);

    /**
     * 根据公网IP和云厂商类型查找实例
     */
    OtherBootInstance findByPublicIpAndCloudType(String publicIp, Integer cloudType);

    /**
     * 查找指定时间范围内创建的指定云厂商实例
     */
    @Query("SELECT o FROM OtherBootInstance o WHERE o.cloudType = :cloudType AND o.createdAt BETWEEN :startTime AND :endTime")
    List<OtherBootInstance> findByCloudTypeAndCreatedAtBetween(@Param("cloudType") Integer cloudType,
                                                               @Param("startTime") java.time.LocalDateTime startTime,
                                                               @Param("endTime") java.time.LocalDateTime endTime);

    /**
     * 查找指定云厂商长时间运行的实例（运行超过指定小时数）
     */
    @Query("SELECT o FROM OtherBootInstance o WHERE o.cloudType = :cloudType AND o.status = 2 AND o.updatedAt < :cutoffTime")
    List<OtherBootInstance> findLongRunningInstancesByCloudType(@Param("cloudType") Integer cloudType,
                                                                @Param("cutoffTime") java.time.LocalDateTime cutoffTime);

    /**
     * 根据租户ID、云厂商类型和架构查找实例
     */
    List<OtherBootInstance> findByTenantIdAndCloudTypeAndArchitecture(Long tenantId, Integer cloudType, String architecture);

    void deleteByTenantId(Long tenantId);
}
