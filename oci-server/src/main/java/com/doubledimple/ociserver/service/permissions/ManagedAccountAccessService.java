package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.config.ProxyContext;
import com.doubledimple.ociserver.pojo.response.UserRes;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.Domain;
import com.oracle.bmc.identity.requests.GetDomainRequest;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.User;
import com.oracle.bmc.identitydomains.model.UserGroups;
import com.oracle.bmc.identitydomains.requests.ListUsersRequest;
import com.oracle.bmc.identitydomains.responses.ListUsersResponse;
import lombok.extern.slf4j.Slf4j;

import java.net.URI;
import java.util.List;
import java.util.Objects;
import java.util.regex.Pattern;

/** Target checks supplement the matching OCI role grants and IAM conditions. */
@Slf4j
public final class ManagedAccountAccessService {
    private static final Pattern USER_OCID = Pattern.compile("ocid1\\.user\\.[A-Za-z0-9._-]+");

    private ManagedAccountAccessService() {}

    public static void requireUserAction(Tenant tenant, String permission, String userId) {
        OciPermissions.require(tenant, permission);
        requireUserId(userId);
        if (!OciPermissions.isManaged(tenant)) return;
        if (Objects.equals(tenant.getTenantId(), userId)) {
            throw new OciPermissionDeniedException("不能通过账号管理修改正在使用的专用 API 用户");
        }
        AccountPermissionScope scope = AccountPermissionScope.parse(tenant.getAccountScopeJson());
        if ("USER_DELETE".equals(permission) && OciPermissions.allowsDirect(tenant, "USER_DELETE")) return;
        if ("USER_PASSWORD_RESET".equals(permission)
                && OciPermissions.allowsDirect(tenant, "USER_PASSWORD_RESET")
                && (scope.isAllUsers() || scope.getPasswordResetUserIds().contains(userId))) return;
        if (OciPermissions.allowsDirect(tenant, "DOMAIN_USER_MANAGE")) {
            try (IdentityDomainsClient client = openDomainClient(tenant)) {
                if (inManagementScope(scope, resolveDomainUser(client, tenant, userId))) return;
            }
        }
        throw new OciPermissionDeniedException("该用户不在已授权的账号管理范围内");
    }

    public static boolean useDomainUserManager(Tenant tenant, String permission, String userId) {
        if (!OciPermissions.isManaged(tenant)
                || !OciPermissions.allowsDirect(tenant, "DOMAIN_USER_MANAGE")) return false;
        AccountPermissionScope scope = AccountPermissionScope.parse(tenant.getAccountScopeJson());
        if ("USER_DELETE".equals(permission)) return !OciPermissions.allowsDirect(tenant, "USER_DELETE");
        return !OciPermissions.allowsDirect(tenant, "USER_PASSWORD_RESET")
                || (!scope.isAllUsers() && !scope.getPasswordResetUserIds().contains(userId));
    }

    /** Never sign a request to a client-provided domain endpoint. */
    public static IdentityDomainsClient openDomainClient(Tenant tenant) {
        String endpoint;
        if (OciPermissions.isManaged(tenant)) {
            if (tenant.getManagedDomainId() == null
                    || !tenant.getManagedDomainId().matches("ocid1\\.domain\\.[A-Za-z0-9._-]+")) {
                throw new OciPermissionDeniedException("缺少已授权身份域，请重新配置该租户的身份域权限");
            }
            try (IdentityClient identity = IdentityClient.builder().clientConfigurator(ProxyContext.get())
                    .build(OciUtils.getProvider(tenant))) {
                Domain domain = identity.getDomain(GetDomainRequest.builder()
                        .domainId(tenant.getManagedDomainId()).build()).getDomain();
                endpoint = normalizedEndpoint(tenant.getManagedDomainUrl());
                if (endpoint.isEmpty() || domain == null || !tenant.getManagedDomainId().equals(domain.getId())
                        || !tenant.getTenancy().equals(domain.getCompartmentId())
                        || (!endpoint.equals(normalizedEndpoint(domain.getUrl()))
                        && !endpoint.equals(normalizedEndpoint(domain.getHomeRegionUrl())))) {
                    throw new OciPermissionDeniedException("保存的身份域地址与 OCI 返回的身份域不一致");
                }
            }
        } else {
            try (IdentityClient identity = IdentityClient.builder().clientConfigurator(ProxyContext.get())
                    .build(OciUtils.getProvider(tenant))) {
                endpoint = normalizedEndpoint(OciUtils.getDomain(identity, tenant.getTenancy()));
            }
        }
        if (endpoint.isEmpty()) throw new IllegalArgumentException("当前租户没有可用的身份域");
        IdentityDomainsClient client = IdentityDomainsClient.builder().clientConfigurator(ProxyContext.get())
                .build(OciUtils.getProvider(tenant));
        client.setEndpoint(endpoint);
        return client;
    }

