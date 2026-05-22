package com.doubledimple.ociserver.service.oracle.impl;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.InstanceTraffic;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.InstanceTrafficRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.enums.oci.TrafficPeriod;
import com.doubledimple.ociserver.service.oracle.InstanceTrafficService;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.response.InstanceTrafficVO;
import com.doubledimple.ociserver.pojo.response.ThresholdSettingDTO;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.doubledimple.ociserver.utils.oracle.TrafficMetricsUtils;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicCreationResult;
import com.doubledimple.ociserver.utils.oracle.vnic.VnicManagementUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.model.Instance;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeanUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import javax.annotation.Resource;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Queue;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName InstanceTrafficServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-10 17:33
 */
@Service
@Slf4j
public class InstanceTrafficServiceImpl implements InstanceTrafficService {

    @Resource
    private InstanceTrafficRepository instanceTrafficRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OracleInstanceService oracleInstanceService;

    @Resource
    OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Override
    public List<InstanceTrafficVO> getAllInstanceTraffic(String tenantId) {
        // 获取当天的统计数据
        LocalDate today = LocalDate.now();
        List<InstanceTraffic> trafficList = new ArrayList<>();

        if (StringUtils.hasText(tenantId)) {
            Long tenantIdLong = Long.parseLong(tenantId);
            Optional<Tenant> byId = tenantRepository.findById(tenantIdLong);
            if (byId.isPresent()){
                String tenantIdProvider = byId.get().getTenancy();
                trafficList = instanceTrafficRepository.findByTenancyAndStatsDate(tenantIdProvider, today);
            }
        } else {
            trafficList = instanceTrafficRepository.findByStatsDate(today);
        }

        List<InstanceTrafficVO> collect = trafficList.stream()
                .map(this::convertToVO)
                .collect(Collectors.toList());

        if (collect.size() > 0){
            oracleInstanceService.getInstanceDetails(collect);
        }
        return collect;
    }

    @Override
    public Map<String, Object> getTrafficTrend(String instanceId, String tenantId, Integer days) {
        LocalDate endDate = LocalDate.now();
        LocalDate startDate = endDate.minusDays(days);

        List<InstanceTraffic> trafficData = new ArrayList<>();

        if (StringUtils.hasText(instanceId)) {
            trafficData = instanceTrafficRepository.findByInstanceIdAndStatsDateBetween(
                    instanceId, startDate, endDate);
        } else if (StringUtils.hasText(tenantId)) {
            Long tenantIdLong = Long.parseLong(tenantId);
            Optional<Tenant> byId = tenantRepository.findById(tenantIdLong);
            if (byId.isPresent()){
                String tenancy = byId.get().getTenancy();
                trafficData = instanceTrafficRepository.findByTenancyAndStatsDateBetween(
                        tenancy, startDate, endDate);
            }
        } else {
            trafficData = instanceTrafficRepository.findByStatsDateBetween(startDate, endDate);
        }

        // 修改: 先按照日期分组，再计算每天的总流量
        Map<LocalDate, List<InstanceTraffic>> groupedByDate = trafficData.stream()
                .collect(Collectors.groupingBy(InstanceTraffic::getStatsDate));

        Map<LocalDate, Double> dailyTraffic = new HashMap<>();

        // 对每天的数据单独计算总流量
        for (Map.Entry<LocalDate, List<InstanceTraffic>> entry : groupedByDate.entrySet()) {
            double totalTraffic = entry.getValue().stream()
                    .mapToDouble(t -> (t.getIngressBytes() + t.getEgressBytes()) / (1024.0 * 1024.0 * 1024.0))
                    .sum();
            dailyTraffic.put(entry.getKey(), totalTraffic);
        }

        // 按日期排序
        List<LocalDate> sortedDates = dailyTraffic.keySet().stream()
                .sorted()
                .collect(Collectors.toList());

        List<String> formattedDates = sortedDates.stream()
                .map(LocalDate::toString)
                .collect(Collectors.toList());

        List<Double> sortedTraffic = sortedDates.stream()
                .map(dailyTraffic::get)
                .map(value -> Math.round(value * 100.0) / 100.0) // 保留两位小数
                .collect(Collectors.toList());

        Map<String, Object> result = new HashMap<>();
        result.put("dates", formattedDates);
        result.put("traffic", sortedTraffic);

        return result;
    }

