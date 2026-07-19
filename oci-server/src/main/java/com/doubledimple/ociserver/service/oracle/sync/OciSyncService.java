package com.doubledimple.ociserver.service.oracle.sync;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.service.cloud.CloudInstanceServiceFactory;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;

/**
 * 租户实例同步（队列消费）。按 cloudType 分发到 CloudInstanceService。
 */
@Service
@Slf4j
public class OciSyncService {

    @Resource
    private CloudInstanceServiceFactory cloudInstanceServiceFactory;

    @Transactional
    public void processTenantSync(Tenant tenant) {
        try {
            log.info("开始同步租户[{}]实例, cloudType={}", tenant.getId(), tenant.getCloudType());
            if (!cloudInstanceServiceFactory.supports(tenant.getCloudType())) {
                log.warn("租户[{}] cloudType={} 无实例同步实现，跳过", tenant.getId(), tenant.getCloudType());
                return;
            }
            cloudInstanceServiceFactory.get(tenant.getCloudType()).syncToLocal(tenant);
            log.info("租户[{}]实例同步完成", tenant.getId());
        } catch (Exception e) {
            log.error("同步租户[{}]实例时发生错误", tenant.getId(), e);
            throw e;
        }
    }
}
