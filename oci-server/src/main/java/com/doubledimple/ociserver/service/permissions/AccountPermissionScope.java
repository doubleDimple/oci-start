package com.doubledimple.ociserver.service.permissions;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;

import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/** Explicit targets for credential changes and delegated identity-domain user management. */
public final class AccountPermissionScope {
    private static final Pattern USER_OCID = Pattern.compile("ocid1\\.user\\.[A-Za-z0-9._-]+");
    private static final Pattern GROUP_OCID = Pattern.compile("ocid1\\.group\\.[A-Za-z0-9._-]+");
    private final boolean allUsers;
    private final Set<String> passwordResetUserIds;
    private final Set<String> userManagementGroupIds;

    private AccountPermissionScope(boolean allUsers, Set<String> userIds, Set<String> groupIds) {
        this.allUsers = allUsers;
        this.passwordResetUserIds = Collections.unmodifiableSet(userIds);
        this.userManagementGroupIds = Collections.unmodifiableSet(groupIds);
    }

    public static AccountPermissionScope parse(String value) {
        if (value == null || value.trim().isEmpty()) {
            return new AccountPermissionScope(false, new LinkedHashSet<>(), new LinkedHashSet<>());
        }
        try {
            if (value.length() > 32768) throw new IllegalArgumentException();
            JSONObject object = JSON.parseObject(value);
            if (object == null) throw new IllegalArgumentException();
            for (String field : object.keySet()) {
                if (!"allUsers".equals(field) && !"passwordResetUserIds".equals(field)
                        && !"userManagementGroupIds".equals(field)) throw new IllegalArgumentException();
            }
            Object all = object.get("allUsers");
            if (all != null && !(all instanceof Boolean)) throw new IllegalArgumentException();
            return new AccountPermissionScope(Boolean.TRUE.equals(all),
                    ids(object.get("passwordResetUserIds"), USER_OCID),
                    ids(object.get("userManagementGroupIds"), GROUP_OCID));
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("账号管理范围无效，请填写有效的用户或用户组 OCID");
        }
    }

    public static AccountPermissionScope forSelection(String value, Collection<String> selected) {
        AccountPermissionScope parsed = parse(value);
        boolean reset = selected.contains("USER_PASSWORD_RESET");
        boolean manage = selected.contains("DOMAIN_USER_MANAGE");
        if (!reset && !manage) return parse(null);
        if (!parsed.allUsers && reset && parsed.passwordResetUserIds.isEmpty()) {
            throw new IllegalArgumentException("请选择允许重置密码的用户 OCID");
        }
        if (!parsed.allUsers && manage && parsed.userManagementGroupIds.isEmpty()) {
            throw new IllegalArgumentException("请选择允许管理的用户组 OCID");
        }
        return new AccountPermissionScope(parsed.allUsers,
                reset && !parsed.allUsers ? new LinkedHashSet<>(parsed.passwordResetUserIds) : new LinkedHashSet<>(),
                manage && !parsed.allUsers ? new LinkedHashSet<>(parsed.userManagementGroupIds) : new LinkedHashSet<>());
    }

    private static Set<String> ids(Object raw, Pattern pattern) {
        LinkedHashSet<String> result = new LinkedHashSet<>();
        if (raw == null) return result;
        if (!(raw instanceof JSONArray) || ((JSONArray) raw).size() > 50) throw new IllegalArgumentException();
        for (Object entry : (JSONArray) raw) {
            if (!(entry instanceof String)) throw new IllegalArgumentException();
            String id = ((String) entry).trim();
            if (id.length() > 255 || !pattern.matcher(id).matches()) throw new IllegalArgumentException();
            result.add(id);
        }
        return result;
    }

    public boolean isAllUsers() { return allUsers; }
    public Set<String> getPasswordResetUserIds() { return passwordResetUserIds; }
    public Set<String> getUserManagementGroupIds() { return userManagementGroupIds; }

    public String toJson() {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("allUsers", allUsers);
        fields.put("passwordResetUserIds", passwordResetUserIds);
        fields.put("userManagementGroupIds", userManagementGroupIds);
        return JSON.toJSONString(fields);
    }
}
