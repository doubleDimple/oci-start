package com.doubledimple.ociserver.service.oracle;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;

import java.util.Map;

public interface OciNetBootService {


    public boolean executeAutoNetBoot(Tenant tenant, InstanceDetails instanceDetails, Map<String, String> sshConfig, String privateKeyPath, String architecture) ;


}
