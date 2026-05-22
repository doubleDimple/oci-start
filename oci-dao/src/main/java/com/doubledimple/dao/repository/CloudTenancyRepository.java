package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.CloudTenancy;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CloudTenancyRepository extends JpaRepository<CloudTenancy, Long>, JpaSpecificationExecutor<CloudTenancy> {

    /**
     * 根据租户名称查找
     * @param tenancyName 租户名称
     * @return 云租户配置
     */
    Optional<CloudTenancy> findByTenancyNameAndType(String tenancyName,Integer type);

    /**
     * 根据云类型查找所有配置
     * @param cloudType 云类型
     * @return 云租户配置列表
     */
    List<CloudTenancy> findByCloudTypeAndType(Integer cloudType,Integer  type);

    /**
     * 根据自定义名称查找
     * @param defName 自定义名称
     * @return 云租户配置列表
     */
    List<CloudTenancy> findByDefNameContainingAndType(String defName,Integer type);

    /**
     * 根据租户名称和云类型查找
     * @param tenancyName 租户名称
     * @param cloudType 云类型
     * @return 云租户配置
     */
    Optional<CloudTenancy> findByTenancyNameAndCloudTypeAndType(String tenancyName, Integer cloudType,Integer  type);

    /**
     * 获取最新创建的记录
     * @return 最新的云租户配置
     */
    Optional<CloudTenancy> findFirstByOrderByCreateTimeDesc();

    /**
     * 获取最早创建的记录
     * @return 最早的云租户配置
     */
    Optional<CloudTenancy> findFirstByOrderByCreateTimeAsc();


    /**
     * 检查租户名称是否存在
     * @param tenancyName 租户名称
     * @return 是否存在
     */
    boolean existsByTenancyNameAndType(String tenancyName,Integer type);

}
