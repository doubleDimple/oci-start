package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.BootInstance;
import com.doubledimple.dao.repository.BootInstanceRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.doubledimple.ociserver.pojo.response.DashboardStats;
import com.doubledimple.ociserver.service.BootTotalInstanceService;
import com.doubledimple.ociserver.config.task.CreateInstanceTaskV2;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.Optional;

/**
 * @author doubleDimple
 * @date 2024:10:22日 22:44
 */
@Service
@Slf4j
public class BootTotalInstanceServiceImpl implements BootTotalInstanceService {


    @Resource
    BootInstanceRepository bootInstanceRepository;

    @Resource
    TenantRepository tenantRepository;

    /*@Resource
    TaskRepository taskRepository;*/

    @Resource
    CreateInstanceTaskV2 createInstanceTaskV2;

    @Transactional
    @Override
    public long inc(User user) {
        try {
            // 获取更新后的计数
            BootInstance bootInstance = bootInstanceRepository.findById(user.getBootId()) .orElseThrow(() -> new RuntimeException("Boot instance not found"));
            long addCount = bootInstance.getAddCount();
            bootInstance.setAddCount(addCount + 1);
            bootInstance.incrementAttemptCount();
            bootInstanceRepository.save(bootInstance);
            return bootInstance.getAddCount();
        }
        catch (Exception e) {
            return 1L;
        }
    }

    @Transactional
    @Override
    public void updatePublicIp(Long bootId, int status, String publicIp) {
        Optional<BootInstance> instanceOpt = bootInstanceRepository.findById(bootId);
        if (instanceOpt.isPresent()) {
            BootInstance instance = instanceOpt.get();
            instance.setStatus(status);
            instance.setPublicIp(publicIp);
            instance.setSuccessCount((instance.getSuccessCount()) + 1);
            bootInstanceRepository.save(instance);
        }
    }

    @Override
    public DashboardStats count() {
        DashboardStats dashboardStats = new DashboardStats();
        try  {
            // 获取API调用数
            Long apiCount = tenantRepository.queryDistinctByTenantId();
            dashboardStats.setTotalApiCalls(apiCount == null ? 0L : apiCount);

            // 获取总Boot实例数（通过统计不同的bootId数量）
            Long totalBoot = bootInstanceRepository.count();
            dashboardStats.setTotalBootInstances(totalBoot);

            // 获取总抢机次数
            long totalAttempts = bootInstanceRepository.sumAddCount();
            dashboardStats.setTotalAttempts(totalAttempts);

            // 获取成功次数
            long successfulAttempts = bootInstanceRepository.sumSuccessCount();
            dashboardStats.setSuccessfulAttempts(successfulAttempts);

            //获取失败次数
            long failCounts =  bootInstanceRepository.sumFailCount();
            dashboardStats.setFailCounts(failCounts);

            // 计算成功率(转换为百分比整数)
            if (totalAttempts == 0 || successfulAttempts == 0) {
                dashboardStats.setSuccessRate(0L);
            } else {
                long rate = (successfulAttempts * 100) / totalAttempts;
                dashboardStats.setSuccessRate(rate);
            }
        } catch (Exception e) {
            log.error("Failed to get dashboard stats", e);
            // 发生错误时返回空统计
            dashboardStats.setTotalApiCalls(0L);
            dashboardStats.setTotalBootInstances(0L);
            dashboardStats.setTotalAttempts(0L);
            dashboardStats.setSuccessfulAttempts(0L);
            dashboardStats.setSuccessRate(0L);
        }
        return dashboardStats;
    }

    @Override
    public Long queryAddCountByBootId(Long bootId) {
        return bootInstanceRepository.findById(bootId)
                .map(BootInstance::getAddCount)
                .orElse(0L);
    }

    /**
    * 根据bootId查询配置的抢机实例记录
    */
    @Override
    public BootInstance queryBootInstanceById(String bootId) {
        return bootInstanceRepository.queryBootInstanceById(bootId);
    }
}
