package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.utils.IpUtils;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.service.TenantService;
import com.doubledimple.ociserver.utils.oracle.OciConsoleUtils;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.core.model.InstanceConsoleConnection;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import javax.annotation.Resource;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

/**
 * @version 1.0.0
 * @ClassName CloudShellController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-24 16:49
 */
@Slf4j
@Controller
@RequestMapping("/oci/console")
public class CloudShellController  extends BaseController{

    @Resource
    private TenantService tenantService;

    @Resource
    private OracleInstanceService oracleInstanceService;

    /**
     * 显示控制台终端页面
     */
    @GetMapping("/terminal")
    public String showConsoleTerminal(Model model) {
        // 设置侧边栏激活菜单
        model.addAttribute("activePage", "api-ociBootList");
        return "console_terminal";
    }

    /**
     * 显示指定实例的控制台终端页面
     */
    @GetMapping("/terminal/{instanceId}")
    public String showConsoleTerminalWithInstance(@PathVariable String instanceId,
                                                  Model model) {
        try {
            // 获取实例详情
            InstanceDetails instanceByInstanceId = oracleInstanceService.getInstanceById(Long.valueOf(instanceId));
            if (instanceByInstanceId == null) {
                throw new RuntimeException("实例不存在");
            }

            // 添加实例信息到模型
            model.addAttribute("instance", instanceByInstanceId);
            model.addAttribute("instanceId", instanceId);
            model.addAttribute("ociInstanceId", instanceByInstanceId.getInstanceId());
            model.addAttribute("instanceIp", instanceByInstanceId.getPublicIps());  // 公网IP
            model.addAttribute("instanceName", instanceByInstanceId.getDisplayName());  // 实例名称

            // 添加租户ID（优先使用实例中的租户ID）
            Long actualTenantId = instanceByInstanceId.getTenantId();
            model.addAttribute("tenantId", String.valueOf(actualTenantId));

            String publicIp = IpUtils.getPublicIp();
            model.addAttribute("serverIp", publicIp);
            // 设置侧边栏激活菜单
            model.addAttribute("activePage", "api-ociBootList");

            return "console_terminal";

        } catch (NumberFormatException e) {
            log.error("无效的实例ID格式: {}", instanceId);
            throw new RuntimeException("无效的实例ID格式");
        }
    }

