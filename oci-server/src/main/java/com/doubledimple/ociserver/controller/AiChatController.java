package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.doubledimple.ociserver.service.TenantService;
import com.oracle.bmc.generativeai.model.ModelSummary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * AI对话控制器
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Slf4j
@Controller
@RequestMapping("/ai")
public class AiChatController  extends BaseController{

    @Resource
    private TenantService tenantService;

    @Resource
    private OciAiChatUtils ociAiChatUtils;

    /**
     * 显示AI对话页面
     *
     * @param tenantId 租户ID
     * @param model    模型对象
     * @return AI对话页面
     */
    @GetMapping("/chat")
    public String showChatPage(@RequestParam("tenantId") Long tenantId, Model model) {
        try {
            // 查找租户信息
            Tenant tenant = tenantService.getById(tenantId);

            model.addAttribute("tenant", tenant);
            model.addAttribute("tenantId", tenantId);

            // 设置页面标题
            model.addAttribute("pageTitle", "AI对话 - " + (tenant.getDefName() != null ? tenant.getDefName() : tenant.getTenancyName()));
            model.addAttribute("activePage", "api-management");

            log.info("显示AI对话页面 - 租户ID: {}", tenantId);

            return "chat";

        } catch (Exception e) {
            log.error("显示AI对话页面时发生错误: {}", e.getMessage(), e);
            model.addAttribute("error", "加载AI对话页面时发生错误: " + e.getMessage());
            return "error";
        }
    }

    /**
     * 异步获取可用的模型列表
     *
     * @param tenantId 租户ID
     * @return 模型列表的JSON响应
     */
    @GetMapping("/models")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getAvailableModels(@RequestParam("tenantId") Long tenantId) {
        Map<String, Object> response = new HashMap<>();

        try {
            // 查找租户信息
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "租户信息不存在");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取可用的模型列表
            List<ModelSummary> availableModels = ociAiChatUtils.getAllAvailableModels(tenant);

            // 转换为简单的Map列表，避免Jackson序列化问题
            List<Map<String, Object>> modelList = new ArrayList<>();
            for (ModelSummary model : availableModels) {
                Map<String, Object> modelMap = new HashMap<>();
                modelMap.put("id", model.getId());
                modelMap.put("displayName", model.getDisplayName());
                modelMap.put("version", model.getVersion());
                modelMap.put("vendor", model.getVendor());
                modelMap.put("lifecycleState", model.getLifecycleState() != null ? model.getLifecycleState().toString() : "");
                modelList.add(modelMap);
            }

            response.put("success", true);
            response.put("models", modelList);
            response.put("count", modelList.size());

            log.info("成功获取模型列表 - 租户ID: {}, 模型数量: {}", tenantId, modelList.size());

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("获取可用模型失败 - 租户ID: {}, 错误: {}", tenantId, e.getMessage(), e);
            response.put("success", false);
            response.put("message", "获取模型列表失败: 该租户不支持或者不存在模型");
            return ResponseEntity.ok(response);
        }
    }
}
