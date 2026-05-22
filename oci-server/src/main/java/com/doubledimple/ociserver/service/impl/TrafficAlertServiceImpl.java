package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TrafficAlert;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.TrafficAlertRepository;
import com.doubledimple.ociserver.pojo.request.TrafficAlertDTO;
import com.doubledimple.ociserver.service.TrafficAlertService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.Optional;
import java.util.concurrent.ThreadPoolExecutor;

import static com.doubledimple.ociserver.utils.oracle.OciCliUtils.createVcnAndFlowLogs;

/**
 * @version 1.0.0
 * @ClassName TrafficAlertImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-13 14:04
 */
@Service
@Slf4j
public class TrafficAlertServiceImpl implements TrafficAlertService {


    @Resource
    private TrafficAlertRepository trafficAlertRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private ThreadPoolExecutor threadPoolExecutor;

    /**
     * 获取指定租户的流量预警配置
     */
    @Override
    public TrafficAlertDTO getTrafficAlert(Long tenantId) {
        Optional<TrafficAlert> alertOpt = trafficAlertRepository.findByTenantId(tenantId);
        if (alertOpt.isPresent()) {
            TrafficAlert alert = alertOpt.get();
            TrafficAlertDTO dto = new TrafficAlertDTO();
            dto.setTenantId(alert.getTenantId());
            dto.setThreshold(alert.getThreshold());
            dto.setAutoShutdown(alert.getAutoShutdown());
            dto.setStatisticsEnabled(alert.getStatisticsEnabled());

            return dto;
        }
        return null;
    }

    /**
     * 保存或更新流量预警配置
     */
    @Override
    @Transactional
    public TrafficAlert saveTrafficAlert(TrafficAlertDTO dto) {
        if (dto == null) {
            throw new IllegalArgumentException("流量预警配置不能为空");
        }
        if (dto.getTenantId() == null) {
            throw new IllegalArgumentException("租户ID不能为空");
        }
        // 阈值必须 > 0，避免把 0/空值落库后下次加载显示为空被误以为"自动清空"
        if (dto.getThreshold() == null || dto.getThreshold() <= 0) {
            throw new IllegalArgumentException("流量阈值必须大于 0");
        }
        Optional<Tenant> byId = tenantRepository.findById(dto.getTenantId());
        if (!byId.isPresent()){
            throw new IllegalArgumentException("信息不存在");
        }
        Tenant tenant = byId.get();
        String tenancy = tenant.getTenancy();
        Optional<TrafficAlert> existingAlert = trafficAlertRepository.findByTenantId(dto.getTenantId());
        TrafficAlert alert = existingAlert.orElseGet(() -> {
            TrafficAlert a = new TrafficAlert();
            a.setTenantId(dto.getTenantId());
            return a;
        });

        alert.setStatisticsEnabled(Boolean.TRUE.equals(dto.getStatisticsEnabled()));
        alert.setThreshold(dto.getThreshold());
        alert.setAutoShutdown(Boolean.TRUE.equals(dto.getAutoShutdown()));
        alert.setTenancy(tenancy);
        alert.setEnabled(false);
        TrafficAlert save = trafficAlertRepository.save(alert);
        threadPoolExecutor.execute(() ->createVcnAndFlowLogs(tenant));
        return save;
    }

    /**
     * 检查租户是否已配置流量预警
     */
    public boolean hasTrafficAlert(Long tenantId) {
        return trafficAlertRepository.existsByTenantId(tenantId);
    }

    /**
     * 删除流量预警配置
     */

    @Override
    @Transactional
    public void deleteTrafficAlert(Long tenantId) {
        Optional<TrafficAlert> alert = trafficAlertRepository.findByTenantId(tenantId);
        alert.ifPresent(trafficAlertRepository::delete);
    }
}
