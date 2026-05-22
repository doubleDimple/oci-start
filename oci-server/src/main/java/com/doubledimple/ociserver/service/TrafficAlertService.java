package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.TrafficAlert;
import com.doubledimple.ociserver.pojo.request.TrafficAlertDTO;

public interface TrafficAlertService {

    /**
     * 获取指定租户的流量预警配置
     */
    TrafficAlertDTO getTrafficAlert(Long tenantId);


    /**
     * 保存或更新流量预警配置
     */
    TrafficAlert saveTrafficAlert(TrafficAlertDTO dto);

    /**
     * 删除流量预警配置
     */
     void deleteTrafficAlert(Long tenantId);

     boolean hasTrafficAlert(Long tenantId);
}
