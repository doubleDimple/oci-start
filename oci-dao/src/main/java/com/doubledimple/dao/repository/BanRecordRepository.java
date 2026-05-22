package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.dao.entity.BanRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface BanRecordRepository extends JpaRepository<BanRecord, Long>, JpaSpecificationExecutor<BanRecord> {

    BanRecord findTopByIpAddress(String ip);

}
