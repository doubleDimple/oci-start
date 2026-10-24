package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.NetworkQualityTask;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import javax.persistence.LockModeType;
import java.util.Optional;

public interface NetworkQualityTaskRepository extends JpaRepository<NetworkQualityTask, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from NetworkQualityTask t where t.id = :id")
    Optional<NetworkQualityTask> lockById(@Param("id") Long id);
}
