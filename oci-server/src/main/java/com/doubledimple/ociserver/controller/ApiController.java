package com.doubledimple.ociserver.controller;

import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.ServerMetrics;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.config.exception.RateLimitException;
import com.doubledimple.ociserver.pojo.request.MfaConfig;
import com.doubledimple.ociserver.pojo.request.ServerMetricsDTO;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.pojo.request.UsernameRequest;
import com.doubledimple.ociserver.pojo.request.VerificationRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.MetricsService;
import com.doubledimple.ociserver.service.VerifyService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.mfa.OTPService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpSession;
import javax.validation.Valid;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ocicommon.param.ApiResponse.SUCCESS;
import static com.doubledimple.ociserver.utils.PingUtil.getCurrentPublicIpAndAddress;

/**
 * @author doubleDimple
 * @date 2024:11:16日 19:59
 */
@Slf4j
@RestController
@RequestMapping("/api")
public class ApiController  extends BaseController{



    @Resource
    private MetricsService metricsService;

    @Resource
    private VerifyService verifyService;

    @Resource
    OTPService otpService;

    @Resource
    SystemConfigService systemConfigService;

    /**
     * 接收服务器上报的监控数据
     */
    @PostMapping("metrics/reportMetrics")
    public ResponseEntity<?> reportMetrics(@RequestBody ServerMetrics metrics) {
        try {
            ServerMetrics savedMetrics = metricsService.saveMetrics(metrics);
            return ResponseEntity.ok(savedMetrics);
        } catch (IllegalArgumentException e) {
            log.warn("Invalid metrics data received: {}", e.getMessage());
            return ResponseEntity
                    .badRequest()
                    .body(e.getMessage());
        } catch (Exception e) {
            log.error("Error processing metrics", e);
            return ResponseEntity
                    .status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Internal server error");
        }
    }


    /**
     * 获取最新监控数据的API接口
     */
    @GetMapping("metrics/status")
    @ResponseBody
    public ResponseEntity<List<ServerMetricsDTO>> getMetricsStatus() {
        List<ServerMetricsDTO> metrics = metricsService.getAllServerMetrics();
        return ResponseEntity.ok(metrics);
    }

    /**
     * 获取单个服务器的监控数据
     */
    @GetMapping("metrics/{serverId}")
    @ResponseBody
    public ResponseEntity<ServerMetrics> getServerMetrics(@PathVariable String serverId) {
        ServerMetrics metrics = metricsService.getServerStatus(serverId);
        return ResponseEntity.ok(metrics);
    }

    //
    @GetMapping("metrics/deleteMetrics")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> deleteMetrics(@RequestParam("serverId") String serverId) {
        metricsService.deleteMetrics(serverId);
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/config/message-enabled")
    public boolean isMessageEnabled() {
        return verifyService.isMessageEnabled();
    }

    @GetMapping("/config/mfa-enabled")
    @ResponseBody
    public boolean getMfaEnabled() {
        MfaConfig mfaConfig = verifyService.getMfaConfig();
        return mfaConfig.isEnabled();
    }

    @GetMapping("/config/turnstile")
    @ResponseBody
    public Map<String, Object> getTurnstileConfig() {
        TurnstileConfig config = systemConfigService.getTurnstileConfig();
        Map<String, Object> result = new HashMap<>();
        result.put("enabled", config.isEnabled());
        // 只返回 siteKey（公开的），不返回 secretKey
        result.put("siteKey", config.isEnabled() ? config.getSiteKey() : "");
        return result;
    }

    @PostMapping("/config/verify-mfa-code")
    @ResponseBody
    public ResponseEntity<?> verifyMfaCode(@RequestBody Map<String, String> request) {
        try {
            String username = request.get("username");
            String mfaCode = request.get("mfaCode");

            boolean isValid = otpService.verifyMfaCode(mfaCode);

            if (isValid) {
                // 在session中标记MFA验证通过
                HttpSession session = ((ServletRequestAttributes) RequestContextHolder.getRequestAttributes())
                        .getRequest().getSession();
                session.setAttribute("mfa_verified_" + username, true);

                return ResponseEntity.ok().build();
            } else {
                return ResponseEntity.badRequest().body(Collections.singletonMap("message", "MFA验证码错误"));
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Collections.singletonMap("message", e.getMessage()));
        }
    }

    /**
     * 发送验证码
     * @param request
     * @return
     */
    @PostMapping("/send-verification-code")
    public ResponseEntity<String> sendVerificationCode(@RequestBody @Valid UsernameRequest request, HttpServletRequest  httpServletRequest) {
        try {
            verifyService.sendVerificationCodeForLogin(request.getUsername(),httpServletRequest);
            return ResponseEntity.ok().build();
        } catch (RateLimitException e) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .body(e.getMessage());
        } catch (Exception e) {
            Map<String, String> error = new HashMap<>();
            error.put("message", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(JSONUtil.toJsonStr(error));
        }
    }

    /**
     * 验证
     * @param request
     * @return
     */
    @PostMapping("/verify-code-login")
    public ResponseEntity<String> verifyCode(@RequestBody @Valid VerificationRequest request) {
        try {
            verifyService.checkCodeForLogin(request.getUsername(), request.getVerificationCode());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(e.getMessage());
        }
    }

    @PostMapping("/system/verifyMfaCode")
    @ResponseBody
    public ApiResponse testVerifyMfaCode(@RequestBody Map<String, String> request) {
        try {
            String code = request.get("code");

            if (StringUtils.isBlank(code)) {
                return ApiResponse.error("验证码不能为空");
            }

            if (!code.matches("\\d{6}")) {
                return ApiResponse.error("验证码格式错误，请输入6位数字");
            }

            // 使用当前用户的MFA密钥验证验证码
            boolean isValid = otpService.verifyMfaCode(code);

            if (isValid) {
                return ApiResponse.success("验证成功！您的MFA配置工作正常");
            } else {
                return ApiResponse.error("验证码错误，请检查认证器中的验证码是否正确");
            }

        } catch (Exception e) {
            log.error("MFA验证码验证失败", e);
            return ApiResponse.error("验证过程中发生错误，请稍后重试");
        }
    }

    //获取oracle 端点数据
    @GetMapping("/getOracleEndpoint")
    public ApiResponse getOracleEndpoint() {
         return ApiResponse.success(RegionEnum.getAllRegion());
    }

    //获取当前访问用户的ip
    @GetMapping("/getCurrentIp")
    public ApiResponse getCurrentIp(HttpServletRequest currentRequest) {
        String currentPublicIpAndAddress = getCurrentPublicIpAndAddress(currentRequest);
        return ApiResponse.success(SUCCESS,currentPublicIpAndAddress);
    }

}
