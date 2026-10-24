package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.AuditLog;
import com.doubledimple.dao.repository.AuditLogRepository;
import com.doubledimple.ociserver.service.AuditLogService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import javax.persistence.criteria.Predicate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * 审计日志业务实现类
 *
 * @author doubleDimple
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AuditLogServiceImpl implements AuditLogService {

    private final AuditLogRepository auditLogRepository;

    @Override
    @Transactional
    public void saveAuditLog(AuditLog auditLog) {
        try {
            if (auditLog.getCreateTime() == null) {
                auditLog.setCreateTime(LocalDateTime.now());
            }
            auditLogRepository.save(auditLog);
        } catch (Exception e) {
            log.error("保存审计日志失败: {}", e.getMessage(), e);
        }
    }

    @Override
    public Page<AuditLog> queryLogs(String username, String method, Integer status, String keyword,
                                    LocalDateTime startDate, LocalDateTime endDate, Pageable pageable) {
        // 若未提供开始时间，默认限制最近一个月内
        final LocalDateTime effectiveStart = (startDate != null) ? startDate : LocalDateTime.now().minusMonths(1);
        final LocalDateTime effectiveEnd = (endDate != null) ? endDate : LocalDateTime.now();

        Specification<AuditLog> spec = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();

            // 时间范围过滤
            predicates.add(cb.between(root.get("createTime"), effectiveStart, effectiveEnd));

            // 用户名精确匹配
            if (StringUtils.hasText(username)) {
                predicates.add(cb.equal(root.get("username"), username.trim()));
            }

            // HTTP 请求方法
            if (StringUtils.hasText(method)) {
                predicates.add(cb.equal(root.get("method"), method.trim().toUpperCase()));
            }

            // 操作状态 (1成功, 0失败)
            if (status != null) {
                predicates.add(cb.equal(root.get("status"), status));
            }

            // 关键字模糊搜索 (支持标题、URI、用户名、IP)
            if (StringUtils.hasText(keyword)) {
                String pattern = "%" + keyword.trim() + "%";
                Predicate titlePredicate = cb.like(root.get("title"), pattern);
                Predicate uriPredicate = cb.like(root.get("requestUri"), pattern);
                Predicate userPredicate = cb.like(root.get("username"), pattern);
                Predicate ipPredicate = cb.like(root.get("ip"), pattern);
                predicates.add(cb.or(titlePredicate, uriPredicate, userPredicate, ipPredicate));
            }

            return cb.and(predicates.toArray(new Predicate[0]));
        };

        // 按创建时间倒序排列
        Pageable sortedPageable = PageRequest.of(
                pageable.getPageNumber(),
                pageable.getPageSize(),
                Sort.by(Sort.Direction.DESC, "createTime")
        );

        return auditLogRepository.findAll(spec, sortedPageable);
    }

    @Override
    @Transactional
    public void deleteById(Long id) {
        if (id != null) {
            auditLogRepository.deleteById(id);
        }
    }

    @Override
    @Transactional
    public void deleteBatch(List<Long> ids) {
        if (ids != null && !ids.isEmpty()) {
            auditLogRepository.deleteAllByIdIn(ids);
        }
    }

    @Override
    @Transactional
    public void clearAll() {
        auditLogRepository.clearAll();
    }

    @Override
    @Transactional
    public int deleteBeforeDate(LocalDateTime beforeDate) {
        if (beforeDate == null) {
            return 0;
        }
        return auditLogRepository.deleteBeforeDate(beforeDate);
    }
}
