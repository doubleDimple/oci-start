package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.OciComputerInfo;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Repository
public interface OciComputerInfoRepository extends JpaRepository<OciComputerInfo, Long>, JpaSpecificationExecutor<OciComputerInfo> {


    Optional<OciComputerInfo> findByBootIdStr(String bootIdStr);

    @Modifying
    @Query("DELETE FROM OciComputerInfo o WHERE o.bootIdStr IN :bootIds")
    void deleteAllByBootIdStrInBatch(@Param("bootIds") List<String> bootIds);


    /**
     * 根据租户ID、架构和云厂商类型查询最新的一条记录
     */
    Optional<OciComputerInfo> findFirstByTenantIdAndArchitectureAndCloudTypeAndRegionOrderByIdDesc(
            Long tenantId,
            String architecture,
            int cloudType,
            String region
    );

}
