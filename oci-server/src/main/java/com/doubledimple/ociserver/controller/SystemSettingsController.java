package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiConfigService;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.doubledimple.ocicommon.enums.OperatorEnum;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ChatAiConfigDto;
import com.doubledimple.ociserver.config.telegram.TelegramBotService;
import com.doubledimple.ociserver.config.telegram.TelegramUserService;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfig;
import com.doubledimple.ociserver.pojo.request.CloudflareConfig;
import com.doubledimple.ociserver.pojo.request.EdgeOneConfig;
import com.doubledimple.ociserver.pojo.request.FeishuConfig;
import com.doubledimple.ociserver.pojo.request.ProxyConfig;
import com.doubledimple.ociserver.pojo.response.ModelSummaryDef;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.DingTalkConfig;
import com.doubledimple.ociserver.pojo.request.GithubConfig;
import com.doubledimple.ociserver.pojo.request.TurnstileConfig;
import com.doubledimple.ociserver.pojo.request.IpCheckConfig;
import com.doubledimple.ociserver.pojo.request.TaskConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.pojo.request.VPSConfig;
import com.doubledimple.ociserver.pojo.request.VPSConfigRequest;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.oracle.bmc.generativeai.model.ModelSummary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.Collections;

import static com.doubledimple.ocicommon.utils.DateTimeUtils.getReadableZoneTime;

/**
 * @version 1.0.0
 * @ClassName SystemSettingsController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 12:54
 */
@Controller
@RequestMapping("/system")
@Slf4j
public class SystemSettingsController  extends BaseController{

    @Resource
    private TelegramUserService telegramUserService;

    @Resource
    private TelegramBotService telegramBotService;

    @Resource
    private SystemConfigService systemConfigService;

    @Resource
    private ChatAiConfigService chatAiConfigService;

    @Resource
    private TenantService tenantService;

    @Resource
    OciAiChatUtils ociAiChatUtils;

    @GetMapping("/settings")
    public String showSettings(Model model, Authentication authentication) {
        // 获取当前用户名
        model.addAttribute("currentUsername", authentication.getName());

        // 获取Telegram配置
        model.addAttribute("telegramConfig", systemConfigService.getTelegramConfig());

        // 获取GitHub配置
        model.addAttribute("githubConfig", systemConfigService.getGithubConfig());

        // 获取钉钉配置
        model.addAttribute("dingTalkConfig", systemConfigService.getDingTalkConfig());

        // 获取定时任务配置
        model.addAttribute("taskConfig", systemConfigService.getTaskConfig());

        // 添加获取Bark配置
        model.addAttribute("barkConfig", systemConfigService.getBarkConfig());

        // 添加获取MFA配置 - 这是新增的代码
        model.addAttribute("mfaConfig", systemConfigService.getMfaConfig());

        model.addAttribute("feishuConfig", systemConfigService.getFeishuConfig());

        model.addAttribute("googleConfig", systemConfigService.getGoogleConfig());

        // 获取 Turnstile 配置
        TurnstileConfig turnstileConfig = systemConfigService.getTurnstileConfig();
        model.addAttribute("turnstileConfig", turnstileConfig);

        model.addAttribute("activePage", "api-settings");
        return "system_settings";
    }

    @GetMapping("/notifySettings")
    public String showNotifySettings(Model model, Authentication authentication) {
        // 获取当前用户名
        model.addAttribute("currentUsername", authentication.getName());

        // 获取Telegram配置
        TelegramConfig telegramConfig = systemConfigService.getTelegramConfig();
        model.addAttribute("telegramConfig", telegramConfig);

        // 获取GitHub配置
        GithubConfig githubConfig = systemConfigService.getGithubConfig();
        model.addAttribute("githubConfig", githubConfig);

        // 获取钉钉配置
        DingTalkConfig dingTalkConfig = systemConfigService.getDingTalkConfig();
        model.addAttribute("dingTalkConfig", dingTalkConfig);

        // 获取定时任务配置
        TaskConfig taskConfig = systemConfigService.getTaskConfig();
        model.addAttribute("taskConfig", taskConfig);
        model.addAttribute("currentZoneAndTime", getReadableZoneTime());
        model.addAttribute("systemZone", ZoneId.systemDefault().toString());

        // 添加获取Bark配置
        BarkConfig barkConfig = systemConfigService.getBarkConfig();
        model.addAttribute("barkConfig", barkConfig);

        //添加飞书
        FeishuConfig feishuConfig = systemConfigService.getFeishuConfig();
        model.addAttribute("feishuConfig", feishuConfig);

        ProxyConfig proxyConfig = systemConfigService.getProxyConfig();
        model.addAttribute("proxyConfig", proxyConfig);

        model.addAttribute("activePage", "api-notifySettings");
        return "notification_settings";
    }

