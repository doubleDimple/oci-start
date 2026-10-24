package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.BanRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface BanRecordRepository extends JpaRepository<BanRecord, Long>, JpaSpecificationExecutor<BanRecord> {

    BanRecord findTopByIpAddress(String ip);

    BanRecord findTopByIpAddressOrderByIdDesc(String ip);

    BanRecord findTopByIpAddressAndStatusOrderByIdDesc(String ip, Integer status);

    List<BanRecord> findAllByIpAddressAndStatusOrderByIdDesc(String ip, Integer status);

}
