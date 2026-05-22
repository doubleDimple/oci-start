package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.InstallApp;
import com.doubledimple.ocicommon.param.InstallAppNotify;
import com.doubledimple.ocicommon.param.InstanceHelpNotify;
import com.doubledimple.ocicommon.param.OpenInstanceNotify;
import com.doubledimple.ocicommon.param.OpenRegionNotify;

import java.util.List;

public interface OpenApiService {


    /**
    * @Description: notify
    *
    */
    public void notify(OpenInstanceNotify openInstanceNotify);
    public void help(InstanceHelpNotify instanceHelpNotify);

    public List<OpenRegionNotify> armRecords(OpenRegionNotify openRegionNotify);

    public List<OpenRegionNotify> armRecordsLocal(OpenRegionNotify openRegionNotify);

    public InstallAppNotify installApp(InstallApp installApp);
}
