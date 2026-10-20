package com.doubledimple.ociserver.controller;

import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.config.annotations.AuditLog;
import com.doubledimple.ociserver.service.permissions.ManagedTenantImportService;
import com.doubledimple.ociserver.service.permissions.OciPermissionCatalog;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;

@RestController
@RequestMapping("/tenants")
@Slf4j
public class ManagedTenantController {
    @Resource
    private ManagedTenantImportService managedTenantImportService;
    @Resource private OracleInstanceDetailRepository instanceRepository;
    @Resource private TenantRepository tenantRepository;

    @GetMapping("/permissions/catalog")
    public ApiResponse catalog() {
        return ApiResponse.success(OciPermissionCatalog.describe());
    }

    @GetMapping("/permissions/instance-context")
    public ApiResponse instanceContext(@RequestParam String instanceId) {
        InstanceDetails instance;
        try {
            instance = instanceId.startsWith("ocid1.instance.") ? instanceRepository.findByInstanceId(instanceId)
                    : instanceRepository.findById(Long.valueOf(instanceId)).orElse(null);
        } catch (NumberFormatException e) {
            return ApiResponse.error("实例 ID 无效");
        }
        if (instance == null) return ApiResponse.error("实例不存在");
        if (instance.getCloudType() != 1) {
            java.util.Map<String, Object> data = new java.util.LinkedHashMap<>();
            data.put("id", String.valueOf(instance.getTenantId()));
            data.put("tenantId", String.valueOf(instance.getTenantId()));
            data.put("nonOci", true);
            data.put("permissionMode", "");
            data.put("permissionsJson", null);
            return ApiResponse.success(data);
        }
        Tenant tenant = tenantRepository.findById(instance.getTenantId()).orElse(null);
        if (tenant == null) return ApiResponse.error("租户不存在");
        java.util.Map<String, Object> data = new java.util.LinkedHashMap<>();
        data.put("id", String.valueOf(tenant.getId()));
        data.put("tenantId", String.valueOf(tenant.getId()));
        data.put("permissionMode", tenant.getPermissionMode());
        data.put("permissionsJson", tenant.getPermissionsJson());
        data.put("managedUserName", tenant.getManagedUserName());
        return ApiResponse.success(data);
    }

    @PostMapping(path = "/restricted/save", consumes = "multipart/form-data")
    @AuditLog(title = "配置 OCI 专用用户权限", saveParams = false, saveResponse = false)
    public ApiResponse save(
            @RequestParam String tenantId,
            @RequestParam String tenancy,
            @RequestParam String fingerprint,
            @RequestParam String region,
            @RequestParam String userName,
            @RequestParam String managedUserName,
            @RequestParam String permissions,
            @RequestParam(required = false) String accountScope,
            @RequestParam("keyFileStr") MultipartFile keyFile) {
        try {
            return ApiResponse.success(managedTenantImportService.save(tenantId, tenancy, fingerprint,
                    region, userName, managedUserName, permissions, accountScope, keyFile));
        } catch (IllegalArgumentException e) {
            return ApiResponse.error(e.getMessage());
        } catch (Exception e) {
            // 不输出 SDK 请求、上传凭证或异常中的敏感内容。
            log.warn("配置 OCI 专用用户失败，异常类型:{}", e.getClass().getSimpleName());
            return ApiResponse.error("配置专用用户失败。请检查原 API 的用户、组及策略管理权限；原 API 不会作为租户凭证保存。");
        }
    }
}
