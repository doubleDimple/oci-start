package com.doubledimple.ociserver.controller.login;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.request.GoogleConfig;
import com.doubledimple.ociserver.pojo.request.GoogleUser;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import cn.dev33.satoken.stp.StpUtil;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;
import java.math.BigInteger;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * @version 1.0.0
 * @ClassName GoogleLoginController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-01-19 13:30
 */
@Controller
@Slf4j
public class GoogleLoginController extends BaseController {

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    VersionCheckTask versionCheckTask;

    @Resource
    RestTemplate restTemplate;

    @Resource
    LoginUserService loginUserService;

    private static final Map<String, Long> STATE_CACHE = new ConcurrentHashMap<>();

    private final SecureRandom secureRandom = new SecureRandom();

    /**
     * 获取 Google 登录授权 URL
     */
    @GetMapping("/api/google/login/url")
    @ResponseBody
    public ResponseEntity<String> getGoogleLoginUrl(@RequestParam(name = "remember-me",required = false) String rememberMe) {
        try {
            GoogleConfig config = systemConfigService.getGoogleConfig();
            if (!config.isEnabled()) {
                return ResponseEntity.badRequest().body("Google Sign-in is not enabled.");
            }

            String randomStr = new BigInteger(130, secureRandom).toString(32);
            String state = randomStr + "_" + rememberMe;
            STATE_CACHE.put(state, System.currentTimeMillis() + 5 * 60 * 1000);
            cleanExpiredStates();
            String url = String.format(
                    "https://accounts.google.com/o/oauth2/v2/auth?client_id=%s&redirect_uri=%s&response_type=code&scope=openid%%20email%%20profile&state=%s",
                    config.getClientId(),
                    URLEncoder.encode(config.getRedirectUri(), StandardCharsets.UTF_8.name()),
                    state
            );
            versionCheckTask.checkVersion();
            return ResponseEntity.ok(url);
        } catch (Exception e) {
            log.error("获取Google登录URL失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("获取Google登录URL失败: " + e.getMessage());
        }
    }

    /**
     * Google 登录回调处理
     */
    @GetMapping("/api/google/callback")
    public void googleCallback(@RequestParam String code,
                               @RequestParam String state,
                               HttpServletRequest request,
                               HttpServletResponse response) throws IOException {
        try {
            log.info("Receiving Google callback. Code len: {}, State: {}", code.length(), state);
            Long expireTime = STATE_CACHE.get(state);
            if (expireTime == null) {
                log.warn("非法登录请求：State 不存在或已被使用. State: {}", state);
                throw new RuntimeException("Invalid request or the page has expired. Please refresh and try again.");
            }
            if (System.currentTimeMillis() > expireTime) {
                STATE_CACHE.remove(state);
                throw new RuntimeException("Login request timed out. Please log in again.");
            }
            STATE_CACHE.remove(state);
            GoogleConfig config = systemConfigService.getGoogleConfig();
            if (!config.isEnabled()) {
                throw new RuntimeException("Google Sign-in is not enabled.");
            }
            String accessToken = getGoogleAccessToken(code, config);
            GoogleUser googleUser = getGoogleUserInfo(accessToken);

            String allowedEmail = config.getEmail();
            if (StringUtils.isBlank(allowedEmail)) {
                throw new RuntimeException("Access denied: No administrator email has been configured for login.");
            }
            if (!allowedEmail.equalsIgnoreCase(googleUser.getEmail())) {
                log.warn("非授权 Google 账号尝试登录: {}", googleUser.getEmail());
                throw new RuntimeException("your email " + googleUser.getEmail() + " Unauthorized access to this system");
            }

            String usernamePrefix = googleUser.getName() != null ? googleUser.getName() : googleUser.getEmail().split("@")[0];
            LoginUser localUser = loginUserService.registerThirdPartyUser(
                    googleUser.getEmail(),
                    usernamePrefix,
                    LoginTypeEnum.GOOGLE
            );

            boolean isRememberMe = state.endsWith("_true") || state.endsWith("_on");
            StpUtil.login(localUser.getUsername(), isRememberMe);
            log.info("Google login success, user={}, rememberMe={}", localUser.getUsername(), isRememberMe);

            String redirectUrl = isMobileRequest(request) ? "/m/tenants" : "/index";
            response.sendRedirect(redirectUrl);

        } catch (Exception e) {
            log.error("Google Login Fail", e);
            String loginUrl = isMobileRequest(request) ? "/m/login" : "/login";
            response.sendRedirect(loginUrl + "?error=" + URLEncoder.encode(e.getMessage(), StandardCharsets.UTF_8.name()));
        }
    }

    private void cleanExpiredStates() {
        long now = System.currentTimeMillis();
        STATE_CACHE.entrySet().removeIf(entry -> now > entry.getValue());
    }

    /**
     * 换取 Access Token
     */
    private String getGoogleAccessToken(String code, GoogleConfig config) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        MultiValueMap<String, String> map = new LinkedMultiValueMap<>();
        map.add("client_id", config.getClientId());
        map.add("client_secret", config.getClientSecret());
        map.add("code", code);
        map.add("grant_type", "authorization_code");
        map.add("redirect_uri", config.getRedirectUri());

        HttpEntity<MultiValueMap<String, String>> request = new HttpEntity<>(map, headers);
        try {
            ResponseEntity<Map> response = restTemplate.postForEntity(
                    "https://oauth2.googleapis.com/token",
                    request,
                    Map.class
            );
            Map body = response.getBody();
            if (body != null && body.containsKey("access_token")) {
                return (String) body.get("access_token");
            } else {
                throw new RuntimeException("Failed to obtain Google Access Token.");
            }
        } catch (Exception e) {
            log.error("Google Token 交换失败", e);
            throw new RuntimeException("Google authorization failed. Please check your Client Secret or callback URL configuration.");
        }
    }

    /**
     * 获取用户信息
     */
    private GoogleUser getGoogleUserInfo(String accessToken) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(accessToken);
        HttpEntity<String> request = new HttpEntity<>(headers);
        try {
            ResponseEntity<GoogleUser> response = restTemplate.exchange(
                    "https://www.googleapis.com/oauth2/v3/userinfo",
                    HttpMethod.GET,
                    request,
                    GoogleUser.class
            );
            return response.getBody();
        } catch (Exception e) {
            log.error("获取 Google 用户信息失败", e);
            throw new RuntimeException("获取用户信息失败");
        }
    }

    /**
     * 创建 Spring Security 认证对象
     */
    /*private Authentication createAuthentication(GoogleUser googleUser) {
        List<GrantedAuthority> authorities = Collections.singletonList(
                new SimpleGrantedAuthority("ROLE_USER")
        );
        return new UsernamePasswordAuthenticationToken(
                googleUser.getName() != null ? googleUser.getName() : googleUser.getEmail(),
                "",
                authorities
        );
    }*/

}