    @Override
    @Transactional
    public void setTrafficThreshold(ThresholdSettingDTO setting) {
        // 先查找当天的记录
        LocalDate today = LocalDate.now();
        Optional<InstanceTraffic> todayRecord = instanceTrafficRepository
                .findByInstanceIdAndStatsDate(setting.getInstanceId(), today);

        if (todayRecord.isPresent()) {
            // 更新当天记录
            InstanceTraffic traffic = todayRecord.get();
            traffic.setThreshold(setting.getThreshold());
            traffic.setAutoShutdown(setting.getAutoShutdown());
            instanceTrafficRepository.save(traffic);
        } else {
            // 查找最新的实例流量记录
            Optional<InstanceTraffic> latest = instanceTrafficRepository
                    .findTopByInstanceIdOrderByStatsDateDesc(setting.getInstanceId());

            if (latest.isPresent()) {
                InstanceTraffic traffic = latest.get();
                traffic.setThreshold(setting.getThreshold());
                traffic.setAutoShutdown(setting.getAutoShutdown());
                instanceTrafficRepository.save(traffic);
            } else {
                // 没有找到记录，创建一个新记录
                InstanceTraffic newTraffic = new InstanceTraffic();
                newTraffic.setInstanceId(setting.getInstanceId());
                newTraffic.setThreshold(setting.getThreshold());
                newTraffic.setAutoShutdown(setting.getAutoShutdown());
                newTraffic.setIngressBytes(0.0);
                newTraffic.setEgressBytes(0.0);
                newTraffic.setStatsDate(today);
                instanceTrafficRepository.save(newTraffic);
            }
        }
    }

    @Override
    public List<InstanceTrafficVO> getAllInstanceTraffic(List<String> tenantIds, LocalDate startDate, LocalDate endDate, String period) {
        TrafficPeriod trafficPeriod = Arrays.stream(TrafficPeriod.values())
                .filter(p -> p.getValue().equalsIgnoreCase(period))
                .findFirst()
                .orElse(TrafficPeriod.ONE_DAY);

        // 获取租户
        List<Tenant> tenants = (tenantIds != null && !tenantIds.isEmpty())
                ? tenantIds.stream()
                .map(id -> tenantRepository.findById(Long.parseLong(id)))
                .filter(Optional::isPresent)
                .map(Optional::get)
                .collect(Collectors.toList())
                : tenantRepository.findAll();

        // 时间转换 UTC
        ZonedDateTime startUtc = startDate.atStartOfDay(ZoneOffset.UTC);
        ZonedDateTime endUtc = endDate.plusDays(1).atStartOfDay(ZoneOffset.UTC);
        Date startTime = Date.from(startUtc.toInstant());
        Date endTime = Date.from(endUtc.toInstant());

        // 使用线程安全容器，避免并行流写冲突
        Queue<InstanceTrafficVO> resultQueue = new ConcurrentLinkedQueue<>();

        // 并行处理所有租户
        tenants.forEach(tenant -> {
            try {
                List<InstanceDetails> instanceDetailsList = oracleInstanceDetailRepository.findByTenantId(tenant.getId());

                // 如果没有存储实例信息，则实时查询 OCI
                if (instanceDetailsList.isEmpty()) {
                    SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);
                    List<Instance> instances = oracleInstanceService.getAllInstances(provider);

                    instances.parallelStream().forEach(instance -> {
                        List<String> vnicIdList = getUniqueVnicIds(tenant, instance.getId(),instance.getCompartmentId());
                        Map<LocalDateTime, Double> ingressMap = TrafficMetricsUtils.getInstanceTrafficByPeriod(
                                tenant, vnicIdList, false, startTime, endTime, trafficPeriod,instance.getCompartmentId());
                        Map<LocalDateTime, Double> egressMap = TrafficMetricsUtils.getInstanceTrafficByPeriod(
                                tenant, vnicIdList, true, startTime, endTime, trafficPeriod,instance.getCompartmentId());

                        mergeTrafficData(resultQueue, tenant, instance.getId(),
                                instance.getDisplayName(), null, startDate, endDate, period, ingressMap, egressMap);
                    });

                } else {
                    // 已有实例信息
                    instanceDetailsList.parallelStream().forEach(instanceDetail -> {
                        List<String> vnicIdList = getUniqueVnicIds(tenant, instanceDetail);
                        Map<LocalDateTime, Double> ingressMap = TrafficMetricsUtils.getInstanceTrafficByPeriod(
                                tenant, vnicIdList, false, startTime, endTime, trafficPeriod,instanceDetail.getCompartmentId());
                        Map<LocalDateTime, Double> egressMap = TrafficMetricsUtils.getInstanceTrafficByPeriod(
                                tenant, vnicIdList, true, startTime, endTime, trafficPeriod,instanceDetail.getCompartmentId());

                        mergeTrafficData(resultQueue, tenant, instanceDetail.getInstanceId(),
                                instanceDetail.getDisplayName(), instanceDetail.getPublicIps(),
                                startDate, endDate, period, ingressMap, egressMap);
                    });
                }
            } catch (Exception e) {
                log.error("❌ 并行查询租户 [{}] 实例流量失败: {}", tenant.getTenancy(), e.getMessage(), e);
            }
        });

