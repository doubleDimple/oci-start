package com.doubledimple.ocicommon.cache;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

/**
* 缓存bean初始化
*/
@Configuration
@ConditionalOnProperty(name = "spring.cache.type", havingValue = "caffeine")
@EnableCaching
public class CommonCacheAutoConfiguration {

    @Bean
    @Primary
    public CacheManager cacheManager() {
        return CacheManagerFactory.createDefault(CacheConstants.CACHE_NAMES);
    }


    @Bean("cacheManagerNetwork")
    public CacheManager cacheManagerNetwork() {
        return CacheManagerFactory.createLongTerm(CacheConstants.OCI_NET_WORK_KEY);
    }

    @Bean
    public CacheService cacheService(CacheManager cacheManager) {
        return new CacheService(cacheManager);
    }
}
