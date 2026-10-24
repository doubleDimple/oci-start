package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.dao.entity.Tenant;

/** 本地选择与 OCI 云端策略双重限制；历史凭证保持原有行为。 */
public final class OciPermissions {
    public static final String MODE = "managed-v1";

    private OciPermissions() {}

    public static boolean isManaged(Tenant tenant) {
        return tenant != null && tenant.getPermissionMode() != null
                && !tenant.getPermissionMode().trim().isEmpty();
    }

    public static boolean allows(Tenant tenant, String permission) {
        if (allowsDirect(tenant, permission)) return true;
        if ("USER_DISABLE".equals(permission) || "USER_ENABLE".equals(permission)
                || "USER_PASSWORD_RESET".equals(permission) || "USER_DELETE".equals(permission)) {
            return allowsDirect(tenant, "DOMAIN_USER_MANAGE");
        }
        if ("NOTIFICATION_EMAIL".equals(permission) || "MFA_MANAGE".equals(permission)
                || "SOCIAL_MANAGE".equals(permission) || "PASSWORD_POLICY".equals(permission)) {
            return allowsDirect(tenant, "DOMAIN_SECURITY_MANAGE");
        }
        return false;
    }

    /** Distinguish an explicitly selected action from a role's scoped capabilities. */
    public static boolean allowsDirect(Tenant tenant, String permission) {
        if (tenant == null) return false;
        if (!isManaged(tenant)) return true;
        if (!MODE.equals(tenant.getPermissionMode())) return false;
        try {
            return OciPermissionCatalog.parse(tenant.getPermissionsJson()).contains(permission);
        } catch (RuntimeException ignored) {
            // 元数据损坏时不放宽权限。
            return false;
        }
    }

    public static void require(Tenant tenant, String permission) {
        if (!allows(tenant, permission)) {
            throw new OciPermissionDeniedException("此租户未授权该操作：" + permission);
        }
    }
}