    @GetMapping("/ipSettings")
    public String showIpSettings(Model model, Authentication authentication) {
        // 获取当前用户名
        model.addAttribute("currentUsername", authentication.getName());

        // 获取IP质量检测配置
        IpCheckConfig ipCheckConfig = systemConfigService.getIpCheckConfig();
        model.addAttribute("ipCheckConfig", ipCheckConfig);

        // 获取三大运营商VPS配置
        VPSConfig telecomConfig = systemConfigService.getVPSConfig(OperatorEnum.TELECOM.getType());
        VPSConfig unicomConfig = systemConfigService.getVPSConfig(OperatorEnum.UNICOM.getType());
        VPSConfig mobileConfig = systemConfigService.getVPSConfig(OperatorEnum.MOBILE.getType());

        model.addAttribute("telecomConfig", telecomConfig);
        model.addAttribute("unicomConfig", unicomConfig);
        model.addAttribute("mobileConfig", mobileConfig);

        model.addAttribute("activePage", "ip-settings");
        return "ip_settings";
    }

    @GetMapping("/ai/models")
    public String aiModels(Model model) {
        model.addAttribute("activePage", "ai-models");
        return "ai_model_config";
    }


    @GetMapping("/domainSettings")
    public String showDomainSettings(Model model, Authentication authentication) {
        // 获取当前用户名
        model.addAttribute("currentUsername", authentication.getName());

        // 获取Cloudflare配置
        CloudflareConfig cloudflareConfig = systemConfigService.getCloudflareConfig();
        model.addAttribute("cloudflareConfig", cloudflareConfig);

        // 添加腾讯云EdgeOne配置
        EdgeOneConfig edgeOneConfig = systemConfigService.getEdgeOneConfig();
        model.addAttribute("edgeOneConfig", edgeOneConfig);

        model.addAttribute("activePage", "domain-settings");
        return "domain_settings";
    }

    /**
     * API Token配置页面
     */
    @GetMapping("/apiTokens")
    public String showApiTokenConfig(Model model, Authentication authentication) {
        // 获取当前用户名
        model.addAttribute("currentUsername", authentication.getName());

        // 获取API Token配置
        ApiTokenConfig apiTokenConfig = systemConfigService.getApiTokenConfig();
        model.addAttribute("apiTokenConfig", apiTokenConfig);

        // 获取Token状态信息
        Map<String, Object> tokenStatus = systemConfigService.getApiTokenStatus();
        model.addAttribute("tokenStatus", tokenStatus);

        model.addAttribute("activePage", "api-tokens");
        return "api_token_config";
    }

