package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.TemInstance;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;

import java.util.List;

public interface TemInstanceService {

    public void deleteByTenancyAndRegionAndArchitecture(String tenancy, String regions, String type, SimpleAuthenticationDetailsProvider provider,String tmpInstanceId,boolean deleteInsFlag);

    List<TemInstance> findByTenancyAndRegionAndArchitecture(String tenancy, String region, String type);

    void save(TemInstance temInstance);

    TemInstance findByInstanceId(String instanceId);

    void deleteByTenancy(String tenancy, String regionCode, String helpArchitecture);
}
