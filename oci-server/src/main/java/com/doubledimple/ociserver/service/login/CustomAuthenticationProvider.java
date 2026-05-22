package com.doubledimple.ociserver.service.login;

import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.MfaConfig;
import com.doubledimple.ociserver.service.VerifyService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.mfa.OTPService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.AuthenticationProvider;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_WRONG_PASSWORD_TEMPLATE_V_2;
import static com.doubledimple.ociserver.utils.PingUtil.getCurrentPublicIpAndAddress;

/**
 * @version 1.0.0
 * @ClassName CustomAuthenticationProvider
 * @Description
 * @Author doubleDimple
 * @Date 2025-08-02 09:33
 */
@Component
@Slf4j
public class CustomAuthenticationProvider implements AuthenticationProvider {
    @Resource
    private LoginUserService loginUserService;

    @Resource
    private PasswordEncoder passwordEncoder;

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private OTPService otpService;

    @Resource
    private VerifyService verifyService;

    @Resource
    MessageFactory messageFactory;

    @Override
    public Authentication authenticate(Authentication authentication) throws AuthenticationException {
        String username = authentication.getName();
        Object credentials = authentication.getCredentials();
        if (credentials == null){
            throw new BadCredentialsException("用户名或密码错误");
        }
        String password = credentials.toString();

        log.debug("开始验证用户: {}", username);

        try {
            // 1. 验证用户名和密码
            UserDetails userDetails = loginUserService.loadUserByUsername(username);
            if (!passwordEncoder.matches(password, userDetails.getPassword())) {
                log.warn("用户 {} 密码验证失败", username);
                HttpServletRequest currentRequest = getCurrentRequest();
                String clientIpAddress = IpUtils.getClientIpAddress(currentRequest).replace('.', '_');
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(String.format(MESSAGE_WRONG_PASSWORD_TEMPLATE_V_2,
                        getCurrentPublicIpAndAddress(currentRequest), clientIpAddress,clientIpAddress));
                throw new BadCredentialsException("用户名或密码错误");
            }

            log.debug("用户 {} 基础认证通过", username);

            // 2. 获取请求参数进行额外验证
            HttpServletRequest request = getCurrentRequest();
            if (request != null) {
                // 验证额外的认证因子
                validateAdditionalFactors(request, username);
            }

            log.debug("用户 {} 所有验证通过", username);

            // 创建认证成功的token
            return new UsernamePasswordAuthenticationToken(
                    userDetails, password, userDetails.getAuthorities());

        } catch (Exception e) {
            log.error("用户 {} 认证失败: {}", username, e.getMessage());
            throw new BadCredentialsException("认证失败: " + e.getMessage());
        }
    }

    private void validateAdditionalFactors(HttpServletRequest request, String username) {
        // 获取系统配置
        boolean messageEnabled = isMessageEnabled();
        MfaConfig mfaConfig = systemConfigService.getMfaConfig();
        boolean mfaEnabled = mfaConfig.isEnabled();

        log.debug("验证配置 - 消息验证: {}, MFA验证: {}", messageEnabled, mfaEnabled);

        if (!messageEnabled && !mfaEnabled) {
            // 都没开启，跳过额外验证
            log.debug("用户 {} 无需额外验证", username);
            return;
        }

        String verificationCode = request.getParameter("verificationCode");
        String mfaCode = request.getParameter("mfaCode");

        log.debug("接收到参数 - 验证码: {}, MFA码: {}",
                StringUtils.hasText(verificationCode) ? "有" : "无",
                StringUtils.hasText(mfaCode) ? "有" : "无");

        boolean hasValidVerification = false;

        // 验证消息验证码
        if (messageEnabled && StringUtils.hasText(verificationCode)) {
            boolean isValidCode = validateMessageCode(username, verificationCode);
            if (isValidCode) {
                hasValidVerification = true;
                log.debug("用户 {} 消息验证码验证通过", username);
            }
        }

        // 验证MFA验证码
        if (mfaEnabled && StringUtils.hasText(mfaCode)) {
            boolean isValidMfa = validateMfaCode(mfaCode, mfaConfig.getSecretKey());
            if (isValidMfa) {
                hasValidVerification = true;
                log.debug("用户 {} MFA验证码验证通过", username);
            }
        }

        // 检查是否需要验证但没有通过
        if (!hasValidVerification) {
            String errorMsg = buildValidationErrorMessage(messageEnabled, mfaEnabled, verificationCode, mfaCode);
            log.warn("用户 {} 额外验证失败: {}", username, errorMsg);
            throw new BadCredentialsException(errorMsg);
        }
    }

    private boolean isMessageEnabled() {
        try {
            // 可以从 SystemConfigService 获取或者直接判断
            return systemConfigService.getTelegramConfig().isEnabled() ||
                    systemConfigService.getDingTalkConfig().isEnabled() ||
                    systemConfigService.getBarkConfig().isEnabled();
        } catch (Exception e) {
            log.error("获取消息配置失败", e);
            return false;
        }
    }

    private boolean validateMessageCode(String username, String verificationCode) {
        try {
            verifyService.checkCodeForLogin(username, verificationCode);
            return true;
        } catch (Exception e) {
            log.error("消息验证码验证失败", e);
            return false;
        }
    }

    private boolean validateMfaCode(String mfaCode, String secretKey) {
        try {
            if (!StringUtils.hasText(secretKey) || !StringUtils.hasText(mfaCode)) {
                return false;
            }
            return otpService.verifyMfaCode(mfaCode);
        } catch (Exception e) {
            log.error("MFA验证码验证失败", e);
            return false;
        }
    }

    private String buildValidationErrorMessage(boolean messageEnabled, boolean mfaEnabled,
                                               String verificationCode, String mfaCode) {
        if (messageEnabled && mfaEnabled) {
            if (!StringUtils.hasText(verificationCode) && !StringUtils.hasText(mfaCode)) {
                return "请提供消息验证码或MFA验证码";
            } else {
                return "验证码错误，请检查消息验证码或MFA验证码";
            }
        } else if (messageEnabled) {
            if (!StringUtils.hasText(verificationCode)) {
                return "请提供消息验证码";
            } else {
                return "消息验证码错误";
            }
        } else if (mfaEnabled) {
            if (!StringUtils.hasText(mfaCode)) {
                return "请提供MFA验证码";
            } else {
                return "MFA验证码错误";
            }
        }
        return "验证失败";
    }

    private HttpServletRequest getCurrentRequest() {
        try {
            ServletRequestAttributes attributes =
                    (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            return attributes != null ? attributes.getRequest() : null;
        } catch (Exception e) {
            log.warn("获取当前请求失败", e);
            return null;
        }
    }

    @Override
    public boolean supports(Class<?> authentication) {
        return UsernamePasswordAuthenticationToken.class.isAssignableFrom(authentication);
    }

}