    private static String normalizedEndpoint(String endpoint) {
        if (endpoint == null || endpoint.trim().isEmpty()) return "";
        URI uri = URI.create(endpoint.trim());
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null
                || (uri.getPort() != -1 && uri.getPort() != 443)
                || (uri.getPath() != null && !uri.getPath().isEmpty() && !"/".equals(uri.getPath()))) {
            throw new OciPermissionDeniedException("身份域地址格式无效");
        }
        return "https://" + uri.getHost().toLowerCase(java.util.Locale.ROOT);
    }

    public static User resolveDomainUser(IdentityDomainsClient client, Tenant tenant, String userId) {
        requireUserId(userId);
        User found = null;
        String page = null;
        do {
            ListUsersResponse response = client.listUsers(ListUsersRequest.builder()
                    .filter("ocid eq \"" + userId + "\"")
                    .attributes("id,ocid,userName,tenancyOcid,domainOcid,active,groups").page(page).build());
            if (response.getUsers() == null || response.getUsers().getResources() == null) {
                throw new OciPermissionDeniedException("身份域没有返回可验证的用户信息");
            }
            for (User user : response.getUsers().getResources()) {
                if (found != null || !userId.equals(user.getOcid()) || user.getId() == null
                        || !tenant.getTenancy().equals(user.getTenancyOcid())
                        || (OciPermissions.isManaged(tenant)
                        && !tenant.getManagedDomainId().equals(user.getDomainOcid()))) {
                    throw new OciPermissionDeniedException("无法确认目标用户所属身份域");
                }
                found = user;
            }
            page = response.getOpcNextPage();
        } while (page != null && !page.isEmpty());
        if (found == null) throw new OciPermissionDeniedException("找不到目标用户，或无权管理该用户");
        return found;
    }

    private static boolean inManagementScope(AccountPermissionScope scope, User user) {
        if (scope.isAllUsers()) return true;
        if (user.getGroups() == null) return false;
        for (UserGroups membership : user.getGroups()) {
            if (scope.getUserManagementGroupIds().contains(membership.getOcid())) return true;
        }
        return false;
    }

    /** Button metadata is fail-closed; cloud errors must not grant local actions. */
    public static void enrichUsers(Tenant tenant, List<UserRes> users) {
        if (!OciPermissions.isManaged(tenant)) {
            for (UserRes user : users) {
                user.setCanResetPassword(true);
                user.setCanDelete(true);
            }
            try (IdentityDomainsClient client = openDomainClient(tenant)) {
                for (UserRes user : users) {
                    try {
                        User domainUser = resolveDomainUser(client, tenant, user.getId());
                        user.setActive(domainUser.getActive());
                        user.setCanManage(domainUser.getActive() != null);
                    } catch (RuntimeException e) {
                        log.debug("无法读取该用户的身份域状态");
                    }
                }
            } catch (RuntimeException e) {
                log.debug("该 API 当前无法查询身份域用户状态");
            }
            return;
        }
        AccountPermissionScope scope;
        try {
            scope = AccountPermissionScope.parse(tenant.getAccountScopeJson());
        } catch (RuntimeException e) {
            return;
        }
        for (UserRes user : users) {
            if (Objects.equals(tenant.getTenantId(), user.getId())) continue;
            user.setCanDelete(OciPermissions.allowsDirect(tenant, "USER_DELETE"));
            user.setCanResetPassword(OciPermissions.allowsDirect(tenant, "USER_PASSWORD_RESET")
                    && (scope.isAllUsers() || scope.getPasswordResetUserIds().contains(user.getId())));
        }
        if (!OciPermissions.allowsDirect(tenant, "DOMAIN_USER_MANAGE")) return;
        try (IdentityDomainsClient client = openDomainClient(tenant)) {
            for (UserRes user : users) {
                if (Objects.equals(tenant.getTenantId(), user.getId())) continue;
                try {
                    User domainUser = resolveDomainUser(client, tenant, user.getId());
                    user.setActive(domainUser.getActive());
                    boolean managed = inManagementScope(scope, domainUser);
                    user.setCanManage(managed);
                    user.setCanResetPassword(user.isCanResetPassword() || managed);
                    user.setCanDelete(user.isCanDelete() || managed);
                } catch (RuntimeException e) {
                    log.debug("目标用户不可由当前身份域账号范围管理");
                }
            }
        } catch (RuntimeException e) {
            log.debug("无法读取身份域用户范围，已隐藏对应管理操作");
        }
    }

    private static void requireUserId(String userId) {
        if (userId == null || !USER_OCID.matcher(userId).matches()) {
            throw new IllegalArgumentException("用户 ID 必须是 OCI 用户 OCID");
        }
    }
}
