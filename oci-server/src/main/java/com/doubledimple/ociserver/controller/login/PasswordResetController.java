package com.doubledimple.ociserver.controller.login;

import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.VerifyService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
@Slf4j
public class PasswordResetController  extends BaseController {

    @Resource
    private VerifyService verifyService;

    /**
     * 发送重置验证码
     */
    @PostMapping("/send-reset-code")
    public ApiResponse sendResetCode(@RequestBody Map<String, String> request, HttpServletRequest  httpServletRequest) {
        try {
            String username = request.get("username");
            if (username == null || username.trim().isEmpty()) {
                return ApiResponse.error("用户名不能为空");
            }

            verifyService.sendVerificationCodeForPasswordReset(username,httpServletRequest);
            return ApiResponse.success("验证码已发送到您的通知终端");

        } catch (IllegalStateException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("发送重置验证码失败", e);
            return ApiResponse.error("系统错误，请稍后重试");
        }
    }

    /**
     * 验证重置验证码
     */
    @PostMapping("/verify-reset-code")
    public ApiResponse verifyResetCode(@RequestBody Map<String, String> request,HttpServletRequest httpServletRequest) {
        try {
            String username = request.get("username");
            String verificationCode = request.get("verificationCode");

            if (username == null || username.trim().isEmpty()) {
                return ApiResponse.error("用户名不能为空");
            }

            if (verificationCode == null || verificationCode.trim().isEmpty()) {
                return ApiResponse.error("验证码不能为空");
            }

            String resetToken = verifyService.verifyCodeForPasswordReset(username, verificationCode,httpServletRequest);

            Map<String, Object> data = new HashMap<>();
            data.put("resetToken", resetToken);
            data.put("expiresIn", 600); // 10分钟过期

            return ApiResponse.builder()
                    .success(true)
                    .message("验证成功")
                    .data(data)
                    .build();

        } catch (IllegalStateException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("验证重置验证码失败", e);
            return ApiResponse.error("系统错误，请稍后重试");
        }
    }

    /**
     * 执行密码重置
     */
    @PostMapping("/reset-password")
    public ApiResponse resetPassword(
            @RequestBody Map<String, String> request,
            @RequestHeader(value = "Reset-Token", required = false) String resetToken) {

        try {
            String username = request.get("username");

            // 优先从请求头获取resetToken，如果没有则从请求体获取
            if (resetToken == null || resetToken.trim().isEmpty()) {
                resetToken = request.get("resetToken");
            }

            if (username == null || username.trim().isEmpty()) {
                return ApiResponse.error("用户名不能为空");
            }

            if (resetToken == null || resetToken.trim().isEmpty()) {
                return ApiResponse.error("重置凭证缺失");
            }

            verifyService.resetPassword(username, resetToken);
            return ApiResponse.success("密码重置成功，新密码已发送到您的通知终端");

        } catch (IllegalStateException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            log.error("密码重置失败", e);
            return ApiResponse.error("系统错误，请稍后重试");
        }
    }
}
