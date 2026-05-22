package com.doubledimple.ociserver.service.factory;

import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import com.doubledimple.ociserver.service.CostService;
import com.doubledimple.ociserver.service.impl.OciCostServiceImpl;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName CloudCostServiceFactory
 * @Description TODO
 * @Author renyx
 * @Date 2025-11-30 08:26
 */
@Component
public class CloudCostServiceFactory {

    private final Map<CloudTypeEnum, CostService> serviceMap = new HashMap<>();

    public CloudCostServiceFactory(List<CostService> serviceList) {
        for (CostService service : serviceList) {
            serviceMap.put(service.getCloudType(), service);
        }
    }

    public CostService get(CloudTypeEnum type) {
        CostService service = serviceMap.get(type);
        if (service == null) {
            throw new IllegalArgumentException("不支持的云厂商类型: " + type);
        }
        return service;
    }
}
