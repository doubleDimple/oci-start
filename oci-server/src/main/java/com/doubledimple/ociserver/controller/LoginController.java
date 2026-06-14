package com.doubledimple.ociserver.controller;

import cn.dev33.satoken.stp.StpUtil;
import com.doubledimple.ocicommon.utils.RsaUtils;
import com.doubledimple.ociserver.controller.BaseController.MessageResolver;
import com.doubledimple.ociserver.pojo.request.MfaConfig;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.service.VerifyService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.service.mfa.OTPService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.MessageSource;
import org.springframework.context.annotation.Lazy;
import org.springframework.context.i18n.LocaleContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.ResponseBody;

import java.util.Locale;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;

import static com.doubledimple.ocicommon.constant.Constants.RSA_PRIVATE_KEY;
import static com.doubledimple.ocicommon.constant.Constants.RSA_PUBLIC_KEY;
import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

@Controller
@CrossOrigin
@Slf4j
public class LoginController {

    @Resource
    private LoginUserService loginUserService;

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private PasswordEncoder passwordEncoder;

    @Resource
    private VerifyService verifyService;

    @Resource
    private OTPService otpService;

    @Resource
    private MessageSource messageSource;

    @RequestMapping(value = "/login", method = RequestMethod.GET)
    public String login(Model model, HttpServletRequest request) {
        Locale locale = LocaleContextHolder.getLocale();
        model.addAttribute("msg", new MessageResolver(messageSource, locale));
        model.addAttribute("currentLocale", locale.toString());
        model.addAttribute("siteLogoName", systemConfigService.getSiteLogoName());
        HttpSession session = request.getSession();
        String publicKey = null;
        try {
            String existingPrivateKey = (String) session.getAttribute(RSA_PRIVATE_KEY);
            if (existingPrivateKey == null) {
                KeyPair keyPair = RsaUtils.generateKeyPair();
                publicKey = RsaUtils.getPublicKeyString(keyPair);
                String privateKey = RsaUtils.getPrivateKeyString(keyPair);
                session.setAttribute(RSA_PRIVATE_KEY, privateKey);
                session.setAttribute(RSA_PUBLIC_KEY, publicKey);
            } else {
                publicKey = (String) session.getAttribute(RSA_PUBLIC_KEY);
            }
            model.addAttribute("publicKey", publicKey);
        } catch (IllegalStateException e) {
            log.debug("login session 已失效，RSA 写入跳过: {}", e.getMessage());
        } catch (Exception e) {
            log.error("生成RSA密钥对失败", e);
        }
        model.addAttribute("allowRegister", !loginUserService.existsAnyUser());
        model.addAttribute("githubEnabled", systemConfigService.getGithubConfig().isEnabled());
        model.addAttribute("googleEnabled", systemConfigService.getGoogleConfig().isEnabled());

        TurnstileConfig turnstileConfig = systemConfigService.getTurnstileConfig();
        model.addAttribute("turnstileEnabled", turnstileConfig.isEnabled());
        model.addAttribute("turnstileSiteKey", turnstileConfig.getSiteKey());

        if (isMobileRequest(request)) {
            return "mobile/login";
        }
        return "login_user";
    }

    @RequestMapping(value = "/perform_login", method = RequestMethod.POST)
    public void performLogin(HttpServletRequest request, HttpServletResponse response) throws IOException {
        String username = request.getParameter("username");
        String password = request.getParameter("password");
        String rememberMeParam = request.getParameter("remember-me");
        boolean rememberMe = "on".equals(rememberMeParam) || "true".equals(rememberMeParam) || "1".equals(rememberMeParam);

        String xRequestedWith = request.getHeader("X-Requested-With");
        String accept = request.getHeader("Accept");
        boolean isAjax = "XMLHttpRequest".equals(xRequestedWith) || (accept != null && accept.contains("application/json"));
        boolean mobile = isMobileRequest(request);

        try {
            if (!StringUtils.hasText(username) || !StringUtils.hasText(password)) {
                redirectError(response, request, isAjax, mobile, "用户名或密码不能为空");
                return;
            }

            // 验证用户名密码
            com.doubledimple.dao.entity.LoginUser user = loginUserService.validateCredentials(username, password);

            // 验证额外因子（MFA / 消息验证码）
            String factorError = validateAdditionalFactors(request, username);
            if (factorError != null) {
                redirectError(response, request, isAjax, mobile, factorError);
                return;
            }

            // 登录成功，写入 Sa-Token session
            StpUtil.login(user.getUsername(), rememberMe);
            log.info("用户 [{}] 登录成功，rememberMe={}", username, rememberMe);

            // 登录成功后清除 RSA 密钥，防止重复使用
            HttpSession session = request.getSession(false);
            if (session != null) {
                session.removeAttribute(RSA_PRIVATE_KEY);
                session.removeAttribute(RSA_PUBLIC_KEY);
            }

            String targetUrl = mobile ? "/m/tenants" : "/index";
            if (isAjax) {
                response.setContentType("application/json;charset=utf-8");
                response.getWriter().write("{\"success\":true,\"redirectUrl\":\"" + targetUrl + "\"}");
            } else {
                response.sendRedirect(targetUrl);
            }
        } catch (Exception e) {
            log.warn("用户 [{}] 登录失败：{}", username, e.getMessage());
            redirectError(response, request, isAjax, mobile, e.getMessage());
        }
    }

