package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.InstanceTraffic;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

public interface InstanceTrafficRepository extends JpaRepository<InstanceTraffic, Long> , JpaSpecificationExecutor<InstanceTraffic> {


    /**
     * 根据统计日期查找流量数据
     * @param statsDate 统计日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByStatsDate(LocalDate statsDate);

    /**
     * 根据租户ID和统计日期查找流量数据
     * @param tenantId 租户ID
     * @param statsDate 统计日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByTenantIdAndStatsDate(Long tenantId, LocalDate statsDate);

    /**
     * 根据提供商租户ID和统计日期查找流量数据
     * @param tenancy 提供商租户ID
     * @param statsDate 统计日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByTenancyAndStatsDate(String tenancy, LocalDate statsDate);

    /**
     * 根据实例ID和日期范围查找流量数据
     * @param instanceId 实例ID
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByInstanceIdAndStatsDateBetween(
            String instanceId, LocalDate startDate, LocalDate endDate);

    /**
     * 根据租户ID和日期范围查找流量数据
     * @param tenantId 租户ID
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByTenantIdAndStatsDateBetween(
            Long tenantId, LocalDate startDate, LocalDate endDate);

    /**
     * 根据提供商租户ID和日期范围查找流量数据
     * @param tenancy 提供商租户ID
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByTenancyAndStatsDateBetween(
            String tenancy, LocalDate startDate, LocalDate endDate);

    /**
    * 按照实例分组查询
    */
    @Query("SELECT new InstanceTraffic(" +
            "t.instanceId, t.tenantId, t.tenancy, " +
            "SUM(t.ingressBytes), SUM(t.egressBytes), " +
            "MAX(t.statsDate)) " +
            "FROM InstanceTraffic t " +
            "WHERE t.tenancy = :tenancy AND t.region IN :regions AND t.statsDate BETWEEN :startDate AND :endDate " +
            "GROUP BY t.instanceId")
    List<InstanceTraffic> findByTenancyAndStatsDateBetweenGroup(
            @Param("tenancy") String tenancy, @Param("regions")Set<String> regions, @Param("startDate")LocalDate startDate, @Param("endDate")LocalDate endDate);

    /**
     * 查找指定日期范围内的所有流量数据
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 流量数据列表
     */
    List<InstanceTraffic> findByStatsDateBetween(LocalDate startDate, LocalDate endDate);


    @Query("SELECT new com.doubledimple.dao.entity.InstanceTraffic(" +
            "t.instanceId, t.tenantId, t.tenancy, " +
            "SUM(t.ingressBytes), SUM(t.egressBytes), " +
            "MAX(t.statsDate)) " +
            "FROM InstanceTraffic t " +
            "WHERE t.statsDate BETWEEN :startDate AND :endDate " +
            "GROUP BY t.instanceId")
    List<InstanceTraffic> findByStatsDateBetweenGroup(
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);

    /**
     * 查找指定实例的最新流量记录
     * @param instanceId 实例ID
     * @return 最新的流量记录
     */
    Optional<InstanceTraffic> findTopByInstanceIdOrderByStatsDateDesc(String instanceId);

    /**
     * 根据实例ID查找流量记录
     * @param instanceId 实例ID
     * @return 流量记录
     */
    Optional<InstanceTraffic> findByInstanceId(String instanceId);

    /**
     * 根据实例ID和统计日期查找流量记录
     * @param instanceId 实例ID
     * @param statsDate 统计日期
     * @return 流量记录
     */
    Optional<InstanceTraffic> findByInstanceIdAndStatsDate(String instanceId, LocalDate statsDate);

    /**
     * 根据实例ID查询当月（从当月第一天到当前日期）的流量数据
     * @param instanceId 实例ID
     * @return 当月指定实例的流量数据列表
     */
    default List<InstanceTraffic> findCurrentMonthTrafficByInstanceId(String instanceId) {
        LocalDate today = LocalDate.now();
        LocalDate firstDayOfMonth = today.withDayOfMonth(1);
        return findByInstanceIdAndStatsDateBetween(instanceId, firstDayOfMonth, today);
    }

    /**
     * 计算指定实例在当月的总流量（入站+出站）
     * @param instanceId 实例ID
     * @return 当月总流量（Double类型）
     */
    default Double sumCurrentMonthTrafficByInstanceId(String instanceId) {
        List<InstanceTraffic> trafficList = findCurrentMonthTrafficByInstanceId(instanceId);
        return trafficList.stream()
                .mapToDouble(traffic ->
                        (traffic.getIngressBytes() == null ? 0.0 : traffic.getIngressBytes())  +
                                (traffic.getEgressBytes() == null ? 0.0 : traffic.getEgressBytes())) // 入站+出站
                .sum();
    }

    /**
     * 计算指定实例在日期范围内的总流量（入站+出站）
     * @param instanceId 实例ID
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 日期范围内的总流量（Double类型）
     */
    default Double sumTrafficByInstanceIdAndDateRange(String instanceId, LocalDate startDate, LocalDate endDate) {
        List<InstanceTraffic> trafficList = findByInstanceIdAndStatsDateBetween(instanceId, startDate, endDate);
        return trafficList.stream()
                .mapToDouble(traffic ->
                        (traffic.getIngressBytes() == null ? 0.0 : traffic.getIngressBytes())  +
                                (traffic.getEgressBytes() == null ? 0.0 : traffic.getEgressBytes()))
                .sum();
    }

