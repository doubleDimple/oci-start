package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.ServerMetrics;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ServerMetricsRepository extends JpaRepository<ServerMetrics, Long>, JpaSpecificationExecutor<ServerMetrics> {


    /**
     * 查找每个服务器最新的一条记录
     */
    @Query("SELECT m FROM ServerMetrics m WHERE m.lastConnectionTime = " +
            "(SELECT MAX(m2.lastConnectionTime) FROM ServerMetrics m2 WHERE m2.serverId = m.serverId)")
    List<ServerMetrics> findLatestMetricsForAllServers();

    /**
     * 查找指定服务器最新的一条记录
     */
    ServerMetrics findTopByServerIdOrderByLastConnectionTimeDesc(String serverId);


    List<ServerMetrics> findAllByServerId(String serverId);

    void deleteByServerId(String serverId);
}