    private String validateAdditionalFactors(HttpServletRequest request, String username) {
        boolean messageEnabled = isMessageEnabled();
        MfaConfig mfaConfig = systemConfigService.getMfaConfig();
        boolean mfaEnabled = mfaConfig != null && mfaConfig.isEnabled();

        if (!messageEnabled && !mfaEnabled) {
            return null;
        }

        String verificationCode = request.getParameter("verificationCode");
        String mfaCode = request.getParameter("mfaCode");

        if (messageEnabled && StringUtils.hasText(verificationCode)) {
            try {
                verifyService.checkCodeForLogin(username, verificationCode);
                return null;
            } catch (Exception e) {
                log.warn("消息验证码验证失败：{}", e.getMessage());
            }
        }

        if (mfaEnabled && StringUtils.hasText(mfaCode)) {
            try {
                if (otpService.verifyMfaCode(mfaCode)) {
                    return null;
                }
            } catch (Exception e) {
                log.warn("MFA验证码验证失败：{}", e.getMessage());
            }
        }

        if (messageEnabled && mfaEnabled) {
            if (!StringUtils.hasText(verificationCode) && !StringUtils.hasText(mfaCode)) {
                return "请提供消息验证码或MFA验证码";
            }
            return "验证码错误，请检查消息验证码或MFA验证码";
        } else if (messageEnabled) {
            return StringUtils.hasText(verificationCode) ? "消息验证码错误" : "请提供消息验证码";
        } else {
            return StringUtils.hasText(mfaCode) ? "MFA验证码错误" : "请提供MFA验证码";
        }
    }

    private boolean isMessageEnabled() {
        try {
            return systemConfigService.getTelegramConfig().isEnabled()
                    || systemConfigService.getDingTalkConfig().isEnabled()
                    || systemConfigService.getBarkConfig().isEnabled();
        } catch (Exception e) {
            return false;
        }
    }

    @RequestMapping(value = "/perform_logout", method = {RequestMethod.POST, RequestMethod.GET})
    @ResponseBody
    public void performLogout(HttpServletRequest request, HttpServletResponse response) throws IOException {
        StpUtil.logout();
        boolean mobile = isMobileRequest(request);
        String accept = request.getHeader("Accept");
        String xRequestedWith = request.getHeader("X-Requested-With");
        boolean isAjax = "XMLHttpRequest".equals(xRequestedWith) || (accept != null && accept.contains("application/json"));
        if (isAjax) {
            response.setContentType("application/json;charset=utf-8");
            response.getWriter().write("{\"success\":true}");
        } else {
            response.sendRedirect(mobile ? "/m/login" : "/login");
        }
    }

    private void redirectError(HttpServletResponse response, HttpServletRequest request,
                               boolean isAjax, boolean mobile, String message) throws IOException {
        if (isAjax) {
            response.setContentType("application/json;charset=utf-8");
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            String escaped = message == null ? "" : message.replace("\"", "\\\"");
            response.getWriter().write("{\"success\":false,\"message\":\"" + escaped + "\"}");
        } else {
            String loginUrl = mobile ? "/m/login" : "/login";
            String encoded = URLEncoder.encode(message == null ? "" : message, StandardCharsets.UTF_8.name());
            response.sendRedirect(loginUrl + "?error=" + encoded);
        }
    }
}
