package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.AuditLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 审计日志持久层
 *
 * @author doubleDimple
 */
@Repository
public interface AuditLogRepository extends JpaRepository<AuditLog, Long>, JpaSpecificationExecutor<AuditLog> {

    @Modifying
    @Transactional
    @Query("delete from AuditLog a where a.id in :ids")
    int deleteAllByIdIn(@Param("ids") List<Long> ids);

    @Modifying
    @Transactional
    @Query("delete from AuditLog a")
    int clearAll();

    @Modifying
    @Transactional
    @Query("delete from AuditLog a where a.createTime < :beforeDate")
    int deleteBeforeDate(@Param("beforeDate") LocalDateTime beforeDate);
}
