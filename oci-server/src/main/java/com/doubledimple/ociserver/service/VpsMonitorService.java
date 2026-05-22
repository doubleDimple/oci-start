package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.VpsMonitor;

import java.util.List;

public interface VpsMonitorService {


    public List<VpsMonitor> pageList(int pageNum, int pageSize);
}
