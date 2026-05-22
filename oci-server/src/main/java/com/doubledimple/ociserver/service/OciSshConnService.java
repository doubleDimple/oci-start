package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.InstanceDetails;

public interface OciSshConnService {


    void saveOrUpdate(InstanceDetails instanceDetails);
}