    @PostMapping("/vps/saveConfig")
    public ResponseEntity<?> saveVPSConfig(@RequestBody VPSConfigRequest request) {
        try {
            systemConfigService.updateVPSConfig(request);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PostMapping("/vps/testConnection")
    public ResponseEntity<?> testSSHConnection(@RequestBody VPSConfigRequest request) {
        try {
            boolean success = systemConfigService.testSSHConnection(request);
            Map<String, Object> response = new HashMap<>();
            response.put("success", success);
            response.put("message", success ? "SSH连接成功" : "SSH连接失败");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @GetMapping("/memPage")
    public String memPage(Model model, Authentication authentication) {
        // 获取当前用户名
        model.addAttribute("currentUsername", authentication.getName());
        model.addAttribute("activePage", "api-memPage");

        return "memo";
    }

    //重新注册机器人
    @PostMapping("/startTgRobot")
    public ResponseEntity<?> startTgRobot() {
        try {
            telegramUserService.delCurrentBot();
            telegramBotService.startBot();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }


    /**
     * 获取Telegram AI配置
     */
    @GetMapping("/telegramAiConfigs")
    public ResponseEntity<List<ChatAiConfigDto>> getTelegramAiConfigs() {
        try {
            List<ChatAiConfigDto> configs = chatAiConfigService.getAllConfigsByCloudType(1);
            return ResponseEntity.ok(configs);
        } catch (Exception e) {
            log.error("获取Telegram AI配置列表失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 更新Telegram AI配置
     */
    @PostMapping("/updateTelegramAiConfig")
    public ResponseEntity<?> updateTelegramAiConfig(@RequestBody ChatAiConfigDto configDto) {
        try {
            // 默认cloudType为1
            if (configDto.getCloudType() == null) {
                configDto.setCloudType(1);
            }

            ChatAiConfigDto savedConfig = chatAiConfigService.saveOrUpdateConfig(configDto);
            return ResponseEntity.ok(savedConfig);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("更新Telegram AI配置失败: " + e.getMessage());
        }
    }

    /**
     * 批量更新Telegram AI配置
     */
    @PostMapping("/batchToggleTelegramAiConfigs")
    public ResponseEntity<?> batchToggleTelegramAiConfigs(@RequestBody Map<String, Object> request) {
        try {
            Boolean enabled = (Boolean) request.get("enabled");
            if (enabled == null) {
                return ResponseEntity.badRequest().body("enabled参数不能为空");
            }

            // 批量更新所有配置的状态
            int updatedCount = chatAiConfigService.batchUpdateConfigStatus(enabled);

            Map<String, Object> response = new HashMap<>();
            response.put("updatedCount", updatedCount);
            response.put("enabled", enabled);
            response.put("message", enabled ? "已启用" + updatedCount + "个AI配置" : "已禁用" + updatedCount + "个AI配置");

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("批量更新Telegram AI配置失败: " + e.getMessage());
        }
    }

    // 删除AI配置
    @DeleteMapping("/deleteTelegramAiConfig/{id}")
    public ResponseEntity<?> deleteTelegramAiConfig(@PathVariable Long id) {
        try {
            boolean deleted = chatAiConfigService.deleteById(id);
            if (deleted) {
                return ResponseEntity.ok().build();
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            log.error("删除Telegram AI配置失败", e);
            return ResponseEntity.badRequest().body("删除失败: " + e.getMessage());
        }
    }

    /**
     * 获取AI模型列表
     */
    @GetMapping("/aiModels")
    public ResponseEntity<?> getAiModels() {
        List<Tenant> tenants = tenantService.querySupportAiRecords(1);
        List<Map<String, Object>> result = new ArrayList<>();

        for (Tenant tenant : tenants) {
            Map<String, Object> tenantData = new HashMap<>();

            // 租户信息
            Map<String, String> tenantInfo = new HashMap<>();
            tenantInfo.put("tenantId", tenant.getIdStr());
            tenantInfo.put("userName", tenant.getUserName()+"-"+ RegionEnum.getRegionCode(tenant.getRegion()));

            // 模型列表
            List<ModelSummaryDef> tenantModels = new ArrayList<>();
            List<ModelSummary> allAvailableModels = ociAiChatUtils.getAllAvailableModels(tenant);
            for (ModelSummary allAvailableModel : allAvailableModels) {
                ModelSummaryDef modelSummaryDef = new ModelSummaryDef();
                modelSummaryDef.setId(allAvailableModel.getId());
                modelSummaryDef.setName(allAvailableModel.getDisplayName());
                modelSummaryDef.setDescription(allAvailableModel.getDisplayName());
                modelSummaryDef.setProvider("OCI");
                modelSummaryDef.setModelName(allAvailableModel.getDisplayName());
                modelSummaryDef.setEnabled(true);
                modelSummaryDef.setTenantId(tenant.getId().toString());
                tenantModels.add(modelSummaryDef);
            }

            tenantData.put("tenantInfo", tenantInfo);
            tenantData.put("models", tenantModels);
            result.add(tenantData);
        }

        return ResponseEntity.ok(result);
    }

    /**
     * 获取支持AI的租户列表（供左侧面板下拉选使用）
     */
    @GetMapping("/ai/tenants")
    @ResponseBody
    public ResponseEntity<?> getAiTenants() {
        try {
            List<Tenant> tenants = tenantService.querySupportAiRecords(1);
            List<Map<String, Object>> result = new ArrayList<>();
            for (Tenant tenant : tenants) {
                Map<String, Object> t = new HashMap<>();
                t.put("id", tenant.getId().toString());
                t.put("name", tenant.getUserName() + " - " + RegionEnum.getRegionCode(tenant.getRegion()));
                result.add(t);
            }
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("获取AI租户列表失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 获取指定租户的可用AI模型列表
     */
    @GetMapping("/ai/modelsByTenant")
    @ResponseBody
    public ResponseEntity<?> getModelsByTenant(@RequestParam String tenantId) {
        try {
            List<Tenant> tenants = tenantService.querySupportAiRecords(1);
            Tenant target = tenants.stream()
                    .filter(t -> t.getId().toString().equals(tenantId))
                    .findFirst().orElse(null);
            if (target == null) {
                return ResponseEntity.ok(Collections.emptyList());
            }
            List<ModelSummaryDef> models = new ArrayList<>();
            List<ModelSummary> allAvailableModels = ociAiChatUtils.getAllAvailableModels(target);
            for (ModelSummary m : allAvailableModels) {
                ModelSummaryDef def = new ModelSummaryDef();
                def.setId(m.getId());
                def.setName(m.getDisplayName());
                def.setDescription(m.getDisplayName());
                def.setProvider("OCI");
                def.setModelName(m.getDisplayName());
                def.setEnabled(true);
                def.setTenantId(target.getId().toString());
                models.add(def);
            }
            return ResponseEntity.ok(models);
        } catch (Exception e) {
            log.error("获取租户AI模型列表失败", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 启用/禁用AI配置
     */
    @PostMapping("/toggleAiConfig")
    public ResponseEntity<?> toggleAiConfig(@RequestBody Map<String, Object> request) {
        try {
            Integer cloudType = (Integer) request.getOrDefault("cloudType", 1);
            Boolean enabled = (Boolean) request.get("enabled");

            boolean updated = chatAiConfigService.updateEnabled(cloudType, enabled);
            if (updated) {
                return ResponseEntity.ok("配置状态已更新");
            } else {
                return ResponseEntity.badRequest().body("配置不存在");
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("更新配置状态失败: " + e.getMessage());
        }
    }

}
