package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.AuditLog;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 审计日志业务接口
 *
 * @author doubleDimple
 */
public interface AuditLogService {

    /**
     * 保存审计日志
     */
    void saveAuditLog(AuditLog auditLog);

    /**
     * 分页多条件查询审计日志
     */
    Page<AuditLog> queryLogs(String username, String method, Integer status, String keyword,
                             LocalDateTime startDate, LocalDateTime endDate, Pageable pageable);

    /**
     * 单条删除
     */
    void deleteById(Long id);

    /**
     * 批量删除
     */
    void deleteBatch(List<Long> ids);

    /**
     * 一键清空所有日志
     */
    void clearAll();

    /**
     * 删除指定日期前的历史日志
     */
    int deleteBeforeDate(LocalDateTime beforeDate);
}
