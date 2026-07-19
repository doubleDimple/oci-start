package com.doubledimple.ociserver.service.cloud;

import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 多云实例服务工厂。新增实现类自动注册，无需修改本类。
 */
@Component
public class CloudInstanceServiceFactory {

    private final Map<CloudTypeEnum, CloudInstanceService> serviceMap = new HashMap<CloudTypeEnum, CloudInstanceService>();

    public CloudInstanceServiceFactory(List<CloudInstanceService> services) {
        if (services != null) {
            for (CloudInstanceService service : services) {
                serviceMap.put(service.getCloudType(), service);
            }
        }
    }

    public CloudInstanceService get(CloudTypeEnum type) {
        CloudInstanceService service = serviceMap.get(type);
        if (service == null) {
            throw new IllegalArgumentException("不支持的云厂商实例服务: " + type);
        }
        return service;
    }

    public CloudInstanceService get(int cloudType) {
        CloudTypeEnum type = CloudTypeEnum.getCloudTypeEnum(cloudType);
        if (type == null) {
            throw new IllegalArgumentException("未知云厂商类型: " + cloudType);
        }
        return get(type);
    }

    public boolean supports(CloudTypeEnum type) {
        return serviceMap.containsKey(type);
    }

    public boolean supports(int cloudType) {
        CloudTypeEnum type = CloudTypeEnum.getCloudTypeEnum(cloudType);
        return type != null && supports(type);
    }
}
