package com.doubledimple.ociserver.utils.oracle;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.model.Subnet;
import com.oracle.bmc.core.model.Vcn;
import com.oracle.bmc.core.requests.GetSubnetRequest;
import com.oracle.bmc.core.requests.GetVnicRequest;
import com.oracle.bmc.core.requests.ListInstancesRequest;
import com.oracle.bmc.core.requests.ListSubnetsRequest;
import com.oracle.bmc.core.requests.ListVnicAttachmentsRequest;
import com.oracle.bmc.core.responses.GetSubnetResponse;
import com.oracle.bmc.core.responses.GetVnicResponse;
import com.oracle.bmc.core.responses.ListInstancesResponse;
import com.oracle.bmc.core.responses.ListSubnetsResponse;
import com.oracle.bmc.core.responses.ListVnicAttachmentsResponse;
import com.oracle.bmc.logging.LoggingManagementClient;
import com.oracle.bmc.logging.model.Archiving;
import com.oracle.bmc.logging.model.Configuration;
import com.oracle.bmc.logging.model.CreateLogDetails;
import com.oracle.bmc.logging.model.CreateLogGroupDetails;
import com.oracle.bmc.logging.model.Log;
import com.oracle.bmc.logging.model.LogGroup;
import com.oracle.bmc.logging.model.LogGroupLifecycleState;
import com.oracle.bmc.logging.model.LogGroupSummary;
import com.oracle.bmc.logging.model.LogLifecycleState;
import com.oracle.bmc.logging.model.LogSummary;
import com.oracle.bmc.logging.model.OciService;
import com.oracle.bmc.logging.requests.CreateLogGroupRequest;
import com.oracle.bmc.logging.requests.CreateLogRequest;
import com.oracle.bmc.logging.requests.GetLogGroupRequest;
import com.oracle.bmc.logging.requests.GetLogRequest;
import com.oracle.bmc.logging.requests.ListLogGroupsRequest;
import com.oracle.bmc.logging.requests.ListLogsRequest;
import com.oracle.bmc.logging.responses.CreateLogGroupResponse;
import com.oracle.bmc.logging.responses.CreateLogResponse;
import com.oracle.bmc.logging.responses.GetLogGroupResponse;
import com.oracle.bmc.logging.responses.GetLogResponse;
import com.oracle.bmc.logging.responses.ListLogGroupsResponse;
import com.oracle.bmc.logging.responses.ListLogsResponse;
import com.oracle.bmc.loggingsearch.LogSearchClient;
import com.oracle.bmc.loggingsearch.model.SearchLogsDetails;
import com.oracle.bmc.loggingsearch.model.SearchResponse;
import com.oracle.bmc.loggingsearch.model.SearchResult;
import com.oracle.bmc.loggingsearch.model.SearchResultSummary;
import com.oracle.bmc.loggingsearch.requests.SearchLogsRequest;
import com.oracle.bmc.loggingsearch.responses.SearchLogsResponse;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * @version 1.0.0
 * @ClassName VCNFlowLogsUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-28 22:43
 */
@Slf4j
public class VCNFlowLogsUtils {

    private static final int DEFAULT_TIMEOUT_SECONDS = 300; // 5分钟超时
    private static final int DEFAULT_QUERY_HOURS = 1; // 默认查询1小时
    private static final int MAX_QUERY_HOURS = 24; // 最大查询24小时


    /**
     * 流量统计数据模型
     */
    @Data
    public static class FlowLogsTrafficStats {
        private String instanceId;
        private String privateIP;
        private String publicIP;
        private Instant startTime;
        private Instant endTime;
        private Long totalInboundBytes;
        private Long totalOutboundBytes;
        private Long totalInboundPackets;
        private Long totalOutboundPackets;
        private Long totalFlow;
        private List<FlowLogsDataPoint> dataPoints;
        private String queryDuration;

        // 构造函数
        public FlowLogsTrafficStats() {}
    }

    /**
     * 流量数据点模型
     */
    @Data
    public static class FlowLogsDataPoint {
        private Instant timestamp;
        private Long inboundBytes;
        private Long outboundBytes;
        private Long inboundPackets;
        private Long outboundPackets;
        private String protocol;
        private String action;

        // 构造函数
        public FlowLogsDataPoint() {}
    }

    /**
     * 获取实例最近N小时的流量统计
     *
     * @param tenant 租户信息
     * @param compartmentId 区间ID
     * @param hours 小时数（默认1小时，最大24小时）
     * @return 流量统计结果
     */
    public static FlowLogsTrafficStats getInstanceTrafficStats(Tenant tenant, InstanceDetails instanceDetail,
                                                               String compartmentId, int hours) {
        if (hours <= 0 || hours > MAX_QUERY_HOURS) {
            hours = DEFAULT_QUERY_HOURS;
            log.warn("小时数无效，使用默认值: " + DEFAULT_QUERY_HOURS);
        }

        Instant endTime = Instant.now();
        Instant startTime = endTime.minus(hours, ChronoUnit.HOURS);

        return getInstanceTrafficStats(tenant, instanceDetail, compartmentId, startTime, endTime);
    }

    /**
     * 获取实例指定时间段的流量统计
     *
     * @param tenant 租户信息
     * @param compartmentId 区间ID
     * @param startTime 开始时间
     * @param endTime 结束时间
     * @return 流量统计结果
     */
    public static FlowLogsTrafficStats getInstanceTrafficStats(Tenant tenant, InstanceDetails instanceDetail,
                                                               String compartmentId, Instant startTime, Instant endTime) {
        long queryStart = System.currentTimeMillis();

        try {
            log.info("开始获取实例 {} 从 {} 到 {} 的流量统计",
                    instanceDetail.getInstanceId(), startTime, endTime);

            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            // 1. 获取实例信息和私有IP
            String privateIP = instanceDetail.getPrivateIps();
            if (privateIP == null || privateIP.isEmpty()) {
                throw new RuntimeException("无法获取实例私有IP: " + instanceDetail.getInstanceId());
            }

            String publicIP = instanceDetail.getPublicIps();
            log.info("实例 {} 私有IP: {}, 公网IP: {}",
                    instanceDetail.getInstanceId(), privateIP, publicIP);

            // 2. 执行修复后的Flow Logs查询
            FlowLogsTrafficStats stats = executeFlowLogsQuery(provider, tenant, compartmentId,
                    instanceDetail.getInstanceId(), privateIP, startTime, endTime);

            // 3. 设置额外信息
            stats.setPublicIP(publicIP);

            long queryDuration = System.currentTimeMillis() - queryStart;
            stats.setQueryDuration(queryDuration + "ms");

            log.info("成功获取实例 {} 流量统计，耗时: {}ms", instanceDetail.getInstanceId(), queryDuration);
            log.info("流量统计 - 入站: {}, 出站: {}, 数据点: {}",
                    formatBytes(stats.getTotalInboundBytes()),
                    formatBytes(stats.getTotalOutboundBytes()),
                    stats.getDataPoints().size());

            return stats;

        } catch (Exception e) {
            log.error("获取实例流量统计失败: " + e.getMessage(), e);

            // 返回空的统计对象而不是抛出异常
            FlowLogsTrafficStats errorStats = new FlowLogsTrafficStats();
            errorStats.setInstanceId(instanceDetail.getInstanceId());
            errorStats.setPrivateIP(instanceDetail.getPrivateIps());
            errorStats.setPublicIP(instanceDetail.getPublicIps());
            errorStats.setStartTime(startTime);
            errorStats.setEndTime(endTime);
            errorStats.setTotalInboundBytes(0L);
            errorStats.setTotalOutboundBytes(0L);
            errorStats.setTotalInboundPackets(0L);
            errorStats.setTotalOutboundPackets(0L);
            errorStats.setDataPoints(new ArrayList<>());
            errorStats.setQueryDuration("ERROR: " + e.getMessage());

            return errorStats;
        }
    }

