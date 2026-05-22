package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.InstallApp;
import com.doubledimple.ocicommon.param.InstallAppNotify;

public interface InstallAppService {


    //新增
    public InstallAppNotify addOrUpdateInstallApp();


    //查询
    public InstallApp getInstallApp();
}
