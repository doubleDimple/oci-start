package com.doubledimple.ociserver.controller;

import com.doubledimple.ocicommon.utils.RsaUtils;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpSession;

import java.security.KeyPair;

import static com.doubledimple.ocicommon.constant.Constants.RSA_PRIVATE_KEY;
import static com.doubledimple.ocicommon.constant.Constants.RSA_PUBLIC_KEY;
import static com.doubledimple.ociserver.utils.DesktopUtils.isMobileRequest;

/**
 * @author doubleDimple
 * @date 2024:10:06日 00:03
 */
@Controller
@CrossOrigin
@Slf4j
public class LoginController  extends BaseController{

    @Resource
    private LoginUserService loginUserService;
    @Resource
    private SystemConfigService systemConfigService;

    @RequestMapping(value = "/login", method = RequestMethod.GET)
    public String login(Model model, HttpServletRequest request) {
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
            // Spring Security 登录成功时会换 sessionId 并 invalidate 旧 session;
            // 如果此刻同一浏览器有并发 GET /login(双击/prefetch/iframe/多 tab),
            // 旧 session 引用上 setAttribute 会抛此异常 —— 这是预期并发场景,
            // 用户已登录成功不受影响,降级到 debug 避免噪音
            log.debug("login session 已失效,RSA 写入跳过(用户大概率已登录成功): {}", e.getMessage());
        } catch (Exception e) {
            log.error("生成RSA密钥对失败", e);
        }
        model.addAttribute("allowRegister", !loginUserService.existsAnyUser());
        model.addAttribute("githubEnabled", systemConfigService.getGithubConfig().isEnabled());
        model.addAttribute("googleEnabled", systemConfigService.getGoogleConfig().isEnabled());

        // Turnstile 配置
        TurnstileConfig turnstileConfig = systemConfigService.getTurnstileConfig();
        model.addAttribute("turnstileEnabled", turnstileConfig.isEnabled());
        model.addAttribute("turnstileSiteKey", turnstileConfig.getSiteKey());

        if (isMobileRequest(request)) {
            return "mobile/login";
        }
        return "login_user";
    }
}
