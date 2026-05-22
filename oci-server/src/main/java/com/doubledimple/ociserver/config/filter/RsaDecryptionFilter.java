package com.doubledimple.ociserver.config.filter;

import com.doubledimple.ocicommon.utils.RsaUtils;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.ParameterRequestWrapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.IOException;
import java.util.Map;

import static com.doubledimple.ocicommon.constant.Constants.RSA_PRIVATE_KEY;
import static com.doubledimple.ocicommon.constant.Constants.RSA_PUBLIC_KEY;

/**
 * @version 1.0.0
 * @ClassName RsaDecryptionFilter
 * @Description RSA 密码解密 + Cloudflare Turnstile 人机验证过滤器
 * @Author doubleDimple
 * @Date 2026-02-06 09:09
 */
@Slf4j
public class RsaDecryptionFilter extends OncePerRequestFilter {

    private static final String TURNSTILE_VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
    private static final String TURNSTILE_RESPONSE_PARAM = "cf-turnstile-response";

    private final SystemConfigService systemConfigService;
    private final RestTemplate restTemplate;

    public RsaDecryptionFilter(SystemConfigService systemConfigService, RestTemplate restTemplate) {
        this.systemConfigService = systemConfigService;
        this.restTemplate = restTemplate;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        if ("/perform_login".equals(request.getServletPath()) && "POST".equalsIgnoreCase(request.getMethod())) {

            // ---- Turnstile 验证 ----
            if (!verifyTurnstileIfEnabled(request, response)) {
                return;
            }

            // ---- RSA 密码解密 ----
            String encryptedPassword = request.getParameter("password");
            HttpSession session = request.getSession(false);
            String privateKey = (session != null) ? (String) session.getAttribute(RSA_PRIVATE_KEY) : null;
            if (encryptedPassword != null && privateKey != null) {
                try {
                    String formattedPwd = encryptedPassword.trim().replace(" ", "+");
                    String rawPassword = RsaUtils.decrypt(formattedPwd, privateKey);
                    if (rawPassword != null) {
                        ParameterRequestWrapper wrapper = new ParameterRequestWrapper(request);
                        wrapper.setParameter("password", rawPassword);
                        session.removeAttribute(RSA_PRIVATE_KEY);
                        session.removeAttribute(RSA_PUBLIC_KEY);
                        filterChain.doFilter(wrapper, response);
                        return;
                    }
                } catch (Exception e) {
                    log.warn("【降级登录告警】解密失败，回退至明文验证,请尽快升级到最新版本。IP: {}, User-Agent: {}, 错误: {}",
                            request.getRemoteAddr(), request.getHeader("User-Agent"), e.getMessage());
                }
            } else {
                if (encryptedPassword != null) {
                    log.warn("【异常登录告警】未获取到RSA私钥，回退至明文验证,请尽快升级到最新版本。IP: {}, User-Agent: {}",
                            request.getRemoteAddr(), request.getHeader("User-Agent"));
                }
            }
        }
        filterChain.doFilter(request, response);
    }

    /**
     * 如果 Turnstile 已启用，则验证 token；验证失败时重定向并返回 false。
     */
    private boolean verifyTurnstileIfEnabled(HttpServletRequest request, HttpServletResponse response) throws IOException {
        try {
            TurnstileConfig config = systemConfigService.getTurnstileConfig();
            if (!config.isEnabled() || StringUtils.isBlank(config.getSecretKey())) {
                return true;
            }

            String token = request.getParameter(TURNSTILE_RESPONSE_PARAM);
            if (StringUtils.isBlank(token)) {
                log.warn("Turnstile 验证失败: 未提供 token，IP={}", request.getRemoteAddr());
                response.sendRedirect("/login?error=true");
                return false;
            }

            boolean verified = callTurnstileApi(token, config.getSecretKey(), request.getRemoteAddr());
            if (!verified) {
                log.warn("Turnstile 验证失败: token 无效，IP={}", request.getRemoteAddr());
                response.sendRedirect("/login?error=true");
                return false;
            }
        } catch (Exception e) {
            log.error("Turnstile 验证异常，跳过验证: {}", e.getMessage());
        }
        return true;
    }

    @SuppressWarnings("unchecked")
    private boolean callTurnstileApi(String token, String secretKey, String remoteIp) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

            MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
            body.add("secret", secretKey);
            body.add("response", token);
            if (StringUtils.isNotBlank(remoteIp)) {
                body.add("remoteip", remoteIp);
            }

            HttpEntity<MultiValueMap<String, String>> entity = new HttpEntity<>(body, headers);
            ResponseEntity<Map> result = restTemplate.postForEntity(TURNSTILE_VERIFY_URL, entity, Map.class);

            if (result.getBody() != null) {
                Object success = result.getBody().get("success");
                return Boolean.TRUE.equals(success);
            }
        } catch (Exception e) {
            log.error("Turnstile API 调用失败: {}", e.getMessage());
        }
        return false;
    }
}
