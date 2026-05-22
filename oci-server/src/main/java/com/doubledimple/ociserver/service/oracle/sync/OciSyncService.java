package com.doubledimple.ociserver.service.oracle.sync;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.List;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getAllInstancesByTenant;

/**
 * @version 1.0.0
 * @ClassName OciSyncService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-13 13:30
 */
@Service
@Slf4j
public class OciSyncService {

    @Resource
    private OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OracleInstanceService oracleInstanceService;

    @Transactional
    public void processTenantSync(Tenant tenant) {
        try {
            log.info("开始同步租户[{}]的OCI实例", tenant.getId());

            // 删除该租户的所有实例
            oracleInstanceDetailRepository.deleteByTenantId(tenant.getId());

            // 查询API获取最新实例
            //List<InstanceDetails> instanceDetails = oracleInstanceService.queryInstanceByApis(tenant);

            List<InstanceDetails> instanceDetails = getAllInstancesByTenant(tenant);

            // 过滤掉无效实例
            instanceDetails = instanceDetails.stream()
                    .filter(instance -> instance.getInstanceId() != null)
                    .collect(Collectors.toList());

            if (!instanceDetails.isEmpty()) {
                // 保存新的实例
                oracleInstanceDetailRepository.saveAllAndFlush(instanceDetails);

                // 更新租户同步状态
                tenant.setApiSynced(true);
                tenantRepository.save(tenant);

                log.info("租户[{}]的OCI实例同步完成，同步了{}个实例",
                        tenant.getId(), instanceDetails.size());
            } else {
                log.info("租户[{}]没有有效的OCI实例", tenant.getId());
            }
        } catch (Exception e) {
            log.error("同步租户[{}]的OCI实例时发生错误", tenant.getId(), e);
            throw e;
        }
    }
}