        return new ArrayList<>(resultQueue);
    }

    private List<String> getUniqueVnicIds(Tenant tenant, String instanceId,String compartmentId) {
        return VnicManagementUtils.getInstanceVnics(tenant, instanceId,compartmentId).stream()
                .map(VnicCreationResult::getVnicId)
                .filter(Objects::nonNull).distinct().collect(Collectors.toList());
    }

    private List<String> getUniqueVnicIds(Tenant tenant, InstanceDetails instanceDetail) {
        if (instanceDetail.getVnicIds() == null) {
            return getUniqueVnicIds(tenant, instanceDetail.getInstanceId(),instanceDetail.getCompartmentId());
        }
        return Arrays.stream(instanceDetail.getVnicIds().split(","))
                .map(String::trim)
                .filter(org.apache.commons.lang3.StringUtils::isNotBlank)
                .collect(Collectors.toCollection(LinkedHashSet::new))
                .stream().collect(Collectors.toList());
    }

    private void mergeTrafficData(Queue<InstanceTrafficVO> resultQueue,
                                  Tenant tenant,
                                  String instanceId,
                                  String instanceName,
                                  String publicIp,
                                  LocalDate startDate,
                                  LocalDate endDate,
                                  String period,
                                  Map<LocalDateTime, Double> ingressMap,
                                  Map<LocalDateTime, Double> egressMap) {

        Set<LocalDateTime> allTimes = new TreeSet<>();
        allTimes.addAll(ingressMap.keySet());
        allTimes.addAll(egressMap.keySet());

        for (LocalDateTime time : allTimes) {
            InstanceTrafficVO vo = new InstanceTrafficVO();
            vo.setInstanceId(instanceId);
            vo.setInstanceName(instanceName);
            vo.setPublicIp(publicIp);
            vo.setTenancy(tenant.getTenancy());
            vo.setTenancyName(tenant.getTenancyName());
            vo.setStartDate(startDate);
            vo.setEndDate(endDate);
            vo.setPeriod(period);
            vo.setTimePoint(time);
            vo.setIngressBytes(ingressMap.getOrDefault(time, 0D));
            vo.setEgressBytes(egressMap.getOrDefault(time, 0D));
            resultQueue.add(vo);
        }
    }


    @Override
    public Map<String, Object> getTrafficTrend(String instanceId, List<String> tenantIds, LocalDate startDate, LocalDate endDate) {
        List<InstanceTraffic> trafficData = new ArrayList<>();
        if (StringUtils.hasText(instanceId)) {
            trafficData = instanceTrafficRepository.findByInstanceIdAndStatsDateBetween(
                    instanceId, startDate, endDate);
        } else if (tenantIds != null && !tenantIds.isEmpty()) {
            Set<String> regions = new HashSet<>();
            String tenancy = "";
            for (String tenantId : tenantIds) {
                Long tenantIdLong = Long.parseLong(tenantId);
                Optional<Tenant> tenant = tenantRepository.findById(tenantIdLong);
                if (tenant.isPresent()) {
                    tenancy = tenant.get().getTenancy();
                    regions.addAll(RegionEnum.getRegions(tenant.get().getRegion()));
                }
            }

            if (tenancy != "" && regions.size() > 0){
                trafficData = instanceTrafficRepository.findByTenancyAndRegionsAndStatsAndDateBetween(
                        tenancy,regions, startDate, endDate);
            }
        } else {
            trafficData = instanceTrafficRepository.findByStatsDateBetween(startDate, endDate);
        }

        // 按日期分组计算流量
        Map<LocalDate, List<InstanceTraffic>> groupedByDate = trafficData.stream()
                .collect(Collectors.groupingBy(InstanceTraffic::getStatsDate));

        Map<LocalDate, Double> dailyTraffic = new HashMap<>();

        // 对每天的数据单独计算总流量
        for (Map.Entry<LocalDate, List<InstanceTraffic>> entry : groupedByDate.entrySet()) {
            double totalTraffic = entry.getValue().stream()
                    .mapToDouble(t -> (t.getIngressBytes() + t.getEgressBytes()) / (1024.0 * 1024.0 * 1024.0))
                    .sum();
            dailyTraffic.put(entry.getKey(), totalTraffic);
        }

        // 生成连续的日期列表
        List<String> formattedDates = new ArrayList<>();
        List<Double> trafficValues = new ArrayList<>();

        LocalDate currentDate = startDate;
        while (!currentDate.isAfter(endDate)) {
            formattedDates.add(currentDate.toString());
            // 如果该日期没有数据，使用0.0，否则使用计算得到的流量值
            // 使用Math.round和除法来保留两位小数
            double trafficValue = Math.round(dailyTraffic.getOrDefault(currentDate, 0.0) * 100.0) / 100.0;
            trafficValues.add(trafficValue);

            currentDate = currentDate.plusDays(1);
        }

        Map<String, Object> result = new HashMap<>();
        result.put("dates", formattedDates);
        result.put("traffic", trafficValues);

        return result;
    }


    private InstanceTrafficVO convertToVO(InstanceTraffic traffic) {
        InstanceTrafficVO vo = new InstanceTrafficVO();
        BeanUtils.copyProperties(traffic, vo);
        vo.setTotalBytes(traffic.getIngressBytes() + traffic.getEgressBytes());
        return vo;
    }
}
