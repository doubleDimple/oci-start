package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.pojo.request.ApiTokenConfigRequest;
import com.doubledimple.ociserver.pojo.request.CloudflareConfigRequest;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfigRequest;
import com.doubledimple.ociserver.pojo.request.FeishuConfigRequest;
import com.doubledimple.ociserver.pojo.request.GoogleConfigRequest;
import com.doubledimple.ociserver.pojo.request.MfaConfigRequest;
import com.doubledimple.ociserver.pojo.request.ProxyConfigRequest;
import com.doubledimple.ociserver.pojo.response.ApiTokenResponse;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.pojo.request.BarkConfigRequest;
import com.doubledimple.ociserver.pojo.request.DingTalkConfigRequest;
import com.doubledimple.ociserver.pojo.request.GithubConfigRequest;
import com.doubledimple.ociserver.pojo.request.IpCheckConfigRequest;
import com.doubledimple.ociserver.pojo.request.PasswordUpdateRequest;
import com.doubledimple.ociserver.pojo.request.TaskConfigRequest;
import com.doubledimple.ociserver.pojo.request.TelegramConfigRequest;
import com.doubledimple.ociserver.pojo.request.TurnstileConfigRequest;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.third.dns.CloudflareService;
import com.doubledimple.ociserver.utils.EdgeUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName SystemSettingsApiController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 12:55
 */
@RestController
@RequestMapping("/api/system")
@Slf4j
public class SystemSettingsApiController  extends BaseController{

    @Resource
    private LoginUserService loginUserService;

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private CloudflareService cloudflareService;

