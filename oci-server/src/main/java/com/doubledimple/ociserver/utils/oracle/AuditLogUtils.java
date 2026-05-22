package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.utils.DateTimeUtils;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.pojo.dto.OciAuditEventDto;
import com.doubledimple.ociserver.pojo.dto.OciPageResult;
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.audit.model.AuditEvent;
import com.oracle.bmc.audit.requests.ListEventsRequest;
import com.oracle.bmc.audit.responses.ListEventsResponse;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static com.doubledimple.ociserver.utils.PingUtil.getGeoInfoByIP;
import static com.doubledimple.ociserver.utils.PingUtil.isPrivateIP;

/**
 * @author doubleDimple
 * @description 查询租户的审计日志（Audit Events）
 * @date 2025/10/31
 */
@Slf4j
@Service
public class AuditLogUtils {


    /**
     * 查询租户在指定时间范围内的审计日志（单页，不循环）
     *
     * @param tenant 租户信息
     * @param startTime ISO8601 格式，如 "2025-10-01T00:00:00Z"
     * @param endTime ISO8601 格式，如 "2025-10-31T23:59:59Z"
     * @param pageToken 分页页码，可为空（从第一页开始）
     * @return 审计事件简化列表 + 下一页 Token
     */
    public OciPageResult<OciAuditEventDto> listAuditEvents(
            Tenant tenant, String startTime, String endTime, String pageToken) {

        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
        List<OciAuditEventDto> results = new ArrayList<>();
        String nextPage = null;

        try (AuditClient auditClient = AuditClient.builder()
                .clientConfigurator(ProxyContext.get()).build(provider)) {
            String compartmentId = provider.getTenantId();
            ListEventsRequest.Builder builder = ListEventsRequest.builder()
                    .compartmentId(compartmentId)
                    .startTime(Date.from(Instant.parse(startTime)))
                    .endTime(Date.from(Instant.parse(endTime)));

            if (pageToken != null && !pageToken.isEmpty()) {
                builder.page(pageToken);
            }

            ListEventsResponse response = auditClient.listEvents(builder.build());
            nextPage = response.getOpcNextPage();

            for (AuditEvent event : response.getItems()) {
                if (event.getData() != null && event.getData().getIdentity() != null) {
                    String userName = event.getData().getIdentity().getPrincipalName();
                    if (userName != null && userName.length() > 35) {
                        userName = userName.substring(0, 35) + "...";
                    }

                    String userType = event.getData().getIdentity().getAuthType();
                    String ipAddress = event.getData().getIdentity().getIpAddress();

                    // 拼接 IP + 地址信息
                    String resolvedIpInfo = resolveMultiIpLocation(ipAddress);

                    String clientEnv = event.getData().getIdentity().getUserAgent();
                    String eventType = event.getEventType();
                    String eventTime = event.getEventTime() != null
                            ? DateTimeUtils.formatDate(event.getEventTime())
                            : "-";
                    String responseStatus = (event.getData().getResponse() != null)
                            ? event.getData().getResponse().getStatus()
                            : "-";

                    results.add(new OciAuditEventDto(
                            eventType, userName, userType, resolvedIpInfo, clientEnv, eventTime, responseStatus));
                }
            }

            log.debug("租户 [{}] 审计日志获取成功，共 {} 条，下一页：{}",
                    tenant.getUserName(), results.size(), nextPage);

        } catch (BmcException e) {
            log.warn("查询审计日志失败: 状态码={}, 错误={}", e.getStatusCode(), e.getMessage());
        } catch (Exception e) {
            log.error("查询审计日志异常: {}", e.getMessage());
        }

        return new OciPageResult<>(results, nextPage);
    }


    /**
     * 查询过去 N 天（最大 90 天）到当前时间的审计日志（单页分页模式）
     */
    public OciPageResult<OciAuditEventDto> listRecentAuditEvents(
            Tenant tenant, int days, String pageToken) {
        if (days <= 0) days = 1;
        else if (days > 90) days = 90;

        ZonedDateTime nowUtc = ZonedDateTime.now(ZoneOffset.UTC);
        ZonedDateTime startUtc = nowUtc.minusDays(days);

        String startTime = startUtc.toInstant().toString();
        String endTime = nowUtc.toInstant().toString();

        log.info("查询过去 {} 天的日志范围: {} → {}", days, startTime, endTime);
        return listAuditEvents(tenant, startTime, endTime, pageToken);
    }

    /**
     * 查询指定日期范围内的审计日志（最多90天）
     * @param tenant 租户信息
     * @param startDate yyyy-MM-dd
     * @param endDate yyyy-MM-dd，可为空（为空时=开始日期当天）
     */
    public OciPageResult<OciAuditEventDto> listAuditEventsByDateRange(
            Tenant tenant, String startDate, String endDate, String pageToken) {

        try {
            LocalDate start = LocalDate.parse(startDate);
            LocalDate end = (endDate != null && !endDate.isEmpty())
                    ? LocalDate.parse(endDate)
                    : start;

            long diffDays = ChronoUnit.DAYS.between(start, end);
            if (diffDays < 0) {
                throw new IllegalArgumentException("结束日期不能早于开始日期");
            }
            if (diffDays > 90) {
                throw new IllegalArgumentException("日期范围不能超过90天");
            }

            ZonedDateTime startUtc = start.atStartOfDay(ZoneOffset.UTC);
            ZonedDateTime endUtc = end.plusDays(1).atStartOfDay(ZoneOffset.UTC).minusSeconds(1);

            String startTime = startUtc.toInstant().toString();
            String endTime = endUtc.toInstant().toString();

            log.debug("查询租户 [{}] 日期范围 {} → {} 的审计日志", tenant.getUserName(), startTime, endTime);
            return listAuditEvents(tenant, startTime, endTime, pageToken);

        } catch (Exception e) {
            log.error("日期范围查询失败: {} → {}, 错误: {}", startDate, endDate, e.getMessage());
            return new OciPageResult<>(Collections.emptyList(), null);
        }
    }

    /**
     * 根据多个 IP 获取拼接的地理位置字符串
     * 示例输入: "10.0.2.9,252.49.125.199"
     * 示例输出: "10.0.2.9(内网地址)，252.49.125.199(中国广东省深圳市)"
     */
    private String resolveMultiIpLocation(String ipAddress) {
        if (ipAddress == null || ipAddress.trim().isEmpty()) {
            return "-";
        }

        String[] ipList = ipAddress.split(",");
        List<String> resolvedList = new ArrayList<>();

        for (String ip : ipList) {
            ip = ip.trim();
            if (ip.isEmpty()) continue;

            String location;
            if (isPrivateIP(ip)) {
                location = "内网地址";
            } else {
                try {
                    location = getGeoInfoByIP(ip);
                } catch (Exception e) {
                    location = "未知";
                }
            }
            resolvedList.add(ip + "(" + location + ")");
        }

        return String.join("，", resolvedList); // 中文逗号分隔
    }

}
