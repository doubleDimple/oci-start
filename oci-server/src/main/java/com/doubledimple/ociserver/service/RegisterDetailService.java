package com.doubledimple.ociserver.service;

import com.oracle.bmc.ospgateway.model.Subscription;

public interface RegisterDetailService {



    void saveRegisterDetail(Long snowflakeNextId, String tenantId, Subscription subscription);
}
