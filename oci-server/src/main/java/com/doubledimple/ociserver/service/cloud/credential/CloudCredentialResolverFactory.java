package com.doubledimple.ociserver.service.cloud.credential;

import com.doubledimple.ocicommon.enums.CloudTypeEnum;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Component
public class CloudCredentialResolverFactory {

    private final Map<CloudTypeEnum, CloudCredentialResolver> map = new HashMap<CloudTypeEnum, CloudCredentialResolver>();

    public CloudCredentialResolverFactory(List<CloudCredentialResolver> resolvers) {
        if (resolvers != null) {
            for (CloudCredentialResolver resolver : resolvers) {
                map.put(resolver.getCloudType(), resolver);
            }
        }
    }

    public CloudCredentialResolver get(CloudTypeEnum type) {
        CloudCredentialResolver resolver = map.get(type);
        if (resolver == null) {
            throw new IllegalArgumentException("不支持的云厂商凭证解析: " + type);
        }
        return resolver;
    }

    public CloudCredentialResolver get(int cloudType) {
        CloudTypeEnum type = CloudTypeEnum.getCloudTypeEnum(cloudType);
        if (type == null) {
            throw new IllegalArgumentException("未知云厂商类型: " + cloudType);
        }
        return get(type);
    }
}
