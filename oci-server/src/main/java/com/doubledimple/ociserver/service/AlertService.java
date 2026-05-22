package com.doubledimple.ociserver.service;

import com.doubledimple.ocicommon.param.monitor.MonitorAlert;
import com.doubledimple.ocicommon.param.monitor.MonitorReportDTO;

public interface AlertService {


    public void sendAlertAsync(MonitorReportDTO reportDto);
}
