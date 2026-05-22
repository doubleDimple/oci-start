package com.doubledimple.ociserver.service.oracle;

import com.doubledimple.ociserver.pojo.response.InstanceTrafficVO;
import com.doubledimple.ociserver.pojo.response.ThresholdSettingDTO;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public interface InstanceTrafficService {

    /**
     * 获取所有实例流量数据
     * @param tenantId 租户ID，可选参数
     * @return 实例流量数据列表
     */
    List<InstanceTrafficVO> getAllInstanceTraffic(String tenantId);

    /**
     * 获取实例流量趋势数据
     * @param instanceId 实例ID，可选参数
     * @param tenantId 租户ID，可选参数
     * @param days 天数
     * @return 流量趋势数据
     */
    Map<String, Object> getTrafficTrend(String instanceId, String tenantId, Integer days);

    /**
     * 设置实例流量阈值
     * @param setting 阈值设置
     */
    void setTrafficThreshold(ThresholdSettingDTO setting);

    List<InstanceTrafficVO> getAllInstanceTraffic(List<String> tenantIds, LocalDate startDate, LocalDate endDate,String period);

    Map<String, Object> getTrafficTrend(String instanceId, List<String> tenantIds, LocalDate startDate, LocalDate endDate);
}
