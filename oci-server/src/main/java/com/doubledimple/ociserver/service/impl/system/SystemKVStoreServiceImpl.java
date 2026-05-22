package com.doubledimple.ociserver.service.impl.system;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.SystemKVStore;
import com.doubledimple.dao.repository.SystemKVStoreRepository;
import com.doubledimple.ociserver.service.SystemKVStoreService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName SystemKVStoreService
 * @Description TODO
 * @Author renyx
 * @Date 2025-11-25 16:31
 */
@Service
@Slf4j
public class SystemKVStoreServiceImpl implements SystemKVStoreService {


    @Resource
    private SystemKVStoreRepository repository;

    @Override
    public void saveOrUpdate(String key, String value, String remark) {
        SystemKVStore kv = repository.findByKey(key)
                .orElseGet(SystemKVStore::new);

        kv.setKey(key);
        kv.setLocalValue(value);
        kv.setRemark(remark);
        LocalDateTime now = LocalDateTime.now();
        kv.setUpdateTime(now);
        repository.save(kv);
    }

    @Override
    public String getValue(String key) {
        return repository.findByKey(key)
                .map(SystemKVStore::getLocalValue)
                .orElse(null);
    }

    @Override
    public <T> T getValueAsObject(String key, Class<T> clazz) {
        String json = getValue(key);
        return json == null ? null : JSON.parseObject(json, clazz);
    }


    @Override
    public boolean isToday(String key) {
        Optional<SystemKVStore> opt = repository.findByKey(key);
        if (!opt.isPresent()) {
            return false;
        }

        SystemKVStore kv = opt.get();
        LocalDate updateTime = kv.getUpdateTime().toLocalDate();
        LocalDate today = LocalDate.now();

        return updateTime.equals(today);
    }

}
