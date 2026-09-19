package com.doubledimple.ociserver.controller;

import com.doubledimple.ocimonitor.service.quality.NetworkQualityException;
import com.doubledimple.ocimonitor.service.quality.NetworkQualityService;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.LinkedHashMap;
import java.util.Map;

import com.doubledimple.ociserver.config.annotations.AuditLog;

@RestController
@RequestMapping("/api/network-quality")
@AuditLog(title = "网络质量监控")
public class NetworkQualityController {
    @Resource private NetworkQualityService quality;

    @GetMapping("/overview")
    public Map<String, Object> overview() { return success(quality.overview()); }
    @GetMapping("/history")
    public Map<String, Object> history(@RequestParam String instanceId, @RequestParam String taskId,
                                       @RequestParam String revision, @RequestParam(defaultValue = "1") int hours) {
        return success(quality.history(instanceId, taskId, revision, hours));
    }
    @PostMapping("/tasks")
    public Map<String, Object> create(@RequestBody JsonNode body, HttpServletRequest request) {
        guardBrowserWrite(request); return success(quality.createTask(body));
    }
    @PutMapping("/tasks/{id}")
    public Map<String, Object> update(@PathVariable String id, @RequestBody JsonNode body, HttpServletRequest request) {
        guardBrowserWrite(request); return success(quality.updateTask(id, body));
    }
    @DeleteMapping("/tasks/{id}")
    public Map<String, Object> delete(@PathVariable String id, @RequestParam String version, HttpServletRequest request) {
        guardBrowserWrite(request); return success(quality.deleteTask(id, version));
    }
    @PostMapping("/tasks/{id}/run")
    public Map<String, Object> run(@PathVariable String id, @RequestBody JsonNode body, HttpServletRequest request) {
        guardBrowserWrite(request); return success(quality.runTask(id, body));
    }

    // Only these exact routes bypass browser sessions. The service validates the hashed bearer on every request.
    @PostMapping("/agent/poll")
    public Map<String, Object> poll(@RequestHeader(value = "Authorization", required = false) String authorization,
                                  @RequestBody JsonNode body) { return success(quality.poll(authorization, body)); }
    @PostMapping("/agent/report")
    public Map<String, Object> report(@RequestHeader(value = "Authorization", required = false) String authorization,
                                    @RequestBody JsonNode body) { return success(quality.report(authorization, body)); }

    @ExceptionHandler(NetworkQualityException.class)
    public ResponseEntity<Map<String, Object>> businessError(NetworkQualityException error) {
        return failure(error.getStatus(), error.getErrorKey(), error.getMessage());
    }
    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class, MissingServletRequestParameterException.class})
    public ResponseEntity<Map<String, Object>> invalidRequest(Exception ignored) {
        return failure(400, "invalidInput", "网络质量请求参数无效");
    }
    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<Map<String, Object>> conflict(Exception ignored) {
        return failure(409, "conflict", "任务版本已变化，请重新读取");
    }
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> unavailable(Exception ignored) {
        // JDBC/HTTP exception messages can contain bind values. Never log or return credential/request material.
        return failure(500, "requestFailed", "网络质量操作未确认完成，请重新读取状态");
    }
    private static Map<String, Object> success(Object data) {
        Map<String, Object> result = new LinkedHashMap<>(); result.put("success", true); result.put("data", data); return result;
    }
    private static void guardBrowserWrite(HttpServletRequest request) {
        // The existing global CORS policy accepts credentialed origins. Protect only this new module's writes.
        // Browsers cannot forge Sec-Fetch-Site; same-origin remains correct through the Vite development proxy.
        String site = request.getHeader("Sec-Fetch-Site");
        if ("same-origin".equals(site)) return;
        if (site != null && !"none".equals(site)) throw forbidden();
        String origin = request.getHeader("Origin");
        if (origin == null) return; // Non-browser callers still pass the existing login interceptor.
        try {
            URI uri = new URI(origin);
            if (uri.getHost() == null || uri.getScheme() == null || uri.getRawUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null || !"".equals(uri.getRawPath())) throw forbidden();
            int port = uri.getPort() < 0 ? ("https".equalsIgnoreCase(uri.getScheme()) ? 443 : 80) : uri.getPort();
            if (!uri.getScheme().equalsIgnoreCase(request.getScheme()) || port != request.getServerPort()
                    || !unbracket(uri.getHost()).equalsIgnoreCase(unbracket(request.getServerName()))) throw forbidden();
        } catch (URISyntaxException e) { throw forbidden(); }
    }
    private static String unbracket(String host) {
        return host.startsWith("[") && host.endsWith("]") ? host.substring(1, host.length() - 1) : host;
    }
    private static NetworkQualityException forbidden() {
        return new NetworkQualityException(403, "forbidden", "只允许同源页面修改网络质量任务");
    }
    private static ResponseEntity<Map<String, Object>> failure(int status, String key, String message) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("success", false); result.put("errorKey", key); result.put("message", message);
        return ResponseEntity.status(status).body(result);
    }
}
