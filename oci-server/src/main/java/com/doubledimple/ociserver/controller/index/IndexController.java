package com.doubledimple.ociserver.controller.index;

import com.doubledimple.ocicommon.cache.CacheService;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.controller.BaseController;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.HashMap;
import java.util.Map;

import static com.doubledimple.ocicommon.cache.CacheConstants.GITHUB_STARS_KEY;

/**
 * @version 1.0.0
 * @ClassName IndexController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-23 10:26
 */
@Controller
@Slf4j
public class IndexController  extends BaseController {

    @Resource
    VersionCheckTask versionCheckTask;

    @Resource
    @Lazy
    CacheService cacheService;

    @GetMapping("/api/dashboard/stats")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getDashboardStats() {
        try {
            Map<String, Object> stats = new HashMap<>();

            // GitHub Stars - 可以通过GitHub API获取
            stats.put("githubStars", getGithubStars());

            return ResponseEntity.ok(stats);
        } catch (Exception e) {
            log.error("获取仪表板统计数据失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(null);
        }
    }

    private Long getGithubStars() {
        return cacheService.getFromCache(
                GITHUB_STARS_KEY,
                Long.class,
                () -> versionCheckTask.getGitHubStars());
    }
}
