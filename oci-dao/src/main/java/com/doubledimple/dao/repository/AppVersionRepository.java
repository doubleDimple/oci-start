package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.AppVersion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface AppVersionRepository extends JpaRepository<AppVersion, Long>, JpaSpecificationExecutor<AppVersion> {
    Optional<AppVersion> findFirstByOrderByUpdateTimeDesc();

    Optional<AppVersion> findFirstByOrderByIdAsc();
}