    /**
     * 使用SQL原生查询计算指定实例在日期范围内的总流量（入站+出站）
     * 当数据量较大时，直接在数据库层面计算总和可能更高效
     */
    @Query("SELECT SUM(t.ingressBytes + t.egressBytes) FROM InstanceTraffic t WHERE t.instanceId = :instanceId " +
            "AND t.statsDate BETWEEN :startDate AND :endDate")
    Double sumTotalTrafficForInstance(@Param("instanceId") String instanceId,
                                      @Param("startDate") LocalDate startDate,
                                      @Param("endDate") LocalDate endDate);

    /**
     * 便捷方法：使用SQL原生查询计算当月总流量（入站+出站）
     */
    default Double sumCurrentMonthTotalTrafficByInstanceId(String instanceId) {
        LocalDate today = LocalDate.now();
        LocalDate firstDayOfMonth = today.withDayOfMonth(1);
        return sumTotalTrafficForInstance(instanceId, firstDayOfMonth, today);
    }

    /**
     * 分别计算入站和出站流量总和
     * @param instanceId 实例ID
     * @return 包含入站和出站流量总和的Map
     */
    default Map<String, Double> sumInboundAndOutboundTrafficByInstanceId(String instanceId) {
        List<InstanceTraffic> trafficList = findCurrentMonthTrafficByInstanceId(instanceId);
        double totalInbound = trafficList.stream().mapToDouble(InstanceTraffic::getIngressBytes).sum();
        double totalOutbound = trafficList.stream().mapToDouble(InstanceTraffic::getEgressBytes).sum();

        Map<String, Double> result = new HashMap<>();
        result.put("inbound", totalInbound);
        result.put("outbound", totalOutbound);
        result.put("total", totalInbound + totalOutbound);

        return result;
    }

    /**
     * 根据提供商租户ID查询当月（从当月第一天到当前日期）的流量数据
     * @param tenancy 提供商租户ID
     * @return 当月指定提供商租户的流量数据列表
     */
    default List<InstanceTraffic> findCurrentMonthTrafficByTenancy(String tenancy) {
        LocalDate today = LocalDate.now();
        LocalDate firstDayOfMonth = today.withDayOfMonth(1);
        return findByTenancyAndStatsDateBetween(tenancy, firstDayOfMonth, today);
    }

    /**
     * 计算指定提供商租户在当月的总流量（入站+出站）
     * @param tenancy 提供商租户ID
     * @return 当月总流量（Double类型）
     */
    default Double sumCurrentMonthTrafficByTenancy(String tenancy) {
        List<InstanceTraffic> trafficList = findCurrentMonthTrafficByTenancy(tenancy);
        return trafficList.stream()
                .mapToDouble(traffic ->
                        (traffic.getIngressBytes() == null ? 0.0 : traffic.getIngressBytes())  +
                                (traffic.getEgressBytes() == null ? 0.0 : traffic.getEgressBytes()))
                .sum();
    }

    /**
     * 计算指定提供商租户在日期范围内的总流量（入站+出站）
     * @param tenancy 提供商租户ID
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @return 日期范围内的总流量（Double类型）
     */
    default Double sumTrafficByTenancyAndDateRange(String tenancy, LocalDate startDate, LocalDate endDate) {
        List<InstanceTraffic> trafficList = findByTenancyAndStatsDateBetween(tenancy, startDate, endDate);
        return trafficList.stream()
                .mapToDouble(traffic ->
                        (traffic.getIngressBytes() == null ? 0.0 : traffic.getIngressBytes())  +
                                (traffic.getEgressBytes() == null ? 0.0 : traffic.getEgressBytes()))
                .sum();
    }

    /**
     * 使用SQL原生查询计算指定提供商租户在日期范围内的总流量（入站+出站）
     */
    @Query("SELECT SUM(t.ingressBytes + t.egressBytes) FROM InstanceTraffic t WHERE t.tenancy = :tenancy " +
            "AND t.statsDate BETWEEN :startDate AND :endDate")
    Double sumTotalTrafficForTenancy(@Param("tenancy") String tenancy,
                                     @Param("startDate") LocalDate startDate,
                                     @Param("endDate") LocalDate endDate);

    /**
     * 便捷方法：使用SQL原生查询计算当月提供商租户总流量（入站+出站）
     */
    default Double sumCurrentMonthTotalTrafficByTenancy(String tenancy) {
        LocalDate today = LocalDate.now();
        LocalDate firstDayOfMonth = today.withDayOfMonth(1);
        return sumTotalTrafficForTenancy(tenancy, firstDayOfMonth, today);
    }

