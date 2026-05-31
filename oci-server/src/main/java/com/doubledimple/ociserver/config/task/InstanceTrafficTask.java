package com.doubledimple.ociserver.config.task;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.entity.TrafficAlert;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.TrafficAlertRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.enums.oci.TrafficPeriod;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.response.TenantTrafficStats;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.doubledimple.ociserver.utils.oracle.TrafficMetricsUtils;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicManagementUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.monitoring.MonitoringClient;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.time.LocalDateTime;
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

    private static final double BYTES_PER_GB = 1024.0 * 1024.0 * 1024.0;

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
     * 查询单个租户本月流量统计（不触发告警，仅返回数据）
     * 供外部调用，例如 TG 菜单查询
     */
    public TenantTrafficStats queryTenantTraffic(Tenant tenant) {
        TenantTrafficStats stats = new TenantTrafficStats();
        stats.setTenantId(tenant.getId());
        stats.setTenancy(tenant.getTenancy());
        stats.setTenancyName(tenant.getTenancyName());
        stats.setDisplayName(resolveDisplayName(tenant));
        stats.setRegion(tenant.getRegion());

        Optional<TrafficAlert> alertOpt = trafficAlertRepository.findByTenantId(tenant.getId());
        alertOpt.ifPresent(alert -> {
            stats.setThresholdGB(alert.getThreshold());
            stats.setStatisticsEnabled(alert.getStatisticsEnabled());
            stats.setAutoShutdown(alert.getAutoShutdown());
        });

        try {
            ZonedDateTime startUtc = ZonedDateTime.now(ZoneOffset.UTC)
                    .withDayOfMonth(1)
                    .toLocalDate()
                    .atStartOfDay(ZoneOffset.UTC);
            ZonedDateTime endUtc = ZonedDateTime.now(ZoneOffset.UTC);
            stats.setStartTime(startUtc.toLocalDateTime());
            stats.setEndTime(endUtc.toLocalDateTime());

            Date startTime = Date.from(startUtc.toInstant());
            Date endTime = Date.from(endUtc.toInstant());

            List<VnicCreationResult> allVnics = VnicManagementUtils.listAllVnicsForTenant(tenant);
            if (allVnics == null || allVnics.isEmpty()) {
                stats.setMessage("该区域暂无 VNIC，无流量可统计");
                return stats;
            }

            Map<String, List<VnicCreationResult>> vnicsByInstance = allVnics.stream()
                    .filter(v -> v != null && v.getVnicId() != null && !v.getVnicId().trim().isEmpty())
                    .collect(Collectors.groupingBy(
                            VnicCreationResult::getInstanceId,
                            LinkedHashMap::new,
                            Collectors.toList()));

            SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
            String compartmentId = provider.getTenantId();

            double totalTenantEgress = 0D;
            try (MonitoringClient monitoringClient = TrafficMetricsUtils.buildClient(provider)) {
                for (Map.Entry<String, List<VnicCreationResult>> entry : vnicsByInstance.entrySet()) {
                    String instanceId = entry.getKey();
                    List<VnicCreationResult> uniqueVnics = entry.getValue().stream()
                            .collect(Collectors.collectingAndThen(
                                    Collectors.toMap(
                                            VnicCreationResult::getVnicId,
                                            v -> v,
                                            (existing, replacement) -> existing,
                                            LinkedHashMap::new),
                                    map -> new ArrayList<>(map.values())));

                    if (uniqueVnics.isEmpty()) {
                        continue;
                    }

                    double instanceEgressBytes = TrafficMetricsUtils.getInstanceTrafficTotal(
                            monitoringClient,
                            compartmentId,
                            uniqueVnics,
                            true,
                            startTime,
                            endTime,
                            TrafficPeriod.ONE_DAY);

                    TenantTrafficStats.InstanceTraffic info = new TenantTrafficStats.InstanceTraffic();
                    info.setInstanceId(instanceId);
                    info.setInstanceName(uniqueVnics.get(0).getInstanceName());
                    info.setPublicIp(uniqueVnics.get(0).getPublicIp());
                    info.setVnicCount(uniqueVnics.size());
                    info.setEgressGB(instanceEgressBytes / BYTES_PER_GB);
                    stats.getInstances().add(info);

                    totalTenantEgress += instanceEgressBytes;
                }
            }

            stats.setTotalEgressGB(totalTenantEgress / BYTES_PER_GB);
        } catch (Exception e) {
            log.error("查询租户 [{}] 流量失败: {}", tenant.getTenancy(), e.getMessage(), e);
            stats.setSuccess(false);
            stats.setMessage(e.getMessage());
        }
        return stats;
    }

    /**
     * 检查单个租户流量情况
     */
    private void checkTrafficForTenant(Tenant tenant, TrafficAlert alert) {
        TenantTrafficStats stats = queryTenantTraffic(tenant);
        if (!stats.isSuccess() || stats.getInstances().isEmpty()) {
            return;
        }

        double totalGB = stats.getTotalEgressGB();
        double threshold = alert.getThreshold() != null ? alert.getThreshold() : Double.MAX_VALUE;

        if (totalGB > threshold) {
            log.warn("租户 [{}] 本月出站流量超限：{} GB / 阈值 {} GB",
                    tenant.getTenancy(), totalGB, threshold);

            TenantTrafficStats.InstanceTraffic first = stats.getInstances().get(0);
            String publicIp = first.getPublicIp();

            boolean shutdown = alert.getAutoShutdown();
            if (shutdown) {
                oracleInstanceService.stopInstance(first.getInstanceId(), tenant.getTenancy());
                log.info("租户 [{}] 实例 [{}] 已自动关机，超出阈值 {} GB",
                        tenant.getTenancy(), first.getInstanceName(), threshold);
            }

            sendAlert(tenant, publicIp, totalGB, threshold, totalGB - threshold, shutdown);
        }
    }

    private String resolveDisplayName(Tenant tenant) {
        String defName = tenant.getDefName();
        if (StringUtils.isBlank(defName) || "未设置".equals(defName)) {
            return tenant.getTenancyName();
        }
        return defName;
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
