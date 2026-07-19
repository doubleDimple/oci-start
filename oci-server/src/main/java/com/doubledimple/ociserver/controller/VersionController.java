package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.AppVersion;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ocicommon.param.ApiResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName VersionController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-15 11:04
 */
@RestController
@RequestMapping("/api/version")
@RequiredArgsConstructor
@Slf4j
public class VersionController  extends BaseController{

    private final VersionCheckTask versionCheckTask;

    @GetMapping("/check")
    public Map<String, Object> checkV() {
        AppVersion version = versionCheckTask.getVersion();
        Map<String, Object> result = new HashMap<>();
        result.put("currentVersion", version.getCurrentVersion());
        result.put("latestVersion", version.getLatestVersion());
        result.put("deployType", version.getDeployType());
        result.put("needUpdate", version.needUpdate());
        return result;
    }

    @PostMapping("/execute-update")
    public ApiResponse executeUpdate() {
        try {
            versionCheckTask.executeUpdate();
            return ApiResponse.success("更新成功 ✅");
        } catch (Exception e) {
            log.warn("执行更新版本失败, 原因为: {}", e.getMessage());
            return ApiResponse.error("更新失败：" + e.getMessage());
        }
    }

    /**
     * 仅把 currentVersion 标记为 latestVersion，不执行安装脚本。
     * 供桌面端（Mac）自行替换 jar 后写库使用。
     */
    @PostMapping("/mark-updated")
    public ApiResponse markUpdated() {
        try {
            versionCheckTask.updateComplete();
            return ApiResponse.success("版本已标记为最新");
        } catch (Exception e) {
            log.warn("标记版本失败, 原因为: {}", e.getMessage());
            return ApiResponse.error("标记失败：" + e.getMessage());
        }
    }
}
