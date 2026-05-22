package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.monitor.MonitorAlert;
import com.doubledimple.ocicommon.param.monitor.MonitorReportDTO;
import com.doubledimple.ocimonitor.service.MonitorCoreService;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.AlertService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.Optional;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_RESOURCE_ALARM_TEMPLATE;

/**
 * @version 1.0.0
 * @ClassName AlertServiceImpl
 * @Description 告警异步通知
 * @Author doubleDImple
 * @Date 2026-02-06 17:29
 */
@Service
@Slf4j
public class AlertServiceImpl implements AlertService {

    @Resource
    private OracleInstanceDetailRepository instanceRepository;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    @Lazy
    private MonitorCoreService monitorCoreService;

    @Resource
    MessageFactory messageFactory;


    @Async("taskExecutor")
    @Override
    public void sendAlertAsync(MonitorReportDTO reportDto) {
        ApiResponse apiResponse = monitorCoreService.processReportData(reportDto);
        MonitorAlert alert = (MonitorAlert)apiResponse.getData();
        if (alert == null) return;
        try {
            log.info("开始异步处理告警: {}", alert.getType());
            InstanceDetails instance = instanceRepository.findByInstanceId(alert.getInstanceId());
            if (instance == null) return;
            Optional<Tenant> optional = tenantRepository.findById(instance.getTenantId());
            if (!optional.isPresent()) return;
            Tenant tenant = optional.get();
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(String.format(MESSAGE_RESOURCE_ALARM_TEMPLATE,tenant.getDefName(), RegionEnum.getNameSimple(tenant.getRegion()),instance.getPublicIps(),alert.getMessage()));
        } catch (Exception e) {
            log.error("告警发送失败", e);
        }
    }
}