    /**
     * 获取所有活跃实例的流量统计
     *
     * @param tenant 租户信息
     * @param compartmentId 区间ID
     * @param hours 小时数
     * @return 实例ID到流量统计的映射
     */
    public static Map<String, FlowLogsTrafficStats> getAllInstancesTrafficStats(Tenant tenant,
                                                                                String compartmentId,
                                                                                List<InstanceDetails> instanceDetails,
                                                                                int hours) {
        try {
            log.info("获取所有活跃实例最近 {} 小时的流量统计", hours);

            if (hours <= 0 || hours > MAX_QUERY_HOURS) {
                hours = DEFAULT_QUERY_HOURS;
                log.warn("小时数无效，使用默认值: {}", DEFAULT_QUERY_HOURS);
            }

            Instant endTime = Instant.now();
            Instant startTime = endTime.minus(hours, ChronoUnit.HOURS);

            Map<String, FlowLogsTrafficStats> result = new HashMap<>();

            log.info("找到 {} 个活跃实例", instanceDetails.size());

            for (InstanceDetails instanceDetail : instanceDetails) {
                try {
                    FlowLogsTrafficStats stats = getInstanceTrafficStats(tenant, instanceDetail,
                            compartmentId, startTime, endTime);
                    result.put(instanceDetail.getPublicIps(), stats);

                    log.info("实例 {} 流量统计完成 - 入站: {}, 出站: {}",
                            instanceDetail.getInstanceId(),
                            formatBytes(stats.getTotalInboundBytes()),
                            formatBytes(stats.getTotalOutboundBytes()));

                } catch (Exception e) {
                    log.error("获取实例 {} 流量统计失败: {}", instanceDetail.getInstanceId(), e.getMessage());

                    // 创建错误统计对象
                    FlowLogsTrafficStats errorStats = new FlowLogsTrafficStats();
                    errorStats.setInstanceId(instanceDetail.getInstanceId());
                    errorStats.setPrivateIP(instanceDetail.getPrivateIps());
                    errorStats.setPublicIP(instanceDetail.getPublicIps());
                    errorStats.setStartTime(startTime);
                    errorStats.setEndTime(endTime);
                    errorStats.setTotalInboundBytes(0L);
                    errorStats.setTotalOutboundBytes(0L);
                    errorStats.setTotalInboundPackets(0L);
                    errorStats.setTotalOutboundPackets(0L);
                    errorStats.setDataPoints(new ArrayList<>());
                    errorStats.setQueryDuration("ERROR: " + e.getMessage());

                    result.put(instanceDetail.getInstanceId(), errorStats);
                }
            }

            log.info("所有实例流量统计完成，成功获取 {} 个实例的数据", result.size());
            return result;

        } catch (Exception e) {
            log.error("获取所有实例流量统计失败: " + e.getMessage(), e);
            throw new RuntimeException("获取所有实例流量统计失败: " + e.getMessage(), e);
        }
    }

