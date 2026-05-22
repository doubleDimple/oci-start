package com.doubledimple.ocicommon.cache;

import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.cache.caffeine.CaffeineCacheManager;

import java.util.concurrent.TimeUnit;

/**
 * @version 1.0.0
 * @ClassName CacheManagerFactory
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-18 14:57
 */
public class CacheManagerFactory {
    /**
     * 创建默认的缓存管理器
     */
    public static CaffeineCacheManager createDefault(String... cacheNames) {
        CaffeineCacheManager cacheManager = new CaffeineCacheManager(cacheNames);
        cacheManager.setCaffeine(Caffeine.newBuilder()
                .initialCapacity(100)
                .maximumSize(1000)
                .expireAfterAccess(30, TimeUnit.MINUTES)
                .expireAfterWrite(1, TimeUnit.HOURS)
                .recordStats());
        return cacheManager;
    }

    /**
     * 创建短期缓存管理器（较短的过期时间）
     */
    public static CaffeineCacheManager createShortTerm(String... cacheNames) {
        CaffeineCacheManager cacheManager = new CaffeineCacheManager(cacheNames);
        cacheManager.setCaffeine(Caffeine.newBuilder()
                .initialCapacity(50)
                .maximumSize(500)
                .expireAfterAccess(5, TimeUnit.MINUTES)
                .expireAfterWrite(10, TimeUnit.MINUTES)
                .recordStats());
        return cacheManager;
    }

    /**
     * 创建长期缓存管理器（较长的过期时间）
     */
    public static CaffeineCacheManager createLongTerm(String... cacheNames) {
        CaffeineCacheManager cacheManager = new CaffeineCacheManager(cacheNames);
        cacheManager.setCaffeine(Caffeine.newBuilder()
                .initialCapacity(200)
                .maximumSize(2000)
                .expireAfterAccess(1, TimeUnit.HOURS)
                .expireAfterWrite(12, TimeUnit.HOURS)
                .recordStats());
        return cacheManager;
    }

    /**
     * 使用自定义配置创建缓存管理器
     */
    public static CaffeineCacheManager create(
            int initialCapacity,
            int maximumSize,
            int expireAfterAccessMinutes,
            int expireAfterWriteMinutes,
            String... cacheNames) {

        CaffeineCacheManager cacheManager = new CaffeineCacheManager(cacheNames);
        cacheManager.setCaffeine(Caffeine.newBuilder()
                .initialCapacity(initialCapacity)
                .maximumSize(maximumSize)
                .expireAfterAccess(expireAfterAccessMinutes, TimeUnit.MINUTES)
                .expireAfterWrite(expireAfterWriteMinutes, TimeUnit.MINUTES)
                .recordStats());
        return cacheManager;
    }
}
