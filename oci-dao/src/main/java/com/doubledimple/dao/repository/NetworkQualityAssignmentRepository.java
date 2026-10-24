package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.NetworkQualityAssignment;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import javax.persistence.LockModeType;
import java.util.List;
import java.util.Optional;

public interface NetworkQualityAssignmentRepository extends JpaRepository<NetworkQualityAssignment, Long> {
    List<NetworkQualityAssignment> findByTaskIdOrderByIdAsc(Long taskId);
    Optional<NetworkQualityAssignment> findByInstanceIdAndTaskId(Long instanceId, Long taskId);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from NetworkQualityAssignment a where a.instanceId = :id order by a.id")
    List<NetworkQualityAssignment> lockForInstance(@Param("id") Long instanceId);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from NetworkQualityAssignment a where a.taskId = :id order by a.id")
    List<NetworkQualityAssignment> lockForTask(@Param("id") Long taskId);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from NetworkQualityAssignment a where a.instanceId = :instanceId and a.taskId = :taskId")
    Optional<NetworkQualityAssignment> lockPair(@Param("instanceId") Long instanceId, @Param("taskId") Long taskId);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from NetworkQualityAssignment a where a.leaseExpiresAt <= :now order by a.id")
    List<NetworkQualityAssignment> lockExpired(@Param("now") Long now, Pageable pageable);
}
