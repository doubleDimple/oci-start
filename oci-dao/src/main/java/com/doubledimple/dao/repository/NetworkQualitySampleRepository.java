package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.NetworkQualitySample;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface NetworkQualitySampleRepository extends JpaRepository<NetworkQualitySample, Long> {
    @Query("select s from NetworkQualitySample s where s.instanceId=:instanceId and s.taskId=:taskId and s.revision=:revision and s.updatedAt>=:from and s.updatedAt<=:to order by s.updatedAt desc, s.id desc")
    List<NetworkQualitySample> window(@Param("instanceId") Long instanceId, @Param("taskId") Long taskId,
                                     @Param("revision") Long revision, @Param("from") Long from, @Param("to") Long to, Pageable pageable);
    @Query("select count(s) as count, " +
            "sum(case when s.status='success' then 1 else 0 end) as successCount, " +
            "sum(case when s.status='partial' then 1 else 0 end) as partialCount, " +
            "sum(case when s.status='failed' then 1 else 0 end) as failedCount, " +
            "sum(case when s.status='unsupported' then 1 else 0 end) as unsupportedCount, " +
            "sum(case when s.status='error' then 1 else 0 end) as errorCount, " +
            "sum(case when s.status='unknown' then 1 else 0 end) as unknownCount, " +
            "sum(s.attempts) as attempts, sum(s.successful) as successful, " +
            "sum(s.avgMs * s.successful) as weightedMs, min(s.minMs) as minMs, max(s.maxMs) as maxMs " +
            "from NetworkQualitySample s where s.instanceId=:instanceId and s.taskId=:taskId and s.revision=:revision and s.updatedAt>=:from and s.updatedAt<=:to")
    WindowStats statistics(@Param("instanceId") Long instanceId, @Param("taskId") Long taskId,
                           @Param("revision") Long revision, @Param("from") Long from, @Param("to") Long to);
    @Query("select s.id from NetworkQualitySample s where s.updatedAt < :cutoff order by s.id")
    List<Long> expiredIds(@Param("cutoff") Long cutoff, Pageable pageable);
    @Modifying
    @Query("delete from NetworkQualitySample s where s.id in :ids")
    int deleteIds(@Param("ids") List<Long> ids);
    @Modifying
    @Query("delete from NetworkQualitySample s where s.taskId=:taskId")
    int deleteTaskHistory(@Param("taskId") Long taskId);

    interface WindowStats {
        Long getCount(); Long getSuccessCount(); Long getPartialCount(); Long getFailedCount();
        Long getUnsupportedCount(); Long getErrorCount(); Long getUnknownCount();
        Long getAttempts(); Long getSuccessful(); Double getWeightedMs(); Double getMinMs(); Double getMaxMs();
    }
}
