package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.InstanceDetails;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.util.List;
import java.util.Optional;

/** Only non-secret columns enter the network-quality module. */
public interface NetworkQualityInstanceRepository extends JpaRepository<InstanceDetails, Long> {
    @Query("select i.id as id, i.displayName as displayName, i.publicIps as publicIps, " +
            "i.cloudType as cloudType, i.monitorInstalled as monitorInstalled, " +
            "t.tenancyName as tenancyName, t.region as regionName " +
            "from InstanceDetails i left join Tenant t on t.id=i.tenantId order by i.id")
    List<AgentInstance> listAgents(Pageable pageable);
    @Query("select i.id from InstanceDetails i where i.id in :ids")
    List<Long> existingIds(@Param("ids") List<Long> ids);
    @Query("select i.monitorInstalled from InstanceDetails i where i.id=:id")
    Optional<Boolean> installationState(@Param("id") Long id);
    interface AgentInstance {
        Long getId(); String getDisplayName(); String getPublicIps(); Integer getCloudType();
        Boolean getMonitorInstalled(); String getTenancyName(); String getRegionName();
    }
}
