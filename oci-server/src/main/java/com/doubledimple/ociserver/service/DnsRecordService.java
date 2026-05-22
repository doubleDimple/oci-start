package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.ProviderType;

import java.util.List;

public interface DnsRecordService {



    void queryDnsRecordAndRefreshAndChange(Tenant tenant, String instanceId, String oldIp, String ipAddress, List<ProviderType> types);
}
