package com.doubledimple.ociserver.service.login;

import com.doubledimple.ociserver.service.OpenApiService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.RememberMeAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.web.authentication.RememberMeServices;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import javax.servlet.http.Cookie;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.concurrent.ThreadPoolExecutor;

/**
 * @version 1.0.0
 * @ClassName CustomerRememberMeService
 * @Description TODO
 * @Author renyx
 * @Date 2025-11-24 16:52
 */
@Component
@Slf4j
public class CustomerRememberMeService implements RememberMeServices {

    private static final String COOKIE_NAME = "remember-me-cookie";

    /** Token 总有效期：7 天 */
    private static final int VALIDITY_SECONDS = 7 * 24 * 60 * 60;

    /** 剩余不足 1 天时自动续期 */
    private static final int REFRESH_WINDOW_SECONDS = 24 * 60 * 60;

    private static final String HMAC_ALGO = "HmacSHA256";

    private final SecureRandom secureRandom = new SecureRandom();

    @Resource
    private LoginUserService loginUserService;

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private OpenApiService openApiService;

    @Resource
    private ThreadPoolExecutor threadPoolExecutor;

    // ================= RememberMeServices 接口实现 =================

    @Override
    public Authentication autoLogin(HttpServletRequest request, HttpServletResponse response) {

        Cookie cookie = findRememberMeCookie(request);
        if (cookie == null) {
            return null;
        }

        try {
            RememberMeToken token = parseToken(cookie.getValue());
            if (token == null) {
                clearCookie(response);
                return null;
            }
            UserDetails userDetails = loginUserService.loadUserByUsername(token.getUsername());
            if (!validateTokenSignature(token, userDetails.getPassword())) {
                log.warn("Remember-me 签名校验失败或密码已修改");
                clearCookie(response);
                return null;
            }

            String keyHash = systemConfigService.getOrCreateRememberMeKey();
            RememberMeAuthenticationToken authentication =
                    new RememberMeAuthenticationToken(
                            keyHash,
                            userDetails,
                            userDetails.getAuthorities()
                    );

            long now = Instant.now().getEpochSecond();
            long remaining = token.getExpiryEpochSeconds() - now;
            if (remaining < REFRESH_WINDOW_SECONDS) {
                log.debug("Remember-me 剩余时间 {} 秒，小于阈值 {} 秒，自动续期", remaining, REFRESH_WINDOW_SECONDS);
                addRememberMeCookie(response, userDetails);
            }
            return authentication;

        } catch (Exception e) {
            log.warn("Remember-me 自动登录失败，清除 Cookie。原因：{}", e.getMessage());
            clearCookie(response);
            return null;
        }
    }

    @Override
    public void loginFail(HttpServletRequest request, HttpServletResponse response) {
        log.warn("手动登录失败，清除 RememberMe Cookie，防止自动登录");
        clearCookie(response);
    }

    @Override
    public void loginSuccess(HttpServletRequest request,
                             HttpServletResponse response,
                             Authentication successfulAuthentication) {

        if (request != null) {
            String remember = request.getParameter("remember-me");
            if (remember == null) {
                log.debug("用户未勾选 remember-me，不写 RememberMe Cookie");
                return;
            }
        }

        rememberLogin(response, successfulAuthentication);

    }


    public void rememberLogin(HttpServletResponse response, Authentication authentication) {
        String username = authentication.getName();
        UserDetails userDetails = loginUserService.loadUserByUsername(username);
        addRememberMeCookie(response, userDetails);
        log.debug("写入 RememberMe Cookie，用户：{}", username);
    }


    private Cookie findRememberMeCookie(HttpServletRequest request) {
        if (request == null || request.getCookies() == null) {
            return null;
        }
        for (Cookie c : request.getCookies()) {
            if (COOKIE_NAME.equals(c.getName())) {
                return c;
            }
        }
        return null;
    }

    private void addRememberMeCookie(HttpServletResponse response, UserDetails userDetails) {
        String token = generateToken(userDetails);

        Cookie cookie = new Cookie(COOKIE_NAME, token);
        cookie.setPath("/");
        cookie.setHttpOnly(true);
        cookie.setMaxAge(VALIDITY_SECONDS);
        // 如果生产环境是 https，建议打开
        // cookie.setSecure(true);
        response.addCookie(cookie);
        log.debug("生成签名时的原文 data: {}", token);
    }

    private void clearCookie(HttpServletResponse response) {
        Cookie cookie = new Cookie(COOKIE_NAME, "");
        cookie.setMaxAge(0);
        cookie.setPath("/");
        response.addCookie(cookie);
    }

    // ========== Token 生成 & 解析 ==========

    private String generateToken(UserDetails userDetails) {
        long now = Instant.now().getEpochSecond();
        long expiry = now + VALIDITY_SECONDS;
        String nonce = Long.toHexString(secureRandom.nextLong());

        String key = systemConfigService.getOrCreateRememberMeKey();

        String dataForSignature = userDetails.getUsername() + ":" + expiry + ":" + nonce + ":" + userDetails.getPassword();
        log.debug("生成签名时的原文 data: {}", dataForSignature);

        String signature = hmacHex(dataForSignature, key);
        String rawCookieData = userDetails.getUsername() + ":" + expiry + ":" + nonce + ":" + signature;

        return Base64.getEncoder().encodeToString(rawCookieData.getBytes(StandardCharsets.UTF_8));
    }

    private String hmacHex(String data, String key) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGO);
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), HMAC_ALGO));
            byte[] rawHmac = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(rawHmac);
        } catch (Exception e) {
            throw new IllegalStateException("计算 HMAC 失败", e);
        }
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            String s = Integer.toHexString((b & 0xFF));
            if (s.length() == 1) {
                sb.append('0');
            }
            sb.append(s);
        }
        return sb.toString();
    }

    private boolean validateTokenSignature(RememberMeToken token, String currentPassword) {
        String key = systemConfigService.getOrCreateRememberMeKey();
        String data = token.getUsername() + ":" + token.getExpiryEpochSeconds() + ":" + token.getNonce() + ":" + currentPassword;
        String expectedSignature = hmacHex(data, key);
        log.debug("验签时的原文 data: {}", data);
        return MessageDigest.isEqual(
                expectedSignature.getBytes(StandardCharsets.UTF_8),
                token.getSignature().getBytes(StandardCharsets.UTF_8)
        );
    }

    private RememberMeToken parseToken(String tokenValue) {
        try {
            String decoded = new String(Base64.getDecoder().decode(tokenValue), StandardCharsets.UTF_8);
            String[] parts = decoded.split(":", 4);
            if (parts.length != 4) return null;

            long expiry = Long.parseLong(parts[1]);
            if (expiry < Instant.now().getEpochSecond()) return null;
            return new RememberMeToken(parts[0], expiry, parts[2], parts[3]);
        } catch (Exception e) {
            return null;
        }
    }

    @Data
    @AllArgsConstructor
    private static class RememberMeToken {
        private String username;
        private long expiryEpochSeconds;
        private String nonce;
        private String signature;
    }
}
