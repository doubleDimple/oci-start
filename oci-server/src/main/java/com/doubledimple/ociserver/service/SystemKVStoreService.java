package com.doubledimple.ociserver.service;

public interface SystemKVStoreService {

    public static final String SYSTEM_KV_STORE_ARM_RECORDS = "system_kv_store_arm_records";

    public void saveOrUpdate(String key, String value, String remark);

    public String getValue(String key);

    public <T> T getValueAsObject(String key, Class<T> clazz);


    public boolean isToday(String key);
}
