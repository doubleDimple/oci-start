package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.ServerMetrics;
import com.doubledimple.ociserver.pojo.request.ServerMetricsDTO;

import java.util.List;

public interface MetricsService {

    public ServerMetrics saveMetrics(ServerMetrics metrics);

    public List<ServerMetrics> getAllServerStatus();

    public ServerMetrics getServerStatus(String serverId);

    List<ServerMetricsDTO> getAllServerMetrics();

    void deleteMetrics(String serverId);
}