    /**
     * 分别计算提供商租户入站和出站流量总和
     * @param tenancy 提供商租户ID
     * @return 包含入站和出站流量总和的Map
     */
    default Map<String, Double> sumInboundAndOutboundTrafficByTenancy(String tenancy) {
        List<InstanceTraffic> trafficList = findCurrentMonthTrafficByTenancy(tenancy);
        double totalInbound = trafficList.stream().mapToDouble(InstanceTraffic::getIngressBytes).sum();
        double totalOutbound = trafficList.stream().mapToDouble(InstanceTraffic::getEgressBytes).sum();

        Map<String, Double> result = new HashMap<>();
        result.put("inbound", totalInbound);
        result.put("outbound", totalOutbound);
        result.put("total", totalInbound + totalOutbound);

        return result;
    }

    /**
     * 获取提供商租户当月流量信息（GB格式）
     */
    default Map<String, String> getFormattedTrafficDetailsByTenancy(String tenancy) {
        Map<String, Double> bytesTraffic = sumInboundAndOutboundTrafficByTenancy(tenancy);

        // 转换为GB并格式化
        Map<String, String> gbTraffic = new HashMap<>();
        gbTraffic.put("inbound", String.format("%.2f GB", bytesTraffic.get("inbound") / (1024.0 * 1024.0 * 1024.0)));
        gbTraffic.put("outbound", String.format("%.2f GB", bytesTraffic.get("outbound") / (1024.0 * 1024.0 * 1024.0)));
        gbTraffic.put("total", String.format("%.2f GB", bytesTraffic.get("total") / (1024.0 * 1024.0 * 1024.0)));

        return gbTraffic;
    }

    /**
     * 统计指定租户在指定日期范围内的实例数量
     */
    @Query(value = "SELECT COUNT(*) FROM (" +
            "   SELECT DISTINCT instance_id FROM instance_traffic " +
            "   WHERE tenancy = :tenancy AND stats_date BETWEEN :startDate AND :endDate" +
            ") t",
            nativeQuery = true)
    long countByTenancyAndStatsDateBetween(
            @Param("tenancy") String tenancy,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);

    /**
     * 分页查询指定租户在指定日期范围内的流量数据
     * 按实例分组，每个实例仅返回一条最新记录
     */
    @Query(value = "SELECT t.* FROM (" +
            "   SELECT it.*, ROW_NUMBER() OVER (PARTITION BY it.instance_id ORDER BY it.stats_date DESC) as rn " +
            "   FROM instance_traffic it " +
            "   WHERE it.tenancy = :tenancy AND it.stats_date BETWEEN :startDate AND :endDate" +
            ") t " +
            "WHERE t.rn = 1 " +
            "ORDER BY t.stats_date DESC " +
            "LIMIT :#{#pageable.pageSize} OFFSET :#{#pageable.offset}",
            nativeQuery = true)
    List<InstanceTraffic> findByTenancyAndStatsDateBetweenGroupPaged(
            @Param("tenancy") String tenancy,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate,
            Pageable pageable);

    /**
     * 统计所有实例在指定日期范围内的数量
     */
    @Query(value = "SELECT COUNT(*) FROM (" +
            "   SELECT DISTINCT instance_id FROM instance_traffic " +
            "   WHERE stats_date BETWEEN :startDate AND :endDate" +
            ") t",
            nativeQuery = true)
    long countByStatsDateBetween(
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);

    /**
     * 分页查询所有实例在指定日期范围内的流量数据
     * 按实例分组，每个实例仅返回一条最新记录
     */
    @Query(value = "SELECT t.* FROM (" +
            "   SELECT it.*, ROW_NUMBER() OVER (PARTITION BY it.instance_id ORDER BY it.stats_date DESC) as rn " +
            "   FROM instance_traffic it " +
            "   WHERE it.stats_date BETWEEN :startDate AND :endDate" +
            ") t " +
            "WHERE t.rn = 1 " +
            "ORDER BY t.stats_date DESC " +
            "LIMIT :#{#pageable.pageSize} OFFSET :#{#pageable.offset}",
            nativeQuery = true)
    List<InstanceTraffic> findByStatsDateBetweenGroupPaged(
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate,
            Pageable pageable);

    @Query("SELECT new InstanceTraffic(" +
            "t.instanceId, t.tenantId, t.tenancy, " +
            "SUM(t.ingressBytes), SUM(t.egressBytes), " +
            "MAX(t.statsDate)) " +
            "FROM InstanceTraffic t " +
            "WHERE t.tenancy = :tenancy " +
            "AND t.region IN :regions " +
            "AND t.statsDate BETWEEN :startDate AND :endDate " +
            "GROUP BY t.instanceId, t.tenantId, t.tenancy")
    List<InstanceTraffic> findByTenancyAndRegionsAndStatsAndDateBetween(
            @Param("tenancy") String tenancy,
            @Param("regions") Set<String> regions,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);


    @Query("SELECT COALESCE(SUM(i.egressBytes),0) FROM InstanceTraffic i " +
            "WHERE i.tenancy = :tenancy " +
            "AND FUNCTION('YEAR', i.statsDate) = FUNCTION('YEAR', CURRENT_DATE) " +
            "AND FUNCTION('MONTH', i.statsDate) = FUNCTION('MONTH', CURRENT_DATE)")
    Double sumCurrentMonthEgressByTenancy(@Param("tenancy") String tenancy);

}
