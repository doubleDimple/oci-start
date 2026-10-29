package com.doubledimple.ociserver.controller.dashboard;

import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.config.annotations.AuditLog;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.service.dashboard.BusinessOverviewService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@Slf4j
public class BusinessOverviewController extends BaseController {
    private final BusinessOverviewService overview;

    @GetMapping("/api/dashboard/business")
    @AuditLog(ignore = true)
    public ResponseEntity<ApiResponse> getOverview(@RequestParam(defaultValue = "7") int days) {
        if (days != 7 && days != 30) return ResponseEntity.badRequest().body(ApiResponse.error("统计周期仅支持 7 天或 30 天"));
        try {
            return ResponseEntity.ok().header("Cache-Control", "no-store").body(ApiResponse.success(overview.overview(days)));
        } catch (Exception e) {
            log.error("读取 OCI 业务统计失败", e);
            return ResponseEntity.status(500).body(ApiResponse.error("业务统计暂时不可用，请稍后重试"));
        }
    }
}
