package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.VpsMonitor;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;


@Repository
public interface VpsMonitorRepository extends JpaRepository<VpsMonitor, Long>, JpaSpecificationExecutor<VpsMonitor> {

}
