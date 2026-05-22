package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.ConsoleConnection;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * 控制台连接信息仓库接口
 *
 * @author doubleДимple
 * @date 2025-01-01
 */
@Repository
public interface ConsoleConnectionRepository extends JpaRepository<ConsoleConnection, Long> {

    /**
     * 根据实例ID和租户ID查找连接
     */
    Optional<ConsoleConnection> findByInstanceIdAndTenantId(String instanceId, Long tenantId);

    /**
     * 根据连接ID查找
     */
    Optional<ConsoleConnection> findByConnectionId(String connectionId);

    /**
     * 根据租户ID查找所有连接
     */
    List<ConsoleConnection> findByTenantId(Long tenantId);

    /**
     * 根据实例ID查找所有连接
     */
    List<ConsoleConnection> findByInstanceId(String instanceId);

    /**
     * 删除指定实例和租户的连接记录
     */
    void deleteByInstanceIdAndTenantId(String instanceId, Long tenantId);
}
