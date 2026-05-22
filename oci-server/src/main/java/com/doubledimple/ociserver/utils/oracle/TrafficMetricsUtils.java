package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.oci.TrafficPeriod;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.monitoring.MonitoringClient;
import com.oracle.bmc.monitoring.model.AggregatedDatapoint;
import com.oracle.bmc.monitoring.model.MetricData;
import com.oracle.bmc.monitoring.model.SummarizeMetricsDataDetails;
import com.oracle.bmc.monitoring.requests.SummarizeMetricsDataRequest;
import com.oracle.bmc.monitoring.responses.SummarizeMetricsDataResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * OCI 实例流量查询工具类
 * 支持按 VNIC / 实例 / 时间范围 查询出站和入站流量
 * 返回单位：Byte
 */
/**
 * OCI 实例流量查询工具类（可选粒度）
 * 支持按 VNIC / 实例 / 时间范围 / 粒度 查询出站和入站流量
 * 返回单位：Byte
 */
/**
 * OCI 实例流量查询工具类（支持粒度枚举）
 */
@Slf4j
public class TrafficMetricsUtils {

    /**
     * 查询单个 VNIC 在时间区间内的流量总量
     */
    public static double getVnicTrafficTotal(MonitoringClient client,
                                             String compartmentId,
                                             String vnicId,
                                             boolean egress,
                                             Date startTime,
                                             Date endTime,
                                             TrafficPeriod period) {
        try {
            String metric = egress ? "VnicToNetworkBytes" : "VnicFromNetworkBytes";
            String query = String.format("%s[%s]{resourceId = \"%s\"}.sum()", metric, period.getValue(), vnicId);

            SummarizeMetricsDataDetails details = SummarizeMetricsDataDetails.builder()
                    .namespace("oci_vcn")
                    .query(query)
                    .startTime(startTime)
                    .endTime(endTime)
                    .build();

            SummarizeMetricsDataRequest request = SummarizeMetricsDataRequest.builder()
                    .compartmentId(compartmentId)
                    .summarizeMetricsDataDetails(details)
                    .build();

            SummarizeMetricsDataResponse response = client.summarizeMetricsData(request);
            double total = 0D;
            for (MetricData item : response.getItems()) {
                for (AggregatedDatapoint dp : item.getAggregatedDatapoints()) {
                    total += dp.getValue();
                }
            }
            return total;
        } catch (Exception e) {
            log.warn("❌ 查询 VNIC [{}] {} 流量失败: {}", vnicId, egress ? "出站" : "入站", e.getMessage());
            return 0D;
        }
    }

    /**
     * 查询实例下所有 VNIC 的总流量
     */
    public static double getInstanceTrafficTotal(Tenant tenant,
                                                 List<VnicCreationResult> vnics,
                                                 boolean egress,
                                                 Date startTime,
                                                 Date endTime,
                                                 TrafficPeriod period) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        double total = 0D;
        try (MonitoringClient client = MonitoringClient.builder().build(provider)) {
            for (VnicCreationResult vnic : vnics) {
                total += getVnicTrafficTotal(client, provider.getTenantId(), vnic.getVnicId(), egress, startTime, endTime, period);
            }
        }
        return total;
    }

    /**
     * 📅 按粒度聚合：查询单个 VNIC 每个时间片的流量（如按天 / 小时）
     */
    public static Map<LocalDateTime, Double> getVnicTrafficByPeriod(MonitoringClient client,
                                                                    String compartmentId,
                                                                    String vnicId,
                                                                    boolean egress,
                                                                    Date startTime,
                                                                    Date endTime,
                                                                    TrafficPeriod period) {
        Map<LocalDateTime, Double> result = new LinkedHashMap<>();
        try {
            String metric = egress ? "VnicToNetworkBytes" : "VnicFromNetworkBytes";
            String query = String.format("%s[%s]{resourceId = \"%s\"}.sum()", metric, period.getValue(), vnicId);

            SummarizeMetricsDataDetails details = SummarizeMetricsDataDetails.builder()
                    .namespace("oci_vcn")
                    .query(query)
                    .startTime(startTime)
                    .endTime(endTime)
                    .build();

            SummarizeMetricsDataRequest request = SummarizeMetricsDataRequest.builder()
                    .compartmentId(compartmentId)
                    .summarizeMetricsDataDetails(details)
                    .build();

            SummarizeMetricsDataResponse response = client.summarizeMetricsData(request);

            for (MetricData item : response.getItems()) {
                for (AggregatedDatapoint dp : item.getAggregatedDatapoints()) {
                    LocalDateTime time = dp.getTimestamp().toInstant().atZone(ZoneOffset.UTC).toLocalDateTime();
                    result.merge(time, dp.getValue(), Double::sum);
                }
            }
        } catch (Exception e) {
            log.warn("❌ 查询 VNIC [{}] {} {} 粒度流量失败: {}", vnicId, egress ? "出站" : "入站", period.getValue(), e.getMessage());
        }
        return result;
    }

    /**
     * 📊 按粒度聚合：查询整个实例（多个 VNIC）的流量
     */
    public static Map<LocalDateTime, Double> getInstanceTrafficByPeriod(Tenant tenant,
                                                                        List<String> vnicIdList,
                                                                        boolean egress,
                                                                        Date startTime,
                                                                        Date endTime,
                                                                        TrafficPeriod period,
                                                                        String compartmentId) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        Map<LocalDateTime, Double> totalMap = new LinkedHashMap<>();
        try (MonitoringClient client = MonitoringClient.builder().build(provider)) {
            if (StringUtils.isBlank(compartmentId)){
                compartmentId = provider.getTenantId();
            }
            for (String vnicId : vnicIdList) {
                Map<LocalDateTime, Double> vnicMap =
                        getVnicTrafficByPeriod(client, compartmentId, vnicId, egress, startTime, endTime, period);
                for (Map.Entry<LocalDateTime, Double> entry : vnicMap.entrySet()) {
                    totalMap.merge(entry.getKey(), entry.getValue(), Double::sum);
                }
            }
        } catch (Exception e) {
            log.warn("❌ 查询实例 {} {} 粒度流量失败: {}", tenant.getTenancyName(), period.getValue(), e.getMessage());
        }
        return totalMap;
    }
}
