package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.ChatAiConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

@Repository
public interface ChatAiConfigRepository extends JpaRepository<ChatAiConfig, Long>, JpaSpecificationExecutor<ChatAiConfig> {

    /**
     * 根据云厂商类型查询配置
     */
    Optional<List<ChatAiConfig>> findByCloudType(Integer cloudType);

    /**
     * 检查指定云厂商类型的配置是否存在
     */
    boolean existsByCloudType(Integer cloudType);

    /**
     * 更新指定云厂商类型的启用状态
     */
    @Modifying
    @Transactional
    @Query("UPDATE ChatAiConfig c SET c.enabled = :enabled WHERE c.cloudType = :cloudType")
    int updateEnabledByCloudType(@Param("cloudType") Integer cloudType, @Param("enabled") Boolean enabled);

    /**
     * 删除指定云厂商类型的配置
     */
    @Modifying
    @Transactional
    @Query("DELETE FROM ChatAiConfig c WHERE c.cloudType = :cloudType")
    int deleteByCloudType(@Param("cloudType") Integer cloudType);

    /**
     * 查询表中最大的ID值
     */
    @Query("SELECT MAX(c.id) FROM ChatAiConfig c")
    Optional<Long> findMaxId();

    /**
     * 根据 modelId 查询最新的一条且处于启用状态的配置
     * 按照 ID 倒序排列，取第一条
     *
     * @param modelId 模型ID
     * @return 匹配的配置
     */
    Optional<ChatAiConfig> findFirstByShowModelIdAndEnabledTrueOrderByIdDesc(String modelId);
}
