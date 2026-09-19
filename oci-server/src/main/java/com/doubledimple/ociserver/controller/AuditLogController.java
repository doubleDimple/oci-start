package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.AuditLog;
import com.doubledimple.ociserver.service.AuditLogService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * 访问与操作审计日志控制器
 *
 * @author doubleDimple
 */
@Slf4j
@RestController
@RequestMapping("/api/audit-logs")
@RequiredArgsConstructor
public class AuditLogController extends BaseController {

    private final AuditLogService auditLogService;

    /**
     * 分页查询审计日志（默认查询最近1个月）
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> getAuditLogs(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String username,
            @RequestParam(required = false) String method,
            @RequestParam(required = false) Integer status,
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) String startDate,
            @RequestParam(required = false) String endDate) {

        int pageIndex = Math.max(page - 1, 0);
        int pageSize = Math.min(Math.max(size, 1), 100);

        LocalDateTime start = parseDateTime(startDate, false);
        LocalDateTime end = parseDateTime(endDate, true);

        Page<AuditLog> pageResult = auditLogService.queryLogs(
                username, method, status, keyword, start, end, PageRequest.of(pageIndex, pageSize)
        );

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("content", pageResult.getContent());
        data.put("totalElements", pageResult.getTotalElements());
        data.put("totalPages", pageResult.getTotalPages());
        data.put("page", page);
        data.put("size", pageSize);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("code", 200);
        response.put("data", data);

        return ResponseEntity.ok(response);
    }

    /**
     * 单条删除审计日志
     */
    @DeleteMapping("/{id}")
    @com.doubledimple.ociserver.config.annotations.AuditLog(title = "删除审计日志")
    public ResponseEntity<Map<String, Object>> deleteAuditLog(@PathVariable Long id) {
        auditLogService.deleteById(id);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("code", 200);
        response.put("message", "删除成功");
        return ResponseEntity.ok(response);
    }

    /**
     * 批量删除审计日志
     */
    @PostMapping("/batch-delete")
    @com.doubledimple.ociserver.config.annotations.AuditLog(title = "批量删除审计日志")
    public ResponseEntity<Map<String, Object>> batchDelete(@RequestBody Map<String, Object> body) {
        List<Long> idList = new ArrayList<>();
        if (body != null && body.containsKey("ids")) {
            Object idsObj = body.get("ids");
            if (idsObj instanceof List) {
                for (Object item : (List<?>) idsObj) {
                    if (item instanceof Number) {
                        idList.add(((Number) item).longValue());
                    } else if (item != null) {
                        try {
                            idList.add(Long.parseLong(item.toString()));
                        } catch (NumberFormatException ignored) {
                        }
                    }
                }
            }
        }

        if (!idList.isEmpty()) {
            auditLogService.deleteBatch(idList);
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("code", 200);
        response.put("message", "批量删除成功");
        return ResponseEntity.ok(response);
    }

    /**
     * 一键清空所有审计日志
     */
    @DeleteMapping("/clear")
    @com.doubledimple.ociserver.config.annotations.AuditLog(title = "清空所有审计日志")
    public ResponseEntity<Map<String, Object>> clearAll() {
        auditLogService.clearAll();

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("code", 200);
        response.put("message", "审计日志已全部清空");
        return ResponseEntity.ok(response);
    }

    private LocalDateTime parseDateTime(String text, boolean isEndDate) {
        if (!StringUtils.hasText(text)) {
            return null;
        }
        text = text.trim();
        try {
            if (text.length() == 10) { // yyyy-MM-dd
                LocalDate d = LocalDate.parse(text);
                return isEndDate ? d.atTime(23, 59, 59) : d.atStartOfDay();
            }
            if (text.contains("T")) {
                String clean = text.replace("Z", "");
                if (clean.contains(".")) {
                    clean = clean.substring(0, clean.indexOf('.'));
                }
                return LocalDateTime.parse(clean, DateTimeFormatter.ISO_LOCAL_DATE_TIME);
            }
            return LocalDateTime.parse(text, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        } catch (Exception e) {
            log.debug("解析时间失败: text={}", text);
            return null;
        }
    }
}
