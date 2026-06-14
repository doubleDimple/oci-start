package com.doubledimple.ociserver.controller.login;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.request.GithubConfig;
import com.doubledimple.ociserver.pojo.request.GithubUser;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import cn.dev33.satoken.stp.StpUtil;
import org.springframework.http.*;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

/**
 * @version 1.0.0
 * @ClassName GithubLoginController
 * @Description GitHub登录控制器
 * @Author doubleDimple
 * @Date 2024-11-21 11:09
 */
@Controller
@Slf4j
public class GithubLoginController extends BaseController {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    VersionCheckTask versionCheckTask;

    @Resource
    private LoginUserService loginUserService;
    private static final Map<String, StateInfo> STATE_CACHE = new ConcurrentHashMap<>();

    private static class StateInfo {
        final long expireTime;
        final boolean rememberMe;

        StateInfo(long expireTime, boolean rememberMe) {
            this.expireTime = expireTime;
            this.rememberMe = rememberMe;
        }
    }

    private static boolean parseRememberMe(String value) {
        if (StringUtils.isBlank(value)) {
            return false;
        }
        String v = value.trim().toLowerCase();
        return "on".equals(v) || "true".equals(v) || "1".equals(v) || "yes".equals(v);
    }

    /**
     * 获取 GitHub 登录授权 URL
     */
    @GetMapping("/api/github/login/url")
    @ResponseBody
    public ResponseEntity<String> getGithubLoginUrl(@RequestParam(name = "remember-me", required = false) String rememberMe) {
        try {
            GithubConfig config = systemConfigService.getGithubConfig();
            if (!config.isEnabled()) {
                return ResponseEntity.badRequest().body("GitHub登录未启用");
            }
            boolean isRememberMe = parseRememberMe(rememberMe);
            String state = UUID.randomUUID().toString();
            STATE_CACHE.put(state, new StateInfo(System.currentTimeMillis() + 5 * 60 * 1000, isRememberMe));
            cleanExpiredStates();
            log.info("Generated GitHub login state, rememberMe={}", isRememberMe);
            String url = String.format(
                    "https://github.com/login/oauth/authorize?client_id=%s&redirect_uri=%s&scope=read:user&state=%s",
                    config.getClientId(),
                    URLEncoder.encode(config.getRedirectUri(), StandardCharsets.UTF_8.name()),
                    URLEncoder.encode(state, StandardCharsets.UTF_8.name())
            );
            versionCheckTask.checkVersion();
            return ResponseEntity.ok(url);
        } catch (Exception e) {
            log.error("获取GitHub登录URL失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("获取GitHub登录URL失败: " + e.getMessage());
        }
    }

    /**
     * GitHub 登录回调处理
     */
    @GetMapping("/api/github/callback")
    public void githubCallback(@RequestParam String code,
                               @RequestParam String state,
                               HttpServletRequest request,
                               HttpServletResponse response) throws IOException {
        try {
            log.info("Receiving GitHub callback. Code len: {}, State: {}", code.length(), state);
            StateInfo stateInfo = STATE_CACHE.remove(state);
            if (stateInfo == null) {
                log.warn("非法登录请求：State 不存在或已被使用. State: {}", state);
                throw new RuntimeException("请求无效或页面已过期，请刷新后重试");
            }
            if (System.currentTimeMillis() > stateInfo.expireTime) {
                throw new RuntimeException("登录请求已超时，请重新登录");
            }

            GithubConfig config = systemConfigService.getGithubConfig();
            if (!config.isEnabled()) {
                throw new RuntimeException("GitHub登录未启用");
            }
            String accessToken = getGithubAccessToken(code, config);
            GithubUser githubUser = getGithubUser(accessToken);
            if (!config.getGithubId().equals(String.valueOf(githubUser.getId()))) {
                throw new RuntimeException("未授权的GitHub账号 (ID不匹配)");
            }

            LoginUser localUser = loginUserService.registerThirdPartyUser(
                    String.valueOf(githubUser.getId()),
                    githubUser.getLogin(),
                    LoginTypeEnum.GITHUB
            );

            StpUtil.login(localUser.getUsername(), stateInfo.rememberMe);
            log.info("GitHub login success, user={}, rememberMe={}", localUser.getUsername(), stateInfo.rememberMe);

            String redirectUrl = isMobileRequest(request) ? "/m/tenants" : "/index";
            response.sendRedirect(redirectUrl);

        } catch (Exception e) {
            log.error("GitHub Login fail", e);
            String loginUrl = isMobileRequest(request) ? "/m/login" : "/login";
            response.sendRedirect(loginUrl + "?error=" + URLEncoder.encode(e.getMessage(), StandardCharsets.UTF_8.name()));
        }
    }

    /**
     * 清理过期的 State
     */
    private void cleanExpiredStates() {
        long now = System.currentTimeMillis();
        STATE_CACHE.entrySet().removeIf(entry -> now > entry.getValue().expireTime);
    }

    private String getGithubAccessToken(String code, GithubConfig config) {
        RestTemplate restTemplate = new RestTemplate();
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, String> requestBody = new HashMap<>();
        requestBody.put("client_id", config.getClientId());
        requestBody.put("client_secret", config.getClientSecret());
        requestBody.put("code", code);

        HttpEntity<Map<String, String>> request = new HttpEntity<>(requestBody, headers);
        ResponseEntity<Map> response = restTemplate.postForEntity(
                "https://github.com/login/oauth/access_token",
                request,
                Map.class
        );
        if (response.getBody() != null && response.getBody().containsKey("access_token")) {
            return (String) response.getBody().get("access_token");
        } else {
            throw new RuntimeException("无法获取 GitHub Access Token");
        }
    }

    private GithubUser getGithubUser(String accessToken) {
        RestTemplate restTemplate = new RestTemplate();
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(accessToken);

        HttpEntity<String> request = new HttpEntity<>(headers);

        ResponseEntity<GithubUser> response = restTemplate.exchange(
                "https://api.github.com/user",
                HttpMethod.GET,
                request,
                GithubUser.class
        );

        return response.getBody();
    }

    /*private Authentication createAuthentication(GithubUser githubUser) {
        List<GrantedAuthority> authorities = Collections.singletonList(
                new SimpleGrantedAuthority("ROLE_USER")
        );
        return new UsernamePasswordAuthenticationToken(
                githubUser.getLogin(),
                "",
                authorities
        );
    }*/

}