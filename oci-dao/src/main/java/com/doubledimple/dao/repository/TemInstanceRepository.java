package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.TemInstance;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TemInstanceRepository extends JpaRepository<TemInstance, Long> {

    /**
     * 根据租户、区域和架构类型查询临时实例
     * @param tenancy 租户标识符
     * @param region 区域
     * @param architecture 架构类型
     * @return 符合条件的临时实例
     */
    List<TemInstance> findByTenancyAndRegionAndArchitecture(String tenancy, String region, String architecture);

    TemInstance findByInstanceId(String instanceId);


    /**
     * 根据租户、区域和架构类型删除临时实例
     * @param tenancy 租户标识符
     * @param region 区域
     * @param architecture 架构类型
     */
    void deleteByTenancyAndRegionAndArchitecture(String tenancy, String region, String architecture);

}

