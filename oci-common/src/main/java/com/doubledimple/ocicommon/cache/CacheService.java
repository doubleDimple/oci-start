package com.doubledimple.ocicommon.cache;

import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import java.util.function.Supplier;

/**
 * @version 1.0.0
 * @ClassName CacheLoader
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-28 08:56
 */
@Slf4j
public class CacheService {
    private final CacheManager cacheManager;

    public CacheService(CacheManager cacheManager) {
        this.cacheManager = cacheManager;
    }

    public <T> T getFromCache(String key, Class<T> type, Supplier<T> loader) {
        try {
            Cache cache = cacheManager.getCache(key);
            if (cache == null) return loader.get();
            T value = cache.get(key, type);
            if (value == null) {
                value = loader.get();
                if (value != null) {
                    cache.put(key, value);
                }
            }
            return value;
        } catch (Exception e) {
            log.error("Cache operation failed for key: {}, falling back to loader", key, e);
            return loader.get();
        }
    }
}