    /**
     * 创建控制台连接（REST API）
     */
    @PostMapping("/create")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> createConsoleConnection(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String instanceId = (String) request.get("instanceId");
            Object tenantIdObj = request.get("tenantId");
            String displayName = (String) request.get("displayName");

            // 处理tenantId的类型转换
            Long tenantId = null;
            if (tenantIdObj != null) {
                if (tenantIdObj instanceof Long) {
                    tenantId = (Long) tenantIdObj;
                } else if (tenantIdObj instanceof String) {
                    try {
                        String tenantIdStr = ((String) tenantIdObj).replaceAll(",", "");
                        tenantId = Long.parseLong(tenantIdStr);
                    } catch (NumberFormatException e) {
                        log.error("无效的租户ID格式: {}", tenantIdObj);
                        response.put("success", false);
                        response.put("message", "无效的租户ID格式");
                        return ResponseEntity.badRequest().body(response);
                    }
                } else if (tenantIdObj instanceof Number) {
                    tenantId = ((Number) tenantIdObj).longValue();
                }
            }

            if (tenantId == null) {
                response.put("success", false);
                response.put("message", "缺少租户ID");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 创建控制台连接
            OciConsoleUtils.ConsoleConnectionResult result =
                    OciConsoleUtils.createConsoleConnectionWithAutoKey(tenant, instanceId, displayName);

            if (result == null) {
                response.put("success", false);
                response.put("message", "创建控制台连接失败");
                return ResponseEntity.badRequest().body(response);
            }

            response.put("success", true);
            response.put("connectionId", result.getConnectionId());
            response.put("connectionString", result.getConnectionString());
            response.put("vncConnectionString", result.getVncConnectionString());
            response.put("keyGenerated", result.isKeyGenerated());

            if (result.getKeyPair() != null) {
                response.put("publicKeyOpenSSH", result.getKeyPair().getPublicKeyOpenSSH());
            }

            log.info("成功创建控制台连接，实例: {}, 连接ID: {}", instanceId, result.getConnectionId());
            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("创建控制台连接失败", e);
            response.put("success", false);
            response.put("message", "创建控制台连接失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    //重新引导
    @PostMapping("/heavyNewRestart")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> heavyNewRestart(@RequestBody Map<String, Object> request) {
        Map<String, Object> response = new HashMap<>();

        try {
            String instanceId = (String) request.get("instanceId");
            Object tenantIdObj = request.get("tenantId");

            // 处理tenantId的类型转换
            Long tenantId = null;
            if (tenantIdObj != null) {
                if (tenantIdObj instanceof Long) {
                    tenantId = (Long) tenantIdObj;
                } else if (tenantIdObj instanceof String) {
                    try {
                        String tenantIdStr = ((String) tenantIdObj).replaceAll(",", "");
                        tenantId = Long.parseLong(tenantIdStr);
                    } catch (NumberFormatException e) {
                        log.error("无效的租户ID格式: {}", tenantIdObj);
                        response.put("success", false);
                        response.put("message", "无效的租户ID格式");
                        return ResponseEntity.badRequest().body(response);
                    }
                } else if (tenantIdObj instanceof Number) {
                    tenantId = ((Number) tenantIdObj).longValue();
                }
            }

            if (tenantId == null) {
                response.put("success", false);
                response.put("message", "缺少租户ID");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            CompletableFuture.runAsync(() ->OciUtils.resetInstance(tenant, instanceId));
            response.put("success", true);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("重新引导失败", e);
            response.put("success", false);
            response.put("message", "重新引导失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    /**
     * 工具方法：安全地将对象转换为Long类型
     */
    private Long parseTenantId(Object tenantIdObj) {
        if (tenantIdObj == null) {
            return null;
        }

        if (tenantIdObj instanceof Long) {
            return (Long) tenantIdObj;
        } else if (tenantIdObj instanceof String) {
            try {
                String tenantIdStr = ((String) tenantIdObj).replaceAll(",", "");
                return Long.parseLong(tenantIdStr);
            } catch (NumberFormatException e) {
                log.error("无效的租户ID格式: {}", tenantIdObj);
                return null;
            }
        } else if (tenantIdObj instanceof Number) {
            return ((Number) tenantIdObj).longValue();
        }

        return null;
    }

    /**
     * 获取控制台连接详情
     */
    @GetMapping("/connection/{connectionId}")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getConsoleConnectionDetails(@PathVariable String connectionId,
                                                                           @RequestParam String tenantId) {
        Map<String, Object> response = new HashMap<>();

        try {
            // 安全地解析租户ID
            Long tenantIdLong = parseTenantId(tenantId);
            if (tenantIdLong == null) {
                response.put("success", false);
                response.put("message", "无效的租户ID格式");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantIdLong);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取连接详情
            InstanceConsoleConnection connection = OciConsoleUtils.getConsoleConnectionDetails(tenant, connectionId);
            if (connection == null) {
                response.put("success", false);
                response.put("message", "控制台连接不存在");
                return ResponseEntity.notFound().build();
            }

            response.put("success", true);
            response.put("connectionId", connection.getId());
            response.put("instanceId", connection.getInstanceId());
            response.put("lifecycleState", connection.getLifecycleState().getValue());
            response.put("connectionString", connection.getConnectionString());
            response.put("vncConnectionString", connection.getVncConnectionString());

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("获取控制台连接详情失败", e);
            response.put("success", false);
            response.put("message", "获取连接详情失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    /**
     * 列出实例的所有控制台连接
     */
    @GetMapping("/connections/{instanceId}")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> listConsoleConnections(@PathVariable String instanceId,
                                                                      @RequestParam String tenantId) {
        Map<String, Object> response = new HashMap<>();

        try {
            // 安全地解析租户ID
            Long tenantIdLong = parseTenantId(tenantId);
            if (tenantIdLong == null) {
                response.put("success", false);
                response.put("message", "无效的租户ID格式");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantIdLong);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取连接列表
            List<InstanceConsoleConnection> connections =
                    OciConsoleUtils.listConsoleConnections(tenant, instanceId);

            response.put("success", true);
            response.put("connections", connections);
            response.put("count", connections.size());

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("列出控制台连接失败", e);
            response.put("success", false);
            response.put("message", "列出连接失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    /**
     * 删除控制台连接
     */
    @DeleteMapping("/connection/{connectionId}")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> deleteConsoleConnection(@PathVariable String connectionId,
                                                                       @RequestParam String tenantId) {
        Map<String, Object> response = new HashMap<>();

        try {
            // 安全地解析租户ID
            Long tenantIdLong = parseTenantId(tenantId);
            if (tenantIdLong == null) {
                response.put("success", false);
                response.put("message", "无效的租户ID格式");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantIdLong);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 删除连接
            boolean deleted = OciConsoleUtils.deleteConsoleConnection(tenant, connectionId);

            response.put("success", deleted);
            response.put("message", deleted ? "控制台连接已删除" : "删除控制台连接失败");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("删除控制台连接失败", e);
            response.put("success", false);
            response.put("message", "删除连接失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    /**
     * 清理实例的所有控制台连接
     */
    @DeleteMapping("/connections/{instanceId}/cleanup")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> cleanupConsoleConnections(@PathVariable String instanceId,
                                                                         @RequestParam String tenantId) {
        Map<String, Object> response = new HashMap<>();

        try {
            // 安全地解析租户ID
            Long tenantIdLong = parseTenantId(tenantId);
            if (tenantIdLong == null) {
                response.put("success", false);
                response.put("message", "无效的租户ID格式");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantIdLong);
            if (tenant == null) {
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 清理连接
            int cleanedCount = OciConsoleUtils.cleanupConsoleConnections(tenant, instanceId);

            response.put("success", true);
            response.put("cleanedCount", cleanedCount);
            response.put("message", "已清理 " + cleanedCount + " 个控制台连接");

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            log.error("清理控制台连接失败", e);
            response.put("success", false);
            response.put("message", "清理连接失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }

    /**
     * 一键创建控制台连接并保存密钥
     */
    @PostMapping("/create-and-save-key")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> createConsoleConnectionAndSaveKey(@RequestBody Map<String, Object> request) {
        try {
            String instanceId = (String) request.get("instanceId");
            Object tenantIdObj = request.get("tenantId");
            String displayName = (String) request.get("displayName");
            String keyName = (String) request.get("keyName");
            String saveDirectory = (String) request.get("saveDirectory");

            // 安全地解析租户ID
            Long tenantId = parseTenantId(tenantIdObj);
            if (tenantId == null) {
                Map<String, Object> response = new HashMap<>();
                response.put("success", false);
                response.put("message", "无效的租户ID格式");
                return ResponseEntity.badRequest().body(response);
            }

            // 获取租户信息
            Tenant tenant = tenantService.getById(tenantId);
            if (tenant == null) {
                Map<String, Object> response = new HashMap<>();
                response.put("success", false);
                response.put("message", "未找到租户信息");
                return ResponseEntity.badRequest().body(response);
            }

            // 创建连接并保存密钥
            Map<String, Object> result = OciConsoleUtils.createConsoleConnectionAndSaveKey(
                    tenant, instanceId, keyName, saveDirectory, displayName);

            return ResponseEntity.ok(result);

        } catch (Exception e) {
            log.error("创建控制台连接并保存密钥失败", e);
            Map<String, Object> response = new HashMap<>();
            response.put("success", false);
            response.put("message", "操作失败: " + e.getMessage());
            return ResponseEntity.badRequest().body(response);
        }
    }
}