    @PostMapping("/updatePassword")
    public ResponseEntity<?> updatePassword(@RequestBody PasswordUpdateRequest request, HttpServletRequest httpServletRequest) {
        try {
            loginUserService.updatePassword(request, httpServletRequest);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateTelegramConfig")
    public ResponseEntity<?> updateTelegramConfig(@RequestBody TelegramConfigRequest request) {
        try {
            systemConfigService.updateTelegramConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateGithubConfig")
    public ResponseEntity<?> updateGithubConfig(@RequestBody GithubConfigRequest request) {
        try {
            systemConfigService.updateGithubConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    /**
     * 更新 Google OAuth 配置
     */
    @PostMapping("/updateGoogleConfig")
    public ResponseEntity<?> updateGoogleConfig(@RequestBody GoogleConfigRequest request) {
        try {
            systemConfigService.updateGoogleConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新 Google 配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateDingTalkConfig")
    public ResponseEntity<Void> updateDingTalkConfig(@RequestBody DingTalkConfigRequest request) {
        try {
            systemConfigService.updateDingTalkConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新钉钉配置失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }
    }

    /**
     * @Description: 测试钉钉消息发送
     * @Param: []
     * @return: org.springframework.http.ResponseEntity<java.lang.Void>
     * @Author: doubleDimple
     * @Date: 12/14/24 4:10 PM
     */
    @PostMapping("/testDingTalk")
    public ResponseEntity<Void> testDingTalk() {
        try {
            systemConfigService.sendDingTalkMessage("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("发送钉钉测试消息失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }
    }

    /**
    * @Description: 测试tg消息发送
    * @Param: []
    * @return: org.springframework.http.ResponseEntity<java.lang.Void>
    * @Author: doubleDimple
    * @Date: 12/14/24 4:10 PM
    */
    @PostMapping("/testTgTalk")
    public ResponseEntity<Void> testTgTalk() {
        try {
            systemConfigService.testTgTalk("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("发送钉钉测试消息失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }
    }


    /**
    * @Description: 通知定时任务,账号测活,抢机统计
    * @Param: [int]
    * @return: org.springframework.http.ResponseEntity<java.lang.String>
    * @Author doubleDimple
    * @Date: 1/3/25 9:05 PM
    */
    @PostMapping("/updateTaskConfig")
    public ResponseEntity<?> updateTaskConfig(@RequestBody TaskConfigRequest request) {
        try {
            systemConfigService.updateTaskConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    /**
    * ip质量检测的开关
    */
    @PostMapping("/updateIpCheckConfig")
    public ResponseEntity<?> updateIpCheckConfig(@RequestBody IpCheckConfigRequest request) {
        try {
            systemConfigService.updateIpCheckConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateBarkConfig")
    public ResponseEntity<?> updateBarkConfig(@RequestBody BarkConfigRequest request) {
        try {
            systemConfigService.updateBarkConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/testBark")
    public ResponseEntity<Void> testBark() {
        try {
            systemConfigService.testBark("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("发送Bark测试消息失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }
    }

    @PostMapping("/updateCloudflareConfig")
    public ResponseEntity<?> updateCloudflareConfig(@RequestBody CloudflareConfigRequest request) {
        try {
            systemConfigService.updateCloudflareConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新Cloudflare配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/testCloudflareConnection")
    public ResponseEntity<?> testCloudflareConnection(@RequestBody CloudflareConfigRequest request) {
        try {
            Map<String, Object> result = cloudflareService.testCloudflareConnection(request);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("测试Cloudflare连接失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateEdgeOneConfig")
    public ResponseEntity<?> updateEdgeOneConfig(@RequestBody EdgeOneConfigRequest request) {
        try {
            systemConfigService.updateEdgeOneConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新腾讯云EdgeOne配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/testEdgeOneConnection")
    public ResponseEntity<?> testEdgeOneConnection(@RequestBody EdgeOneConfigRequest request) {
        try {
            Map<String, Object> result = EdgeUtils.testEdgeOneConnection(request);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("测试腾讯云EdgeOne连接失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateMfaConfig")
    public ResponseEntity<?> updateMfaConfig(@RequestBody MfaConfigRequest request) {
        try {
            systemConfigService.updateMfaConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/regenerateMfaSecret")
    public ResponseEntity<?> regenerateMfaSecret() {
        try {
            systemConfigService.regenerateMfaSecret();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @DeleteMapping("/deleteMfaConfig")
    public ResponseEntity<?> deleteMfaConfig() {
        try {
            systemConfigService.deleteMfaConfig();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateFeishuConfig")
    public ResponseEntity<Void> updateFeishuConfig(@RequestBody FeishuConfigRequest request) {
        try {
            systemConfigService.updateFeishuConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新飞书配置失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }
    }

    @PostMapping("/testFeishu")
    public ResponseEntity<Void> testFeishu() {
        try {
            systemConfigService.sendFeishuMessage("这是一条测试消息 - " + LocalDateTime.now());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("发送飞书测试消息失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }
    }

    @PostMapping("/updateProxyConfig")
    public ResponseEntity<?> updateProxyConfig(@RequestBody ProxyConfigRequest request) {
        try {
            systemConfigService.updateProxyConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新代理配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/testProxyConnection")
    public ResponseEntity<?> testProxyConnection(@RequestBody ProxyConfigRequest request) {
        try {
            boolean success = systemConfigService.testProxyConnection(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", success);
            response.put("message", success ? "代理连接测试成功" : "代理连接测试失败");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("测试代理连接失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    /**
     * 生成新的API Token
     */
    @PostMapping("/generateApiToken")
    public ResponseEntity<?> generateApiToken(@RequestBody ApiTokenConfigRequest request) {
        try {
            ApiTokenResponse response = systemConfigService.updateApiTokenConfig(request);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("生成API Token失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    /**
     * 获取Token状态信息
     */
    @GetMapping("/apiTokenStatus")
    public ResponseEntity<?> getApiTokenStatus() {
        try {
            Map<String, Object> status = systemConfigService.getApiTokenStatus();
            return ResponseEntity.ok(status);
        } catch (Exception e) {
            log.error("获取API Token状态失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    /**
     * 撤销API Token
     */
    @PostMapping("/revokeApiToken")
    public ResponseEntity<?> revokeApiToken() {
        try {
            systemConfigService.revokeApiToken();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("撤销API Token失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    /**
     * 验证API Token
     */
    @PostMapping("/validateApiToken")
    public ResponseEntity<?> validateApiToken(@RequestBody Map<String, String> request) {
        try {
            String token = request.get("token");
            boolean isValid = systemConfigService.validateApiToken(token);

            Map<String, Object> response = new HashMap<>();
            response.put("valid", isValid);
            response.put("message", isValid ? "Token有效" : "Token无效或已过期");

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("验证API Token失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateChannelNotifyConfig")
    public ResponseEntity<?> updateChannelNotifyConfig(@RequestBody Map<String, Boolean> request) {
        try {
            Boolean enabled = request.get("enabled");
            if (enabled == null) {
                return ResponseEntity.badRequest().body("enabled参数不能为空");
            }
            systemConfigService.updateChannelNotifyConfig(enabled);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新频道通知配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/updateTurnstileConfig")
    public ResponseEntity<?> updateTurnstileConfig(@RequestBody TurnstileConfigRequest request) {
        try {
            systemConfigService.updateTurnstileConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("更新 Turnstile 配置失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/settings/logo")
    public ResponseEntity<?> updateLogoName(@RequestParam String logoName) {
        try {
            systemConfigService.updateSiteLogoName(logoName);
            Map<String, Object> response = new HashMap<>();
            response.put("code", 200);
            response.put("msg", "success");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("更新Logo名称失败", e);
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }
}
