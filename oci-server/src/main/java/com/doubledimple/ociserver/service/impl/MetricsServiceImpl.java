package com.doubledimple.ociserver.service.impl;

import cn.hutool.core.collection.CollectionUtil;
import com.doubledimple.dao.entity.ServerMetrics;
import com.doubledimple.dao.repository.ServerMetricsRepository;
import com.doubledimple.ociserver.pojo.request.ServerMetricsDTO;
import com.doubledimple.ociserver.service.MetricsService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * @author doubleDimple
 * @date 2024:11:16日 23:19
 */
@Service
@Slf4j
public class MetricsServiceImpl implements MetricsService {

    private static final long OFFLINE_THRESHOLD_MINUTES = 5; // 5分钟无数据视为离线

    @Value("${monitor.offline.threshold:300}")  // 5分钟无心跳视为离线
    private long offlineThresholdSeconds;

    @Resource
    private ServerMetricsRepository repository;

    @Override
    @Transactional
    public ServerMetrics saveMetrics(ServerMetrics metrics) {
        List<ServerMetrics> allByServerId = repository.findAllByServerId(metrics.getServerId());
        if (allByServerId.size() > 0){
            List<Long> collect = allByServerId.stream().map(ServerMetrics::getId).collect(Collectors.toList());
            repository.deleteAllById(collect);
        }
        metrics.setLastConnectionTime(LocalDateTime.now());
        return repository.save(metrics);
    }

    @Override
    public List<ServerMetrics> getAllServerStatus() {
        List<ServerMetrics> metrics = repository.findLatestMetricsForAllServers();
        return metrics.stream()
                .peek(this::checkOnlineStatus)
                .collect(Collectors.toList());
    }

    public ServerMetrics getServerStatus(String serverId) {
        ServerMetrics metrics = repository.findTopByServerIdOrderByLastConnectionTimeDesc(serverId);
        if (metrics != null) {
            checkOnlineStatus(metrics);
        }
        return metrics;
    }

    @Override
    public List<ServerMetricsDTO> getAllServerMetrics() {
        ArrayList<ServerMetricsDTO> serverMetricsDTOS = new ArrayList<>();
        List<ServerMetrics> all = repository.findAll();
        if (CollectionUtil.isNotEmpty(all)){
            for (ServerMetrics serverMetrics : all) {
                serverMetricsDTOS.add(ServerMetricsDTO.fromEntity(serverMetrics));
            }
        }

        return serverMetricsDTOS;
    }

    @Override
    @Transactional
    public void deleteMetrics(String serverId) {
        repository.deleteByServerId(serverId);
        repository.flush();
    }

    private void checkOnlineStatus(ServerMetrics metrics) {
        if (metrics.getLastConnectionTime() == null) {
            metrics.setOnline(false);
            return;
        }

        Duration duration = Duration.between(metrics.getLastConnectionTime(), LocalDateTime.now());
        metrics.setOnline(duration.toMinutes() < OFFLINE_THRESHOLD_MINUTES);
    }
}