    /**
     * 格式化字节数为人性化显示
     *
     * @param bytes 字节数
     * @return 格式化后的字符串
     */
    public static String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return String.format("%.2f KB", bytes / 1024.0);
        if (bytes < 1024 * 1024 * 1024) return String.format("%.2f MB", bytes / (1024.0 * 1024));
        return String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024));
    }

    /**
     * 计算流量速率
     *
     * @param bytes 字节数
     * @param durationSeconds 持续时间（秒）
     * @return 格式化的速率字符串
     */
    public static String calculateRate(long bytes, long durationSeconds) {
        if (durationSeconds <= 0) return "0 B/s";
        long bytesPerSecond = bytes / durationSeconds;
        return formatBytes(bytesPerSecond) + "/s";
    }

    // ===== 私有方法 =====

    /**
     * 获取实例私有IP地址
     */
    private static String getInstancePrivateIP(SimpleAuthenticationDetailsProvider provider,
                                               String instanceId, String compartmentId, Tenant tenant) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 设置区域
            computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
            networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 获取实例的VNIC附件
            ListVnicAttachmentsRequest vnicRequest = ListVnicAttachmentsRequest.builder()
                    .compartmentId(compartmentId)
                    .instanceId(instanceId)
                    .build();

            ListVnicAttachmentsResponse vnicResponse = computeClient.listVnicAttachments(vnicRequest);

            if (!vnicResponse.getItems().isEmpty()) {
                String vnicId = vnicResponse.getItems().get(0).getVnicId();

                // 获取VNIC详情
                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                        .vnicId(vnicId)
                        .build();

                GetVnicResponse getVnicResponse = networkClient.getVnic(getVnicRequest);
                return getVnicResponse.getVnic().getPrivateIp();
            }

            return null;
        } catch (Exception e) {
            log.error("获取实例私有IP失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 获取实例公网IP地址
     */
    private static String getInstancePublicIP(SimpleAuthenticationDetailsProvider provider,
                                              String instanceId, String compartmentId, Tenant tenant) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 设置区域
            computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
            networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 获取实例的VNIC附件
            ListVnicAttachmentsRequest vnicRequest = ListVnicAttachmentsRequest.builder()
                    .compartmentId(compartmentId)
                    .instanceId(instanceId)
                    .build();

            ListVnicAttachmentsResponse vnicResponse = computeClient.listVnicAttachments(vnicRequest);

            if (!vnicResponse.getItems().isEmpty()) {
                String vnicId = vnicResponse.getItems().get(0).getVnicId();

                // 获取VNIC详情
                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                        .vnicId(vnicId)
                        .build();

                GetVnicResponse getVnicResponse = networkClient.getVnic(getVnicRequest);
                return getVnicResponse.getVnic().getPublicIp();
            }

            return null;
        } catch (Exception e) {
            log.warn("获取实例公网IP失败: " + e.getMessage());
            return null;
        }
    }

    /**
     * 获取所有活跃实例ID列表
     */
    private static List<String> getActiveInstanceIds(Tenant tenant, String compartmentId) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                // 设置区域
                computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                ListInstancesRequest request = ListInstancesRequest.builder()
                        .compartmentId(compartmentId)
                        .lifecycleState(Instance.LifecycleState.Running)
                        .build();

                ListInstancesResponse response = computeClient.listInstances(request);

                return response.getItems().stream()
                        .map(Instance::getId)
                        .collect(Collectors.toList());
            }
        } catch (Exception e) {
            log.error("获取活跃实例ID列表失败: " + e.getMessage(), e);
            return Collections.emptyList();
        }
    }

    /**
     * 执行Flow Logs查询
     */
    private static FlowLogsTrafficStats executeFlowLogsQuery(SimpleAuthenticationDetailsProvider provider,
                                                             Tenant tenant, String compartmentId,
                                                             String instanceId, String privateIP,
                                                             Instant startTime, Instant endTime) {
        try (LogSearchClient logSearchClient = LogSearchClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
            // 设置区域
            logSearchClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 获取Flow Logs Group ID
            String flowLogsGroupId = getFlowLogsGroupId(tenant, compartmentId);
            if (flowLogsGroupId == null) {
                log.warn("未找到Flow Logs Group，将使用compartment级别查询");
            }

            // 构建查询语句 - 使用修复后的方法
            String searchQuery;
            if (flowLogsGroupId != null) {
                searchQuery = String.format("search \"%s/%s\" | sort by datetime desc",
                        compartmentId, flowLogsGroupId);
            } else {
                searchQuery = String.format("search \"%s\" | sort by datetime desc", compartmentId);
            }

            log.debug("执行Flow Logs查询: {}", searchQuery);

            // 执行查询
            SearchLogsRequest request = SearchLogsRequest.builder()
                    .searchLogsDetails(SearchLogsDetails.builder()
                            .searchQuery(searchQuery)
                            .timeStart(Date.from(startTime))
                            .timeEnd(Date.from(endTime))
                            .build())
                    .build();

            SearchLogsResponse response = logSearchClient.searchLogs(request);
            SearchResponse searchResponse = response.getSearchResponse();

            // 使用客户端过滤解析结果
            FlowLogsTrafficStats stats = parseFlowLogsResultsWithClientFiltering(
                    searchResponse, instanceId, privateIP, startTime, endTime);

            log.info("Flow Logs查询完成 - 实例: {}, IP: {}, 入站: {}, 出站: {},总流量:{}",
                    instanceId, privateIP,
                    formatBytes(stats.getTotalInboundBytes()),
                    formatBytes(stats.getTotalOutboundBytes()),
                    formatBytes(stats.getTotalFlow()));

            return stats;

        } catch (Exception e) {
            log.error("执行Flow Logs查询失败: " + e.getMessage(), e);
            throw new RuntimeException("Flow Logs查询失败: " + e.getMessage(), e);
        }
    }

    private static String buildFlowLogsQueryForInstance(Tenant tenant,String compartmentId, String privateIP, String vcnId) {
        // 获取Flow Logs Group ID
        String flowLogsGroupId = null;
        try {
            flowLogsGroupId = getFlowLogsGroupId(tenant, compartmentId);
        } catch (Exception e) {
            log.warn("无法动态获取Flow Logs Group ID，使用默认值");
        }

        StringBuilder queryBuilder = new StringBuilder();

        if (flowLogsGroupId != null) {
            // 使用具体的Log Group ID进行查询
            queryBuilder.append(String.format("search \"%s/%s\"", compartmentId, flowLogsGroupId));
        } else {
            // 回退到compartment级别查询
            queryBuilder.append(String.format("search \"%s\"", compartmentId));
        }

        // 添加排序和限制，确保获取最新数据
        queryBuilder.append(" | sort by datetime desc");
        queryBuilder.append(" | limit 1000"); // 增加限制数量，确保能获取到目标IP的数据

        log.debug("生成的Flow Logs查询语句: {}", queryBuilder.toString());
        return queryBuilder.toString();
    }

    private static String buildFlowLogsQueryForInstance2(String compartmentId, String privateIP, String vcnId) {
        if (vcnId != null && !vcnId.isEmpty()) {
            // 如果知道VCN ID，添加VCN过滤条件
            return String.format(
                    "search \"%s\" | where type=\"flowlogs\" | " +
                            "where data.vcnId=\"%s\" | " +
                            "where (data.srcaddr=\"%s\" or data.dstaddr=\"%s\")",
                    compartmentId, vcnId, privateIP, privateIP
            );
        } else {
            // 如果不知道VCN ID，使用原来的查询方式
            return String.format(
                    "search \"%s\" | where type=\"flowlogs\" | where (data.srcaddr=\"%s\" or data.dstaddr=\"%s\")",
                    compartmentId, privateIP, privateIP
            );
        }
    }

    /**
     * 获取实例所在的VCN信息
     */
    private static String getInstanceVcnId(SimpleAuthenticationDetailsProvider provider,
                                           String instanceId, String compartmentId, Tenant tenant) {
        try (ComputeClient computeClient = ComputeClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
             VirtualNetworkClient networkClient = VirtualNetworkClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {

            // 设置区域
            computeClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));
            networkClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

            // 获取实例的VNIC附件
            ListVnicAttachmentsRequest vnicRequest = ListVnicAttachmentsRequest.builder()
                    .compartmentId(compartmentId)
                    .instanceId(instanceId)
                    .build();

            ListVnicAttachmentsResponse vnicResponse = computeClient.listVnicAttachments(vnicRequest);

            if (!vnicResponse.getItems().isEmpty()) {
                String vnicId = vnicResponse.getItems().get(0).getVnicId();

                // 获取VNIC详情
                GetVnicRequest getVnicRequest = GetVnicRequest.builder()
                        .vnicId(vnicId)
                        .build();

                GetVnicResponse getVnicResponse = networkClient.getVnic(getVnicRequest);
                String subnetId = getVnicResponse.getVnic().getSubnetId();

                // 通过子网ID获取VCN ID
                GetSubnetRequest getSubnetRequest = GetSubnetRequest.builder()
                        .subnetId(subnetId)
                        .build();

                GetSubnetResponse getSubnetResponse = networkClient.getSubnet(getSubnetRequest);
                return getSubnetResponse.getSubnet().getVcnId();
            }

            return null;
        } catch (Exception e) {
            log.error("获取实例VCN ID失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 构建Flow Logs查询语句
     */
    private static String buildFlowLogsQuery(String compartmentId, String privateIP) {
        return String.format(
                "search \"%s\" | where type=\"flowlogs\" | where (data.srcaddr=\"%s\" or data.dstaddr=\"%s\")",
                compartmentId, privateIP, privateIP
        );
    }

    private static FlowLogsTrafficStats parseFlowLogsResults(SearchResponse response,
                                                             String instanceId, String privateIP,
                                                             Instant startTime, Instant endTime) {
        // 直接使用修复后的客户端过滤方法
        return parseFlowLogsResultsWithClientFiltering(response, instanceId, privateIP, startTime, endTime);
    }

    // 辅助解析方法
    private static long parseLong(Object value) {
        if (value == null) return 0;
        if (value instanceof Number) {
            return ((Number) value).longValue();
        }
        try {
            return Long.parseLong(value.toString());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String parseString(Object value) {
        return value != null ? value.toString() : "unknown";
    }

    private static Instant parseTimestamp(Object timestamp) {
        if (timestamp instanceof Date) {
            return ((Date) timestamp).toInstant();
        }
        if (timestamp instanceof String) {
            try {
                return Instant.parse((String) timestamp);
            } catch (Exception e) {
                try {
                    return Instant.from(DateTimeFormatter.ISO_INSTANT.parse((String) timestamp));
                } catch (Exception ex) {
                    log.warn("解析时间戳失败: " + timestamp);
                    return Instant.now();
                }
            }
        }
        return Instant.now();
    }

    /**
     * 获取VCN下的所有子网
     */
    public static List<Subnet> getVcnSubnets(VirtualNetworkClient virtualNetworkClient,
                                              String compartmentId, String vcnId) {
        try {
            ListSubnetsRequest request = ListSubnetsRequest.builder()
                    .compartmentId(compartmentId)
                    .vcnId(vcnId)
                    .build();

            ListSubnetsResponse response = virtualNetworkClient.listSubnets(request);
            return response.getItems();

        } catch (Exception e) {
            log.error("获取VCN子网失败: " + e.getMessage(), e);
            return Collections.emptyList();
        }
    }

    /**
     * 创建或获取Log Group
     */
    private static LogGroup createOrGetLogGroup(LoggingManagementClient loggingManagementClient,
                                                String compartmentId) {
        try {
            String logGroupName = "vcn-flowlogs-group";

            // 先查询是否已存在Log Group
            ListLogGroupsRequest listRequest = ListLogGroupsRequest.builder()
                    .compartmentId(compartmentId)
                    .displayName(logGroupName)
                    .build();

            ListLogGroupsResponse listResponse = loggingManagementClient.listLogGroups(listRequest);

            // 如果已存在，获取完整的Log Group信息
            if (!listResponse.getItems().isEmpty()) {
                LogGroupSummary existingGroupSummary = listResponse.getItems().get(0);
                log.info("找到现有Log Group: " + existingGroupSummary.getId() + ", Name: " + existingGroupSummary.getDisplayName());

                // 获取完整的Log Group信息
                GetLogGroupRequest getRequest = GetLogGroupRequest.builder()
                        .logGroupId(existingGroupSummary.getId())
                        .build();

                GetLogGroupResponse getResponse = loggingManagementClient.getLogGroup(getRequest);
                LogGroup existingGroup = getResponse.getLogGroup();

                log.info("使用现有Log Group: " + existingGroup.getId() + ", Name: " + existingGroup.getDisplayName());
                return existingGroup;
            }

            // 创建新的Log Group
            log.info("创建新的Log Group: " + logGroupName);

            CreateLogGroupDetails createDetails = CreateLogGroupDetails.builder()
                    .compartmentId(compartmentId)
                    .displayName(logGroupName)
                    .description("Log Group for VCN Flow Logs")
                    .build();

            CreateLogGroupRequest createRequest = CreateLogGroupRequest.builder()
                    .createLogGroupDetails(createDetails)
                    .build();

            CreateLogGroupResponse createResponse = loggingManagementClient.createLogGroup(createRequest);

            LogGroup logGroup = waitForLogGroupCreation(loggingManagementClient, compartmentId, logGroupName, 60);

            log.info("创建Log Group成功: " + logGroup.getId());

            return logGroup;

        } catch (Exception e) {
            log.error("创建或获取Log Group失败: " + e.getMessage(), e);
            throw new RuntimeException("Log Group配置失败", e);
        }
    }

    /**
     * 为子网配置Flow Logs
     */
    private static boolean configureSubnetFlowLogs(LoggingManagementClient loggingManagementClient,
                                                   String compartmentId, String logGroupId, Subnet subnet) {
        try {
            String logName = "flowlogs-" + subnet.getDisplayName().toLowerCase().replaceAll("[^a-z0-9-]", "-");

            // 1. 先检查是否已经配置了Flow Logs（按资源检查）
            if (isFlowLogsAlreadyConfigured(loggingManagementClient, compartmentId, subnet.getId())) {
                log.info("子网 {} 已配置Flow Logs，跳过创建", subnet.getId());
                return false;
            }

            // 2. 检查Log名称是否冲突，如果冲突则生成唯一名称
            String uniqueLogName = generateUniqueLogName(loggingManagementClient, logGroupId, logName);

            log.debug("为子网 {} 创建Flow Logs: {}", subnet.getId(), uniqueLogName);

            // 创建Flow Logs配置
            OciService ociService = OciService.builder()
                    .service("flowlogs")
                    .resource(subnet.getId())
                    .category("all")
                    .build();

            Configuration configuration = Configuration.builder()
                    .source(ociService)
                    .archiving(Archiving.builder()
                            .isEnabled(false)
                            .build())
                    .build();

            CreateLogDetails createLogDetails = CreateLogDetails.builder()
                    .displayName(uniqueLogName)
                    .logType(CreateLogDetails.LogType.Service)
                    .configuration(configuration)
                    .retentionDuration(30) // 保留30天
                    .build();

            CreateLogRequest createRequest = CreateLogRequest.builder()
                    .createLogDetails(createLogDetails)
                    .logGroupId(logGroupId)
                    .build();

            CreateLogResponse createResponse = loggingManagementClient.createLog(createRequest);

            log.info("Flow Logs创建请求已提交: {}", uniqueLogName);

            // 等待Log变为Active状态（可选）
            try {
                // 这里需要等待Log创建完成，类似Log Group的等待机制
                waitForLogCreation(loggingManagementClient, logGroupId, uniqueLogName, 60);
            } catch (Exception e) {
                log.warn("等待Flow Logs激活超时，但创建请求已提交: " + e.getMessage());
            }

            return true;

        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().contains("already exists")) {
                log.warn("子网 {} 的Flow Logs可能已存在，跳过创建: {}", subnet.getId(), e.getMessage());
                return false;
            } else {
                log.error("配置子网Flow Logs失败: " + e.getMessage(), e);
                throw new RuntimeException("子网Flow Logs配置失败", e);
            }
        }
    }

    /**
     * 生成唯一的Log名称
     */
    private static String generateUniqueLogName(LoggingManagementClient loggingManagementClient,
                                                String logGroupId, String baseName) {
        try {
            // 获取Log Group中的所有Log名称
            ListLogsRequest listLogsRequest = ListLogsRequest.builder()
                    .logGroupId(logGroupId)
                    .build();

            ListLogsResponse listLogsResponse = loggingManagementClient.listLogs(listLogsRequest);

            Set<String> existingNames = listLogsResponse.getItems().stream()
                    .map(LogSummary::getDisplayName)
                    .collect(Collectors.toSet());

            // 如果基础名称不冲突，直接使用
            if (!existingNames.contains(baseName)) {
                return baseName;
            }

            // 如果冲突，添加序号
            int counter = 1;
            String uniqueName;
            do {
                uniqueName = baseName + "-" + counter;
                counter++;
            } while (existingNames.contains(uniqueName) && counter < 100); // 最多尝试100次

            if (counter >= 100) {
                // 如果还是冲突，使用时间戳
                uniqueName = baseName + "-" + System.currentTimeMillis();
            }

            log.info("生成唯一Log名称: {} -> {}", baseName, uniqueName);
            return uniqueName;

        } catch (Exception e) {
            log.warn("生成唯一Log名称失败，使用时间戳: " + e.getMessage());
            return baseName + "-" + System.currentTimeMillis();
        }
    }

    private static boolean waitForLogCreation(LoggingManagementClient loggingManagementClient,
                                              String logGroupId, String logName, int maxWaitSeconds) {
        try {
            int waitedSeconds = 0;
            int pollIntervalSeconds = 2;

            while (waitedSeconds < maxWaitSeconds) {
                Thread.sleep(pollIntervalSeconds * 1000);
                waitedSeconds += pollIntervalSeconds;

                log.debug("查询Log创建状态... (已等待{}秒)", waitedSeconds);

                // 查询Log Group中的Logs
                ListLogsRequest listLogsRequest = ListLogsRequest.builder()
                        .logGroupId(logGroupId)
                        .displayName(logName)
                        .build();

                ListLogsResponse listLogsResponse = loggingManagementClient.listLogs(listLogsRequest);

                if (!listLogsResponse.getItems().isEmpty()) {
                    LogSummary logSummary = listLogsResponse.getItems().get(0);

                    // 获取Log详细信息
                    GetLogRequest getLogRequest = GetLogRequest.builder()
                            .logGroupId(logGroupId)
                            .logId(logSummary.getId())
                            .build();

                    GetLogResponse getLogResponse = loggingManagementClient.getLog(getLogRequest);
                    Log log = getLogResponse.getLog();

                    if (log.getLifecycleState() == LogLifecycleState.Active) {
                        VCNFlowLogsUtils.log.info("Log创建完成并处于Active状态，耗时{}秒", waitedSeconds);
                        return true;
                    } else if (log.getLifecycleState() == LogLifecycleState.Creating) {
                        VCNFlowLogsUtils.log.debug("Log仍在创建中，状态: {}", log.getLifecycleState());
                        continue;
                    } else {
                        VCNFlowLogsUtils.log.warn("Log创建失败，状态: {}", log.getLifecycleState());
                        return false;
                    }
                } else {
                    VCNFlowLogsUtils.log.debug("Log尚未出现在列表中，继续等待...");
                }
            }

            VCNFlowLogsUtils.log.warn("等待Log创建超时，超过{}秒", maxWaitSeconds);
            return false;

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            VCNFlowLogsUtils.log.error("等待Log创建被中断", e);
            return false;
        } catch (Exception e) {
            VCNFlowLogsUtils.log.error("等待Log创建时发生错误: " + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 检查子网是否已配置Flow Logs
     */
    private static boolean isFlowLogsAlreadyConfigured(LoggingManagementClient loggingManagementClient,
                                                       String compartmentId, String subnetId) {
        try {
            log.debug("检查子网 {} 的Flow Logs配置状态", subnetId);

            // 查询所有Log Groups
            ListLogGroupsRequest listGroupsRequest = ListLogGroupsRequest.builder()
                    .compartmentId(compartmentId)
                    .build();

            ListLogGroupsResponse listGroupsResponse = loggingManagementClient.listLogGroups(listGroupsRequest);

            // 遍历每个Log Group
            for (LogGroupSummary logGroupSummary : listGroupsResponse.getItems()) {
                // 查询Log Group中的所有Logs
                ListLogsRequest listLogsRequest = ListLogsRequest.builder()
                        .logGroupId(logGroupSummary.getId())
                        .logType(ListLogsRequest.LogType.Service)
                        .build();

                ListLogsResponse listLogsResponse = loggingManagementClient.listLogs(listLogsRequest);

                // 检查是否有针对该子网的Flow Logs
                for (LogSummary logSummary : listLogsResponse.getItems()) {
                    try {
                        // 获取Log详情
                        GetLogRequest getLogRequest = GetLogRequest.builder()
                                .logGroupId(logGroupSummary.getId())
                                .logId(logSummary.getId())
                                .build();

                        GetLogResponse getLogResponse = loggingManagementClient.getLog(getLogRequest);
                        Log ociLog = getLogResponse.getLog();

                        // 检查配置中是否包含该子网
                        if (ociLog.getConfiguration() != null &&
                                ociLog.getConfiguration().getSource() != null &&
                                ociLog.getConfiguration().getSource() instanceof OciService) {

                            OciService ociService = (OciService) ociLog.getConfiguration().getSource();

                            if ("flowlogs".equals(ociService.getService()) &&
                                    subnetId.equals(ociService.getResource())) {
                                log.debug("找到子网 {} 的现有Flow Logs配置: {} (状态: {})",
                                        subnetId, ociLog.getId(), ociLog.getLifecycleState());
                                return true;
                            }
                        }
                    } catch (Exception e) {
                        log.debug("检查Log详情失败，跳过: " + e.getMessage());
                        continue;
                    }
                }
            }

            return false; // 未找到配置

        } catch (Exception e) {
            log.warn("检查Flow Logs配置状态失败: " + e.getMessage());
            return false; // 默认假设未配置
        }
    }

    /**
     * 等待Log Group创建完成
     *
     * @param loggingManagementClient Logging客户端
     * @param compartmentId 区间ID
     * @param logGroupName Log Group名称
     * @param maxWaitSeconds 最大等待秒数
     * @return 创建的LogGroup，如果超时返回null
     */
    private static LogGroup waitForLogGroupCreation(LoggingManagementClient loggingManagementClient,
                                                    String compartmentId, String logGroupName, int maxWaitSeconds) {
        try {
            int waitedSeconds = 0;
            int pollIntervalSeconds = 2; // 每2秒查询一次

            while (waitedSeconds < maxWaitSeconds) {
                Thread.sleep(pollIntervalSeconds * 1000);
                waitedSeconds += pollIntervalSeconds;

                log.debug("查询Log Group创建状态... (已等待{}秒)", waitedSeconds);

                // 查询是否已创建成功
                ListLogGroupsRequest listRequest = ListLogGroupsRequest.builder()
                        .compartmentId(compartmentId)
                        .displayName(logGroupName)
                        .build();

                ListLogGroupsResponse listResponse = loggingManagementClient.listLogGroups(listRequest);

                if (!listResponse.getItems().isEmpty()) {
                    // 找到了Log Group，获取完整信息
                    LogGroupSummary logGroupSummary = listResponse.getItems().get(0);

                    GetLogGroupRequest getRequest = GetLogGroupRequest.builder()
                            .logGroupId(logGroupSummary.getId())
                            .build();

                    GetLogGroupResponse getResponse = loggingManagementClient.getLogGroup(getRequest);
                    LogGroup logGroup = getResponse.getLogGroup();

                    // 检查状态
                    if (logGroup.getLifecycleState() == LogGroupLifecycleState.Active) {
                        log.info("Log Group创建完成并处于Active状态，耗时{}秒", waitedSeconds);
                        return logGroup;
                    } else if (logGroup.getLifecycleState() == LogGroupLifecycleState.Creating) {
                        log.debug("Log Group仍在创建中，状态: {}", logGroup.getLifecycleState());
                        continue; // 继续等待
                    } else {
                        log.warn("Log Group创建失败，状态: {}", logGroup.getLifecycleState());
                        return null;
                    }
                } else {
                    log.debug("Log Group尚未出现在列表中，继续等待...");
                }
            }

            log.warn("等待Log Group创建超时，超过{}秒", maxWaitSeconds);
            return null;

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("等待Log Group创建被中断", e);
            return null;
        } catch (Exception e) {
            log.error("等待Log Group创建时发生错误: " + e.getMessage(), e);
            return null;
        }
    }

    //<=======测试方法开始=========>
    /**
     * 调试Flow Logs数据结构
     */
    public static void debugFlowLogsDataStructure(Tenant tenant, String compartmentId) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LogSearchClient logSearchClient = LogSearchClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                logSearchClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                Instant endTime = Instant.now();
                Instant startTime = endTime.minus(1, ChronoUnit.DAYS);

                // 最基础的查询，不加任何过滤条件
                String basicQuery = String.format("search \"%s\"", compartmentId);

                log.info("执行基础查询: {}", basicQuery);

                SearchLogsRequest request = SearchLogsRequest.builder()
                        .searchLogsDetails(SearchLogsDetails.builder()
                                .searchQuery(basicQuery)
                                .timeStart(Date.from(startTime))
                                .timeEnd(Date.from(endTime))
                                .build())
                        .build();

                SearchLogsResponse response = logSearchClient.searchLogs(request);
                SearchResponse searchResponse = response.getSearchResponse();

                List<SearchResult> results = searchResponse.getResults();
                log.info("基础查询返回 {} 条记录", results != null ? results.size() : 0);

                if (results != null && !results.isEmpty()) {
                    // 查看前几条记录的结构
                    for (int i = 0; i < Math.min(3, results.size()); i++) {
                        SearchResult result = results.get(i);
                        log.info("记录 {}: {}", i, result.getData());

                        // 如果数据是Map类型，打印所有字段
                        if (result.getData() instanceof Map) {
                            Map<String, Object> data = (Map<String, Object>) result.getData();
                            log.info("记录 {} 的所有字段:", i);
                            data.forEach((key, value) -> {
                                log.info("  {}: {} (类型: {})", key, value,
                                        value != null ? value.getClass().getSimpleName() : "null");
                            });
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.error("调试Flow Logs数据结构失败", e);
        }
    }

    /**
     * 逐步测试Flow Logs查询
     */
    public static void testFlowLogsQueries(Tenant tenant, String compartmentId, String privateIP) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LogSearchClient logSearchClient = LogSearchClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                logSearchClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                Instant endTime = Instant.now();
                Instant startTime = endTime.minus(1, ChronoUnit.DAYS);

                // 测试查询1: 只查询type
                String[] testQueries = {
                        String.format("search \"%s\" | where data.srcaddr=\"%s\"", compartmentId, privateIP),
                        String.format("search \"%s\" | where data.srcAddr=\"%s\"", compartmentId, privateIP),
                        String.format("search \"%s\" | where data.source=\"%s\"", compartmentId, privateIP),
                };

                for (int i = 0; i < testQueries.length; i++) {
                    String query = testQueries[i];
                    log.info("测试查询 {}: {}", i + 1, query);

                    try {
                        SearchLogsRequest request = SearchLogsRequest.builder()
                                .searchLogsDetails(SearchLogsDetails.builder()
                                        .searchQuery(query)
                                        .timeStart(Date.from(startTime))
                                        .timeEnd(Date.from(endTime))
                                        .build())
                                .build();

                        SearchLogsResponse response = logSearchClient.searchLogs(request);
                        SearchResponse searchResponse = response.getSearchResponse();

                        List<SearchResult> results = searchResponse.getResults();
                        log.info("查询 {} 返回 {} 条记录", i + 1, results != null ? results.size() : 0);

                        if (results != null && !results.isEmpty()) {
                            SearchResult firstResult = results.get(0);
                            log.info("第一条记录: {}", firstResult.getData());
                            break; // 找到有数据的查询就停止
                        }
                    } catch (Exception e) {
                        log.warn("查询 {} 失败: {}", i + 1, e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            log.error("测试Flow Logs查询失败", e);
        }
    }
    /**
     * 检查Flow Logs配置状态
     */
    public static void checkFlowLogsStatus(Tenant tenant, String compartmentId) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LoggingManagementClient loggingClient = LoggingManagementClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                loggingClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 查询所有Log Groups
                ListLogGroupsRequest request = ListLogGroupsRequest.builder()
                        .compartmentId(compartmentId)
                        .build();

                ListLogGroupsResponse response = loggingClient.listLogGroups(request);

                log.info("找到 {} 个Log Groups", response.getItems().size());

                boolean foundFlowLogs = false;
                for (LogGroupSummary logGroup : response.getItems()) {
                    log.info("Log Group: {} (状态: {})", logGroup.getDisplayName(), logGroup.getLifecycleState());

                    // 查询Log Group中的Logs
                    ListLogsRequest logsRequest = ListLogsRequest.builder()
                            .logGroupId(logGroup.getId())
                            .build();

                    ListLogsResponse logsResponse = loggingClient.listLogs(logsRequest);

                    for (LogSummary logSummary : logsResponse.getItems()) {
                        log.info("  Log: {} (状态: {})", logSummary.getDisplayName(), logSummary.getLifecycleState());

                        // 获取Log详情
                        GetLogRequest getLogRequest = GetLogRequest.builder()
                                .logGroupId(logGroup.getId())
                                .logId(logSummary.getId())
                                .build();

                        GetLogResponse getLogResponse = loggingClient.getLog(getLogRequest);
                        Log ociLog = getLogResponse.getLog();

                        if (ociLog.getConfiguration() != null &&
                                ociLog.getConfiguration().getSource() instanceof OciService) {
                            OciService source = (OciService) ociLog.getConfiguration().getSource();
                            log.info("    Service: {}, Resource: {}, Category: {}",
                                    source.getService(), source.getResource(), source.getCategory());

                            if ("flowlogs".equals(source.getService())) {
                                foundFlowLogs = true;
                                log.info("    ✓ 找到Flow Logs配置");
                            }
                        }
                    }
                }

                if (!foundFlowLogs) {
                    log.warn("未找到任何Flow Logs配置，请先配置VCN Flow Logs");
                }
            }
        } catch (Exception e) {
            log.error("检查Flow Logs状态失败", e);
        }
    }

    /**
     * 使用正确GSL语法测试Flow Logs查询
     */
    public static void testCorrectOracleFlowLogsQueriesFixed(Tenant tenant, String compartmentId, String privateIP) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LogSearchClient logSearchClient = LogSearchClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                logSearchClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                Instant endTime = Instant.now();
                Instant startTime = endTime.minus(3, ChronoUnit.HOURS);

                // 获取Flow Logs Group ID
                String flowLogsGroupId = getFlowLogsGroupId(tenant, compartmentId);
                if (flowLogsGroupId == null) {
                    log.error("未找到Flow Logs Group ID，请先配置Flow Logs");
                    return;
                }

                log.info("Flow Logs Group ID: {}", flowLogsGroupId);

                // 修复后的查询策略：由于Oracle不支持复杂的where条件，
                // 我们改用批量查询+后过滤的方式
                String[] workingQueries = {
                        // 查询1: 获取最新的Flow Logs数据
                        String.format("search \"%s/%s\" | sort by datetime desc | limit 100", compartmentId, flowLogsGroupId),

                        // 查询2: 获取更多数据用于IP过滤
                        String.format("search \"%s/%s\" | limit 500", compartmentId, flowLogsGroupId),

                        // 查询3: 如果数据量大，分时间段查询
                        String.format("search \"%s/%s\" | sort by datetime desc | limit 1000", compartmentId, flowLogsGroupId)
                };

                boolean foundMatchingTraffic = false;

                for (int i = 0; i < workingQueries.length; i++) {
                    String query = workingQueries[i];
                    log.info("=== 执行查询 {} ===", i + 1);
                    log.info("查询语句: {}", query);

                    try {
                        SearchLogsRequest request = SearchLogsRequest.builder()
                                .searchLogsDetails(SearchLogsDetails.builder()
                                        .searchQuery(query)
                                        .timeStart(Date.from(startTime))
                                        .timeEnd(Date.from(endTime))
                                        .build())
                                .build();

                        SearchLogsResponse response = logSearchClient.searchLogs(request);
                        SearchResponse searchResponse = response.getSearchResponse();

                        List<SearchResult> results = searchResponse.getResults();
                        log.info("查询 {} 返回 {} 条记录", i + 1, results != null ? results.size() : 0);

                        if (results != null && !results.isEmpty()) {
                            // 手动过滤包含目标IP的记录
                            List<SearchResult> matchingResults = filterResultsByIP(results, privateIP);

                            log.info("过滤后找到 {} 条包含IP {} 的记录", matchingResults.size(), privateIP);

                            if (!matchingResults.isEmpty()) {
                                foundMatchingTraffic = true;
                                log.info("✓ 成功找到目标IP的流量数据！");

                                // 分析前几条匹配的记录
                                for (int j = 0; j < Math.min(3, matchingResults.size()); j++) {
                                    log.info("=== 匹配记录 {} ===", j + 1);
                                    analyzeMatchingFlowLogsRecord(matchingResults.get(j), privateIP);
                                }

                                // 测试流量统计
                                log.info("=== 测试流量统计 ===");
                                FlowLogsTrafficStats stats = parseFlowLogsResultsWithClientFiltering(
                                        searchResponse, "test-instance", privateIP, startTime, endTime);

                                displayTrafficStats(stats);

                                break; // 找到数据就退出
                            } else {
                                log.info("该批次数据中未找到IP {} 的流量", privateIP);
                            }
                        } else {
                            log.warn("查询 {} 无数据", i + 1);
                        }

                    } catch (Exception e) {
                        log.error("查询 {} 失败: {}", i + 1, e.getMessage());
                    }
                }

                if (!foundMatchingTraffic) {
                    log.warn("在所有查询中都未找到IP {} 的流量数据", privateIP);
                    log.info("建议：");
                    log.info("1. 检查IP地址是否正确");
                    log.info("2. 确认该IP在查询时间段内是否有网络活动");
                    log.info("3. 扩大查询时间范围");
                } else {
                    log.info("=== 测试总结 ===");
                    log.info("✓ Oracle Logging Search 基础查询功能正常");
                    log.info("✓ 客户端IP过滤方案可行");
                    log.info("✓ Flow Logs数据结构解析正确");
                    log.info("推荐使用：批量查询 + 客户端过滤的方案");
                }
            }
        } catch (Exception e) {
            log.error("测试Oracle Flow Logs查询失败", e);
        }
    }

    /**
     * 手动过滤包含指定IP的Flow Logs记录
     */
    private static List<SearchResult> filterResultsByIP(List<SearchResult> results, String targetIP) {
        List<SearchResult> matchingResults = new ArrayList<>();

        for (SearchResult result : results) {
            try {
                Object dataObj = result.getData();
                if (!(dataObj instanceof Map)) {
                    continue;
                }

                Map<String, Object> topLevelData = (Map<String, Object>) dataObj;
                Object logContentObj = topLevelData.get("logContent");
                if (!(logContentObj instanceof Map)) {
                    continue;
                }

                Map<String, Object> logContent = (Map<String, Object>) logContentObj;
                Object flowDataObj = logContent.get("data");
                if (!(flowDataObj instanceof Map)) {
                    continue;
                }

                Map<String, Object> flowData = (Map<String, Object>) flowDataObj;

                String sourceAddress = parseString(flowData.get("sourceAddress"));
                String destinationAddress = parseString(flowData.get("destinationAddress"));

                // 检查是否包含目标IP
                if (targetIP.equals(sourceAddress) || targetIP.equals(destinationAddress)) {
                    matchingResults.add(result);
                }

            } catch (Exception e) {
                log.debug("过滤Flow Logs记录时出错: " + e.getMessage());
                continue;
            }
        }

        return matchingResults;
    }

    /**
     * 分析匹配的Flow Logs记录
     */
    private static void analyzeMatchingFlowLogsRecord(SearchResult result, String targetIP) {
        try {
            Object dataObj = result.getData();
            Map<String, Object> topLevelData = (Map<String, Object>) dataObj;
            Map<String, Object> logContent = (Map<String, Object>) topLevelData.get("logContent");
            Map<String, Object> flowData = (Map<String, Object>) logContent.get("data");

            String sourceAddress = parseString(flowData.get("sourceAddress"));
            String destinationAddress = parseString(flowData.get("destinationAddress"));
            long bytesOut = parseLong(flowData.get("bytesOut"));
            long packets = parseLong(flowData.get("packets"));
            String protocolName = parseString(flowData.get("protocolName"));
            String action = parseString(flowData.get("action"));

            // 解析时间戳
            Object datetime = topLevelData.get("datetime");
            Instant timestamp = Instant.ofEpochMilli((Long) datetime);

            // 判断流量方向
            boolean isInbound = targetIP.equals(destinationAddress);
            boolean isOutbound = targetIP.equals(sourceAddress);

            log.info("时间: {}", timestamp);
            log.info("源地址: {} -> 目标地址: {}", sourceAddress, destinationAddress);
            log.info("流量方向: {}", isInbound ? "入站" : (isOutbound ? "出站" : "未知"));
            log.info("字节数: {}, 包数: {}, 协议: {}, 动作: {}",
                    formatBytes(bytesOut), packets, protocolName, action);

        } catch (Exception e) {
            log.error("分析匹配记录失败: " + e.getMessage());
        }
    }

    /**
     * 使用客户端过滤的Flow Logs结果解析
     */
    private static FlowLogsTrafficStats parseFlowLogsResultsWithClientFiltering(SearchResponse response,
                                                                                String instanceId, String privateIP,
                                                                                Instant startTime, Instant endTime) {
        FlowLogsTrafficStats stats = new FlowLogsTrafficStats();
        stats.setInstanceId(instanceId);
        stats.setPrivateIP(privateIP);
        stats.setStartTime(startTime);
        stats.setEndTime(endTime);

        long totalInbound = 0;
        long totalOutbound = 0;
        long totalInboundPackets = 0;
        long totalOutboundPackets = 0;
        List<FlowLogsDataPoint> dataPoints = new ArrayList<>();

        List<SearchResult> results = response.getResults();
        if (results != null && !results.isEmpty()) {
            // 先过滤出包含目标IP的记录
            List<SearchResult> matchingResults = filterResultsByIP(results, privateIP);

            log.debug("Flow Logs解析 - 原始记录: {}, 匹配记录: {}", results.size(), matchingResults.size());

            Map<String, FlowLogsDataPoint> timePointMap = new HashMap<>();
            int validRecords = 0;
            int inboundRecords = 0;
            int outboundRecords = 0;

            for (SearchResult result : matchingResults) {
                try {
                    Object dataObj = result.getData();
                    if (!(dataObj instanceof Map)) {
                        continue;
                    }

                    Map<String, Object> topLevelData = (Map<String, Object>) dataObj;
                    Object logContentObj = topLevelData.get("logContent");
                    if (!(logContentObj instanceof Map)) {
                        continue;
                    }

                    Map<String, Object> logContent = (Map<String, Object>) logContentObj;
                    Object flowDataObj = logContent.get("data");
                    if (!(flowDataObj instanceof Map)) {
                        continue;
                    }

                    Map<String, Object> flowData = (Map<String, Object>) flowDataObj;

                    // 解析字段
                    String sourceAddress = parseString(flowData.get("sourceAddress"));
                    String destinationAddress = parseString(flowData.get("destinationAddress"));

                    // 修复1: 检查多个可能的字节字段
                    long bytes = 0;
                    if (flowData.containsKey("bytesOut")) {
                        bytes = parseLong(flowData.get("bytesOut"));
                    } else if (flowData.containsKey("bytes")) {
                        bytes = parseLong(flowData.get("bytes"));
                    } else if (flowData.containsKey("octets")) {
                        bytes = parseLong(flowData.get("octets"));
                    }

                    long packets = parseLong(flowData.get("packets"));
                    String protocolName = parseString(flowData.get("protocolName"));
                    String action = parseString(flowData.get("action"));

                    // 修复2: 只统计ACCEPT的流量
                    if (!"ACCEPT".equalsIgnoreCase(action)) {
                        log.debug("跳过非ACCEPT流量: action={}", action);
                        continue;
                    }

                    // 解析时间戳
                    Object datetime = topLevelData.get("datetime");
                    Object startTimeObj = flowData.get("startTime");
                    Instant timestamp = parseFlowLogsTimestamp(datetime, startTimeObj);

                    // 修复3: 更精确的流量方向判断
                    FlowDirection direction = determineFlowDirection(sourceAddress, destinationAddress, privateIP);

                    if (direction == FlowDirection.UNKNOWN) {
                        log.debug("跳过方向未知的流量: {} -> {}", sourceAddress, destinationAddress);
                        continue;
                    }

                    validRecords++;
                    if (direction == FlowDirection.INBOUND) {
                        inboundRecords++;
                    } else {
                        outboundRecords++;
                    }

                    // 按时间戳分组 - 修复4: 使用更精确的时间分组
                    String timeKey = timestamp.truncatedTo(ChronoUnit.MINUTES).toString();
                    FlowLogsDataPoint dataPoint = timePointMap.computeIfAbsent(timeKey, k -> {
                        FlowLogsDataPoint dp = new FlowLogsDataPoint();
                        dp.setTimestamp(timestamp.truncatedTo(ChronoUnit.MINUTES));
                        dp.setInboundBytes(0L);
                        dp.setOutboundBytes(0L);
                        dp.setInboundPackets(0L);
                        dp.setOutboundPackets(0L);
                        dp.setProtocol(protocolName);
                        dp.setAction(action);
                        return dp;
                    });

                    // 修复5: 更准确的累加逻辑
                    if (direction == FlowDirection.INBOUND) {
                        dataPoint.setInboundBytes(dataPoint.getInboundBytes() + bytes);
                        dataPoint.setInboundPackets(dataPoint.getInboundPackets() + packets);
                        totalInbound += bytes;
                        totalInboundPackets += packets;
                    } else if (direction == FlowDirection.OUTBOUND) {
                        dataPoint.setOutboundBytes(dataPoint.getOutboundBytes() + bytes);
                        dataPoint.setOutboundPackets(dataPoint.getOutboundPackets() + packets);
                        totalOutbound += bytes;
                        totalOutboundPackets += packets;
                    }

                    // 调试日志
                    if (validRecords <= 5) {
                        log.debug("Flow记录 {}: {} -> {}, 方向: {}, 字节: {}, 协议: {}, 动作: {}",
                                validRecords, sourceAddress, destinationAddress, direction,
                                formatBytes(bytes), protocolName, action);
                    }

                } catch (Exception e) {
                    log.debug("解析Flow Logs记录失败: " + e.getMessage());
                    continue;
                }
            }

            log.info("Flow Logs解析完成 - 有效记录: {}, 入站记录: {}, 出站记录: {}",
                    validRecords, inboundRecords, outboundRecords);

            // 转换为有序列表
            dataPoints = timePointMap.values().stream()
                    .sorted(Comparator.comparing(FlowLogsDataPoint::getTimestamp))
                    .collect(Collectors.toList());
        }

        stats.setTotalInboundBytes(totalInbound);
        stats.setTotalOutboundBytes(totalOutbound);
        stats.setTotalInboundPackets(totalInboundPackets);
        stats.setTotalOutboundPackets(totalOutboundPackets);
        stats.setDataPoints(dataPoints);
        stats.setTotalFlow(totalInbound + totalOutbound);

        return stats;
    }

    private enum FlowDirection {
        INBOUND,    // 入站：外部 -> 私有IP
        OUTBOUND,   // 出站：私有IP -> 外部
        UNKNOWN     // 未知方向
    }

    private static FlowDirection determineFlowDirection(String sourceAddress, String destinationAddress, String privateIP) {
        // 基本方向判断
        boolean sourceIsPrivate = privateIP.equals(sourceAddress);
        boolean destIsPrivate = privateIP.equals(destinationAddress);

        if (destIsPrivate && !sourceIsPrivate) {
            // 外部地址 -> 私有IP = 入站
            return FlowDirection.INBOUND;
        } else if (sourceIsPrivate && !destIsPrivate) {
            // 私有IP -> 外部地址 = 出站
            return FlowDirection.OUTBOUND;
        } else if (sourceIsPrivate && destIsPrivate) {
            // 内部通信，暂时归类为出站
            return FlowDirection.OUTBOUND;
        } else {
            // 两个都不是目标IP，理论上不应该出现
            return FlowDirection.UNKNOWN;
        }
    }

    public static void debugTrafficComparison(FlowLogsTrafficStats stats) {
        log.info("=== 流量统计对比调试 ===");
        log.info("实例: {}, IP: {}", stats.getInstanceId(), stats.getPrivateIP());
        log.info("时间范围: {} 到 {}", stats.getStartTime(), stats.getEndTime());

        // 高精度显示
        log.info("入站流量: {} ({} bytes)", formatBytesWithPrecision(stats.getTotalInboundBytes()), stats.getTotalInboundBytes());
        log.info("出站流量: {} ({} bytes)", formatBytesWithPrecision(stats.getTotalOutboundBytes()), stats.getTotalOutboundBytes());
        log.info("总流量: {} ({} bytes)", formatBytesWithPrecision(stats.getTotalFlow()), stats.getTotalFlow());

        // MB级别对比
        double inboundMB = stats.getTotalInboundBytes() / (1024.0 * 1024.0);
        double outboundMB = stats.getTotalOutboundBytes() / (1024.0 * 1024.0);
        log.info("MB级别 - 入站: {:.6f} MB, 出站: {:.6f} MB", inboundMB, outboundMB);

        // 数据点分析
        log.info("数据点数量: {}", stats.getDataPoints().size());
        if (!stats.getDataPoints().isEmpty()) {
            long maxInbound = stats.getDataPoints().stream().mapToLong(FlowLogsDataPoint::getInboundBytes).max().orElse(0);
            long maxOutbound = stats.getDataPoints().stream().mapToLong(FlowLogsDataPoint::getOutboundBytes).max().orElse(0);
            log.info("单个数据点最大入站: {}, 最大出站: {}", formatBytes(maxInbound), formatBytes(maxOutbound));
        }

        log.info("建议检查项:");
        log.info("1. Oracle控制台显示的时间范围是否与查询时间一致");
        log.info("2. 控制台是否包含了被拒绝的流量(REJECT)");
        log.info("3. 控制台是否按不同的聚合粒度显示数据");
        log.info("4. 检查是否有其他网络接口的流量");
    }

    public static String formatBytesWithPrecision(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return String.format("%.3f KB", bytes / 1024.0);
        if (bytes < 1024 * 1024 * 1024) return String.format("%.3f MB", bytes / (1024.0 * 1024));
        return String.format("%.3f GB", bytes / (1024.0 * 1024 * 1024));
    }

    /**
     * 显示流量统计结果
     */
    private static void displayTrafficStats(FlowLogsTrafficStats stats) {
        log.info("=== 流量统计结果 ===");
        log.info("实例ID: {}", stats.getInstanceId());
        log.info("私有IP: {}", stats.getPrivateIP());
        log.info("查询时间: {} ~ {}", stats.getStartTime(), stats.getEndTime());
        log.info("入站流量: {} ({} 包)", formatBytes(stats.getTotalInboundBytes()), stats.getTotalInboundPackets());
        log.info("出站流量: {} ({} 包)", formatBytes(stats.getTotalOutboundBytes()), stats.getTotalOutboundPackets());
        log.info("数据点数量: {}", stats.getDataPoints().size());

        if (!stats.getDataPoints().isEmpty()) {
            log.info("=== 前3个数据点 ===");
            stats.getDataPoints().stream().limit(3).forEach(point -> {
                log.info("时间: {}, 入站: {}, 出站: {}, 协议: {}",
                        point.getTimestamp(),
                        formatBytes(point.getInboundBytes()),
                        formatBytes(point.getOutboundBytes()),
                        point.getProtocol());
            });
        }
    }



    /**
     * 获取Flow Logs的Log Group ID
     */
    private static String getFlowLogsGroupId(Tenant tenant, String compartmentId) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LoggingManagementClient loggingClient = LoggingManagementClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                loggingClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                // 查询所有Log Groups
                ListLogGroupsRequest request = ListLogGroupsRequest.builder()
                        .compartmentId(compartmentId)
                        .build();

                ListLogGroupsResponse response = loggingClient.listLogGroups(request);

                // 查找Flow Logs相关的Log Group
                for (LogGroupSummary logGroupSummary : response.getItems()) {
                    String displayName = logGroupSummary.getDisplayName();

                    // 检查是否是Flow Logs的Log Group
                    if (displayName != null && (
                            displayName.toLowerCase().contains("flowlogs") ||
                                    displayName.toLowerCase().contains("flow-logs") ||
                                    displayName.toLowerCase().contains("vcn-flowlogs") ||
                                    displayName.equals("vcn-flowlogs-group")
                    )) {
                        log.info("找到Flow Logs Group: {} (ID: {})", displayName, logGroupSummary.getId());
                        return logGroupSummary.getId();
                    }
                }

                // 如果没找到明确的Flow Logs Group，检查每个Group中的Logs
                for (LogGroupSummary logGroupSummary : response.getItems()) {
                    if (containsFlowLogs(loggingClient, logGroupSummary.getId())) {
                        log.info("在Log Group {} 中找到Flow Logs配置", logGroupSummary.getDisplayName());
                        return logGroupSummary.getId();
                    }
                }

                log.warn("未找到Flow Logs Group");
                return null;

            }
        } catch (Exception e) {
            log.error("获取Flow Logs Group ID失败: " + e.getMessage(), e);
            return null;
        }
    }

    /**
     * 检查Log Group中是否包含Flow Logs
     */
    private static boolean containsFlowLogs(LoggingManagementClient loggingClient, String logGroupId) {
        try {
            ListLogsRequest logsRequest = ListLogsRequest.builder()
                    .logGroupId(logGroupId)
                    .build();

            ListLogsResponse logsResponse = loggingClient.listLogs(logsRequest);

            for (LogSummary logSummary : logsResponse.getItems()) {
                try {
                    // 获取Log详情
                    GetLogRequest getLogRequest = GetLogRequest.builder()
                            .logGroupId(logGroupId)
                            .logId(logSummary.getId())
                            .build();

                    GetLogResponse getLogResponse = loggingClient.getLog(getLogRequest);
                    Log ociLog = getLogResponse.getLog();

                    // 检查配置中是否是Flow Logs
                    if (ociLog.getConfiguration() != null &&
                            ociLog.getConfiguration().getSource() != null &&
                            ociLog.getConfiguration().getSource() instanceof OciService) {

                        OciService ociService = (OciService) ociLog.getConfiguration().getSource();

                        if ("flowlogs".equals(ociService.getService())) {
                            return true;
                        }
                    }
                } catch (Exception e) {
                    log.debug("检查Log详情失败，跳过: " + e.getMessage());
                    continue;
                }
            }

            return false;
        } catch (Exception e) {
            log.debug("检查Log Group中的Flow Logs失败: " + e.getMessage());
            return false;
        }
    }

    /**
     * 获取所有Flow Logs相关的Log Group信息（调试用）
     */
    public static void debugAllFlowLogsGroups(Tenant tenant, String compartmentId) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LoggingManagementClient loggingClient = LoggingManagementClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                loggingClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                ListLogGroupsRequest request = ListLogGroupsRequest.builder()
                        .compartmentId(compartmentId)
                        .build();

                ListLogGroupsResponse response = loggingClient.listLogGroups(request);

                log.info("=== 所有Log Groups信息 ===");
                for (LogGroupSummary logGroupSummary : response.getItems()) {
                    log.info("Log Group: {} (ID: {}, 状态: {})",
                            logGroupSummary.getDisplayName(),
                            logGroupSummary.getId(),
                            logGroupSummary.getLifecycleState());

                    // 查询每个Log Group中的Logs
                    ListLogsRequest logsRequest = ListLogsRequest.builder()
                            .logGroupId(logGroupSummary.getId())
                            .build();

                    ListLogsResponse logsResponse = loggingClient.listLogs(logsRequest);

                    for (LogSummary logSummary : logsResponse.getItems()) {
                        log.info("  Log: {} (ID: {}, 状态: {})",
                                logSummary.getDisplayName(),
                                logSummary.getId(),
                                logSummary.getLifecycleState());

                        try {
                            // 获取Log详情
                            GetLogRequest getLogRequest = GetLogRequest.builder()
                                    .logGroupId(logGroupSummary.getId())
                                    .logId(logSummary.getId())
                                    .build();

                            GetLogResponse getLogResponse = loggingClient.getLog(getLogRequest);
                            Log ociLog = getLogResponse.getLog();

                            if (ociLog.getConfiguration() != null &&
                                    ociLog.getConfiguration().getSource() instanceof OciService) {
                                OciService source = (OciService) ociLog.getConfiguration().getSource();
                                log.info("    Service: {}, Resource: {}, Category: {}",
                                        source.getService(),
                                        source.getResource(),
                                        source.getCategory());

                                if ("flowlogs".equals(source.getService())) {
                                    log.info("    ✓ 这是Flow Logs配置");
                                }
                            }
                        } catch (Exception e) {
                            log.debug("获取Log详情失败: " + e.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.error("调试所有Flow Logs Groups失败", e);
        }
    }

    /**
     * 修复后的时间戳解析方法
     */
    private static Instant parseFlowLogsTimestamp(Object datetime, Object startTime) {
        // 优先使用 datetime 字段 (毫秒时间戳)
        if (datetime instanceof Long) {
            return Instant.ofEpochMilli((Long) datetime);
        }

        // 如果没有 datetime，使用 startTime (秒时间戳)
        if (startTime instanceof Integer) {
            return Instant.ofEpochSecond(((Integer) startTime).longValue());
        }

        if (startTime instanceof Long) {
            long timestamp = (Long) startTime;
            // 判断是秒还是毫秒时间戳
            if (timestamp > 1000000000000L) {
                // 毫秒时间戳
                return Instant.ofEpochMilli(timestamp);
            } else {
                // 秒时间戳
                return Instant.ofEpochSecond(timestamp);
            }
        }

        // 如果都解析不了，使用当前时间
        log.warn("无法解析时间戳，使用当前时间: datetime={}, startTime={}", datetime, startTime);
        return Instant.now();
    }



    /**
     * 根据显示名称查找Log Group ID
     */
    public static String getLogGroupIdByDisplayName(Tenant tenant, String compartmentId, String displayName) {
        try {
            final SimpleAuthenticationDetailsProvider provider = getProvider(tenant);

            try (LoggingManagementClient loggingClient = LoggingManagementClient.builder().clientConfigurator(ProxyContext.get()).build(provider)) {
                loggingClient.setRegion(RegionEnum.getRegionCode(tenant.getRegion()));

                ListLogGroupsRequest request = ListLogGroupsRequest.builder()
                        .compartmentId(compartmentId)
                        .displayName(displayName)
                        .build();

                ListLogGroupsResponse response = loggingClient.listLogGroups(request);

                if (!response.getItems().isEmpty()) {
                    LogGroupSummary logGroup = response.getItems().get(0);
                    log.info("找到Log Group: {} (ID: {})", logGroup.getDisplayName(), logGroup.getId());
                    return logGroup.getId();
                } else {
                    log.warn("未找到显示名称为 '{}' 的Log Group", displayName);
                    return null;
                }
            }
        } catch (Exception e) {
            log.error("根据显示名称查找Log Group失败: " + e.getMessage(), e);
            return null;
        }
    }

}
