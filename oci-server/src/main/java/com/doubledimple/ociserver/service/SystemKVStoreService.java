package com.doubledimple.ociserver.service;

public interface SystemKVStoreService {

    public void saveOrUpdate(String key, String value, String remark);

    public String getValue(String key);

    public <T> T getValueAsObject(String key, Class<T> clazz);


    public boolean isToday(String key);
}
