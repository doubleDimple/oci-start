package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiConfigService;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ChatAiConfigDto;
import com.doubledimple.ociserver.config.telegram.TelegramBotService;
import com.doubledimple.ociserver.config.telegram.TelegramUserService;
import com.doubledimple.ociserver.pojo.response.ModelSummaryDef;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.pojo.request.VPSConfigRequest;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.oracle.bmc.generativeai.model.ModelSummary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.*;
import java.util.Collections;

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

    //重新注册机器人
    @PostMapping("/startTgRobot")
    public ResponseEntity<?> startTgRobot(HttpServletRequest httpRequest) {
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
        try {
            telegramBotService.restartBotExplicit();
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Telegram 机器人注册未确认，请核对已保存配置与机器人状态");
        }
    }

    /**
     * 获取Telegram AI配置
     */
    @GetMapping("/telegramAiConfigs")
    public ResponseEntity<List<ChatAiConfigDto>> getTelegramAiConfigs(HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
        try {
            List<ChatAiConfigDto> configs = chatAiConfigService.getAllConfigsByCloudType(1);
            return ResponseEntity.ok(configs);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 更新Telegram AI配置
     */
    @PostMapping("/updateTelegramAiConfig")
    public ResponseEntity<?> updateTelegramAiConfig(@RequestBody ChatAiConfigDto configDto,
                                                   HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
        try {
            // 默认cloudType为1
            if (configDto.getCloudType() == null) {
                configDto.setCloudType(1);
            }

            ChatAiConfigDto savedConfig = chatAiConfigService.saveOrUpdateConfig(configDto);
            return ResponseEntity.ok(savedConfig);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Telegram AI 配置更新未确认，请重新读取核对");
        }
    }

    /**
     * 批量更新Telegram AI配置
     */
    @PostMapping("/batchToggleTelegramAiConfigs")
    public ResponseEntity<?> batchToggleTelegramAiConfigs(@RequestBody Map<String, Object> request, HttpServletRequest httpRequest) {
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
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
            return ResponseEntity.badRequest().body("Telegram AI 配置批量更新未确认，请重新读取核对");
        }
    }

    // 删除AI配置
    @DeleteMapping("/deleteTelegramAiConfig/{id}")
    public ResponseEntity<?> deleteTelegramAiConfig(@PathVariable Long id, HttpServletRequest httpRequest) {
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
        try {
            boolean deleted = chatAiConfigService.deleteById(id);
            if (deleted) {
                return ResponseEntity.ok().build();
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Telegram AI 配置删除未确认，请重新读取核对");
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
    public ResponseEntity<?> getAiTenants(HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
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
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * 获取指定租户的可用AI模型列表
     */
    @GetMapping("/ai/modelsByTenant")
    @ResponseBody
    public ResponseEntity<?> getModelsByTenant(@RequestParam String tenantId, HttpServletRequest httpRequest, HttpServletResponse httpResponse) {
        httpResponse.setHeader("Cache-Control", "no-store");
        SystemSettingsApiController.guardSecurityWrite(httpRequest);
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
