package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TrafficAlert;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.TrafficAlertRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.enums.oci.TrafficPeriod;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.doubledimple.ociserver.utils.oracle.TrafficMetricsUtils;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicManagementUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.monitoring.MonitoringClient;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_TRAFFIC_EXCEED_SHUTDOWN_TEMPLATE;

/**
 * 实例流量实时预警任务（无落库版本）
 * 每次定时任务触发时，直接调用 OCI Monitoring 实时查询
 */
@Component
@Slf4j
public class InstanceTrafficTask {
    @Resource
    private TenantRepository tenantRepository;
    @Resource
    private OracleInstanceService oracleInstanceService;
    @Resource
    private TrafficAlertRepository trafficAlertRepository;
    @Resource
    private MessageFactory messageFactory;

    /** 单轮最长时间预算，超出后提前结束，避免拖到下一轮触发（间隔 30 分钟） */
    private static final long RUN_BUDGET_MS = 25 * 60 * 1000L;

    /**
     * 定时任务入口
     * 每次执行都实时查询 OCI Monitoring
     */
    public void updateInstanceTraffic() {
        log.debug("[流量预警] 开始执行实时任务...");
        List<Tenant> tenants = tenantRepository.findAll();

        long deadline = System.currentTimeMillis() + RUN_BUDGET_MS;
        for (Tenant tenant : tenants) {
            if (System.currentTimeMillis() > deadline) {
                log.warn("[流量预警] 本轮已超时间预算 {} 分钟，提前结束，剩余租户下轮处理", RUN_BUDGET_MS / 60000);
                break;
            }
            Optional<TrafficAlert> alertOpt = trafficAlertRepository.findByTenantId(tenant.getId());
            if (alertOpt.isPresent() && alertOpt.get().getStatisticsEnabled()) {
                try {
                    checkTrafficForTenant(tenant, alertOpt.get());
                } catch (Exception e) {
                    log.error("租户 [{}] 实时统计失败: {}", tenant.getTenancy(), e.getMessage(), e);
                }
            }
        }
    }

    /**
     * 检查单个租户流量情况
     */
    private void checkTrafficForTenant(Tenant tenant, TrafficAlert alert) {
        // 1. 获取本月 UTC 起止时间
        ZonedDateTime startUtc = ZonedDateTime.now(ZoneOffset.UTC)
                .withDayOfMonth(1)
                .toLocalDate()
                .atStartOfDay(ZoneOffset.UTC);
        ZonedDateTime endUtc = ZonedDateTime.now(ZoneOffset.UTC);
        Date startTime = Date.from(startUtc.toInstant());
        Date endTime = Date.from(endUtc.toInstant());

        double totalTenantEgress = 0D;

        // 2. 直接查询所有 VNIC（已包含实例信息）
        List<VnicCreationResult> allVnics = VnicManagementUtils.listAllVnicsForTenant(tenant);

        if (allVnics.isEmpty()) {
            log.warn("租户 [{}] 未找到任何 VNIC，跳过流量统计", tenant.getTenancy());
            return;
        }

        // 3. 根据 instanceId 分组统计
        Map<String, List<VnicCreationResult>> vnicsByInstance = allVnics.stream()
                .filter(v -> v != null && v.getVnicId() != null && !v.getVnicId().trim().isEmpty())
                .collect(Collectors.groupingBy(VnicCreationResult::getInstanceId, LinkedHashMap::new, Collectors.toList()));

        // 4. 复用同一个 MonitoringClient（带超时）查询每个实例的出站流量
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        String compartmentId = provider.getTenantId();
        try (MonitoringClient monitoringClient = TrafficMetricsUtils.buildClient(provider)) {
            for (Map.Entry<String, List<VnicCreationResult>> entry : vnicsByInstance.entrySet()) {
                String instanceId = entry.getKey();
                List<VnicCreationResult> vnics = entry.getValue();

                if (vnics.isEmpty()) {
                    log.warn("租户 [{}] 实例 [{}] 未找到有效 VNIC ID", tenant.getTenancy(), instanceId);
                    continue;
                }

                // 去重（如果有重复 VNIC ID）
                List<VnicCreationResult> uniqueVnics = vnics.stream()
                        .collect(Collectors.collectingAndThen(
                                Collectors.toMap(
                                        VnicCreationResult::getVnicId,
                                        v -> v,
                                        (existing, replacement) -> existing,
                                        LinkedHashMap::new
                                ),
                                map -> new ArrayList<>(map.values())
                        ));

                double instanceEgress = TrafficMetricsUtils.getInstanceTrafficTotal(
                        monitoringClient,
                        compartmentId,
                        uniqueVnics,
                        true,
                        startTime,
                        endTime,
                        TrafficPeriod.ONE_DAY
                );

                String instanceName = uniqueVnics.get(0).getInstanceName();
                log.debug("租户 [{}] 实例 [{}] VNIC 数:{} 出站流量:{} bytes",
                        tenant.getTenancy(), instanceName, uniqueVnics.size(), instanceEgress);

                totalTenantEgress += instanceEgress;
            }
        }

        // 5. 判断是否超过阈值
        double totalGB = totalTenantEgress / (1024.0 * 1024.0 * 1024.0);
        double threshold = alert.getThreshold() != null ? alert.getThreshold() : Double.MAX_VALUE;

        if (totalGB > threshold) {
            log.warn("租户 [{}] 本月出站流量超限：{} GB / 阈值 {} GB",
                    tenant.getTenancy(), totalGB, threshold);

            // 6. 取第一个 VNIC 的实例信息
            VnicCreationResult first = allVnics.get(0);
            String publicIp = first.getPublicIp();

            // 7. 是否自动关机
            boolean shutdown = alert.getAutoShutdown();
            if (shutdown) {
                oracleInstanceService.stopInstance(first.getInstanceId(), tenant.getTenancy());
                log.info("租户 [{}] 实例 [{}] 已自动关机，超出阈值 {} GB",
                        tenant.getTenancy(), first.getInstanceName(), threshold);
            }

            // 8. 发送告警
            sendAlert(tenant, publicIp, totalGB, threshold, totalGB - threshold, shutdown);
        }
    }



    /**
     * 发送流量告警消息
     */
    private void sendAlert(Tenant tenant, String ip, double totalGB, double threshold, double over, boolean shutdown) {
        String message = shutdown
                ? String.format(MESSAGE_TRAFFIC_EXCEED_SHUTDOWN_TEMPLATE,
                tenant.getTenancyName(),
                RegionEnum.getNameByCode(tenant.getRegion()),
                ip, "出站", totalGB, threshold, over)
                : String.format(MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE,
                tenant.getTenancyName(),
                RegionEnum.getNameByCode(tenant.getRegion()),
                ip, "出站", totalGB, threshold, over);

        log.warn("流量超限告警：{}", message);
        messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(message);
    }
}
