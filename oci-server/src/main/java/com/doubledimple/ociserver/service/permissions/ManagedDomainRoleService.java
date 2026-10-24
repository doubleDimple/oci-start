package com.doubledimple.ociserver.service.permissions;

import com.fasterxml.jackson.databind.JsonNode;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.http.client.Method;
import com.oracle.bmc.identity.model.DomainSummary;
import com.oracle.bmc.identitydomains.model.*;
import com.oracle.bmc.identitydomains.requests.*;
import com.oracle.bmc.model.BmcException;
import lombok.Getter;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.Supplier;

/**
 * Reconciles only administrator grants owned by this managed identity.
 * Callers must first verify ownership of the IAM user/group, serialize imports
 * for ownerToken, and audit all group memberships and tenancy policies.
 * Administrator roles are domain-wide bundles, not individual UI operations.
 */
@Service
public class ManagedDomainRoleService {
    public static final String SECURITY_ADMIN = "SECURITY_ADMIN";
    public static final String USER_MANAGER = "USER_MANAGER";
    private static final String MANAGER = "oci-start-managed-by";
    private static final String OWNER = "oci-start-identity";
    private static final String ROLE = "oci-start-role";
    private static final String CONFIG = "oci-start-role-scope";
    private static final String VERSION = "domain-roles-v1";
    private static final String GRANT_SCHEMA = "urn:ietf:params:scim:schemas:oracle:idcs:Grant";
    private static final String GRANT_EXTENSION = "urn:ietf:params:scim:schemas:oracle:idcs:extension:idcsAppRole:Grant";
    private static final String USER_EXTENSION = "urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User";
    private static final String GROUP_EXTENSION = "urn:ietf:params:scim:schemas:oracle:idcs:extension:group:Group";
    private static final int PAGE_SIZE = 100;

    public Result audit(SimpleAuthenticationDetailsProvider admin, DomainSummary domain,
                        String tenancyId, String userOcid, String groupOcid, String ownerToken) {
        return safe(ManagedImportDiagnostics.Stage.DOMAIN_AUDIT, () -> {
            Context context = context(admin, domain, tenancyId, userOcid, groupOcid, ownerToken);
            if (context == null) {
                return new Result();
            }
            try (ManagedDomainGrantClient client = new ManagedDomainGrantClient(admin, context.endpoint)) {
                return inspect(client, context);
            }
        });
    }

    public Result reconcile(SimpleAuthenticationDetailsProvider admin, DomainSummary domain,
                            String tenancyId, String userOcid, String groupOcid, String ownerToken,
                            boolean securityAdminEnabled) {
        return reconcile(admin, domain, tenancyId, userOcid, groupOcid, ownerToken,
                securityAdminEnabled, false, false, Collections.emptyList());
    }

    /**
     * An empty group collection never implies all users. allUsers must be an
     * explicit, persisted selection supplied by the import request.
     */
    public Result reconcile(SimpleAuthenticationDetailsProvider admin, DomainSummary domain,
                            String tenancyId, String userOcid, String groupOcid, String ownerToken,
                            boolean securityAdminEnabled, boolean userManagerEnabled,
                            boolean allUsers, Collection<String> userManagementGroupOcids) {
        return safe(ManagedImportDiagnostics.Stage.DOMAIN_RECONCILE, () -> {
            Context context = context(admin, domain, tenancyId, userOcid, groupOcid, ownerToken);
            if (context == null) {
                if (securityAdminEnabled || userManagerEnabled) {
                    throw failure("当前租户没有可授权的默认身份域，无法启用身份域管理功能。");
                }
                return new Result();
            }
            if (userOcid == null || groupOcid == null) {
                throw failure("专用用户和专用组创建完成后才能更新身份域角色。");
            }
            try (ManagedDomainGrantClient client = new ManagedDomainGrantClient(admin, context.endpoint)) {
                Result before = inspect(client, context);
                Set<String> selectedRoles = new LinkedHashSet<>();
                if (securityAdminEnabled) {
                    selectedRoles.add(SECURITY_ADMIN);
                }
                if (userManagerEnabled) {
                    selectedRoles.add(USER_MANAGER);
                }
                populateRoles(client, context, before, selectedRoles);
                Map<String, GrantMetadata> desired = new LinkedHashMap<>();
                if (securityAdminEnabled) {
                    desired.put(SECURITY_ADMIN, desired(before, SECURITY_ADMIN, Collections.emptySet(), true));
                }
                if (userManagerEnabled) {
                    SortedSet<String> targets = validateScope(client, context, before,
                            allUsers, userManagementGroupOcids);
                    desired.put(USER_MANAGER, desired(before, USER_MANAGER, targets, allUsers));
                }
                // Remove revoked/narrowed grants before adding any new grant.
                // A failed update never falls back to a broader role or scope.
                for (GrantMetadata current : before.grants) {
                    GrantMetadata wanted = desired.get(current.roleKey);
                    if (wanted == null || !sameConfiguration(current, wanted)) {
                        deleteOwned(client, context, current);
                    }
                }
                Result afterRemoval = inspect(client, context);
                for (GrantMetadata wanted : desired.values()) {
                    GrantMetadata current = byRole(afterRemoval.grants, wanted.roleKey);
                    if (current != null && !sameConfiguration(current, wanted)) {
                        throw failure("身份域权限撤回尚未同步，请稍后重试。");
                    }
                    if (current == null) {
                        createOwned(client, context, wanted);
                    }
                }
                Result result = inspect(client, context);
                if (result.grants.size() != desired.size()) {
                    throw failure("身份域角色授权尚未同步，导入未完成，请以相同用户名重试。");
                }
                for (GrantMetadata current : result.grants) {
                    if (!sameConfiguration(current, desired.get(current.roleKey))) {
                        throw failure("身份域实际角色范围与所选范围不一致，已停止导入。");
                    }
                }
                return result;
            }
        });
    }

    private Result inspect(ManagedDomainGrantClient client, Context context) {
        Result result = new Result();
        result.domainId = context.domainId;
        result.domainUrl = context.endpoint;
        User user = context.userOcid == null ? null : uniqueUser(client, context, context.userOcid);
        Group group = context.groupOcid == null ? null : uniqueGroup(client, context, context.groupOcid);
        result.userScimId = user == null ? null : user.getId();
        result.groupScimId = group == null ? null : group.getId();
        if (user == null && group == null) {
            return result;
        }
        List<String> filters = new ArrayList<>();
        if (user != null) {
            filters.add("(grantee.value eq " + quoted(user.getId()) + ")");
        }
        if (group != null) {
            filters.add("(grantee.value eq " + quoted(group.getId()) + ")");
        }
        String filter = String.join(" or ", filters);
        // Start with the complete collection. Core-only identities need no
        // administrator endpoint or metadata for roles they do not hold.
        Map<String, JsonNode> directGrants = new LinkedHashMap<>();
        Set<String> actualRoles = new LinkedHashSet<>();
        for (JsonNode grant : listGrants(client, "Grants", filter)) {
            if (isUserInheritance(grant, result)) {
                // Effective administrator roles are checked below against
                // the dedicated group's owned grants and actual membership.
                continue;
            }
            actualRoles.add(ownedRoleKey(context, grant));
            directGrants.put(text(grant, "id"), grant);
        }
        populateRoles(client, context, result, actualRoles);
        List<JsonNode> adminGrants = directGrants.isEmpty() ? Collections.emptyList()
                : listGrants(client, "IDCSAppRoleGrants", filter);
        Set<String> knownIds = new HashSet<>();
        for (JsonNode grant : adminGrants) {
            if (isUserInheritance(grant, result)) {
                // Materialized inheritance is checked against the audited group
                // grant and user's actual memberships below/by the provisioner.
                continue;
            }
            GrantMetadata owned = ownedGrant(context, result, grant);
            JsonNode generalGrant = directGrants.get(owned.grantId);
            if (generalGrant == null
                    || !owned.roleKey.equals(ownedRoleKey(context, generalGrant))
                    || !configurationHash(owned).equals(tags(generalGrant).get(CONFIG))) {
                throw failure("身份域授权清单尚未同步，无法确认完整的受管权限，请稍后重试。");
            }
            if (!knownIds.add(owned.grantId) || byRole(result.grants, owned.roleKey) != null) {
                throw failure("发现重复的身份域管理角色授权，请先核对云端专用身份。");
            }
            result.grants.add(owned);
            result.managedGrantIds.put(owned.roleKey, owned.grantId);
            if (user != null && (USER_MANAGER.equals(owned.roleKey)
                    || list(user.getGroups()).stream().anyMatch(value ->
                    Objects.equals(context.groupOcid, value.getOcid())))) {
                result.allowedUserAdminRoleIds.add(owned.roleId);
            }
            if (SECURITY_ADMIN.equals(owned.roleKey)) {
                result.allowedGroupAdminRoleIds.add(owned.roleId);
            }
        }
        if (!knownIds.equals(directGrants.keySet())) {
            throw failure("身份域授权清单存在未经确认的授权，已停止更新，未删除该授权。");
        }
        if (user != null) {
            auditUserRoles(user, result);
        }
        if (group != null) {
            auditGroupRoles(group, result);
        }
        return result;
    }

    private void populateRoles(ManagedDomainGrantClient client, Context context,
                               Result result, Set<String> roleKeys) {
        // Discover only required server-issued IDs; never manufacture role IDs.
        if (roleKeys.contains(SECURITY_ADMIN) && result.securityRoleId == null) {
            AppRole role = builtinRole(client, context, "Security Administrator", false);
            result.securityRoleId = role.getId();
            result.securityAppId = role.getApp().getValue();
        }
        if (roleKeys.contains(USER_MANAGER) && result.userManagerRoleId == null) {
            AppRole role = builtinRole(client, context, "User Manager", true);
            result.userManagerRoleId = role.getId();
            result.userManagerAppId = role.getApp().getValue();
        }
    }

    private static boolean isUserInheritance(JsonNode grant, Result identity) {
        return identity.userScimId != null
                && "GROUP_MEMBERSHIP".equals(text(grant, "grantMechanism"))
                && identity.userScimId.equals(grant.path("grantee").path("value").asText());
    }

    private static String ownedRoleKey(Context context, JsonNode grant) {
        Map<String, String> tags = tags(grant);
        String roleKey = tags.get(ROLE);
        if (!VERSION.equals(tags.get(MANAGER)) || !context.owner.equals(tags.get(OWNER))
                || (!SECURITY_ADMIN.equals(roleKey) && !USER_MANAGER.equals(roleKey))) {
            throw failure("专用身份已有非本系统管理的管理员授权，未接管或删除该授权。");
        }
        return roleKey;
    }

    private AppRole builtinRole(ManagedDomainGrantClient client, Context context,
                                String displayName, boolean scoped) {
        List<AppRole> matches = new ArrayList<>();
        int start = 1;
        Set<String> seen = new HashSet<>();
        while (true) {
            AppRoles page = client.listAppRoles(ListAppRolesRequest.builder()
                    .filter("adminRole eq true and displayName eq " + quoted(displayName))
                    .startIndex(start).count(PAGE_SIZE).attributeSets(AttributeSets.All).build()).getAppRoles();
            if (page == null) {
                throw failure("无法读取身份域内置管理角色。");
            }
            List<AppRole> rows = list(page.getResources());
            for (AppRole role : rows) {
                if (!hasText(role.getId()) || !seen.add(role.getId())) {
                    throw failure("身份域管理角色分页结果不完整。");
                }
                if (displayName.equals(role.getDisplayName()) && Boolean.TRUE.equals(role.getAdminRole())) {
                    matches.add(role);
                }
            }
            if (!more(page.getTotalResults(), page.getStartIndex(), start, rows.size())) {
                break;
            }
            start += rows.size();
        }
        if (matches.size() != 1) {
            throw failure("无法唯一识别 Oracle 内置管理角色，未授予替代角色。");
        }
        AppRole role = matches.get(0);
        assertDomain(context, role.getDomainOcid(), role.getTenancyOcid());
        if (role.getApp() == null || !hasText(role.getApp().getValue())
                || !list(role.getIdcsPreventedOperations()).contains(IdcsPreventedOperations.Delete)
                || !Boolean.TRUE.equals(scoped ? role.getAvailableToUsers() : role.getAvailableToGroups())
                || (scoped && !Boolean.TRUE.equals(role.getLimitedToOneOrMoreGroups()))) {
            throw failure("身份域角色缺少可验证的内置标识或所需范围能力，未授予权限。");
        }
        App app = client.getApp(GetAppRequest.builder().appId(role.getApp().getValue())
                .attributes("id,name,infrastructure,domainOcid,tenancyOcid,idcsPreventedOperations").build()).getApp();
        if (app == null || !"IDCSApp".equals(app.getName())
                || !Boolean.TRUE.equals(app.getInfrastructure())
                || !list(app.getIdcsPreventedOperations()).contains(IdcsPreventedOperations.Delete)) {
            throw failure("角色不属于可验证的 Oracle 身份域系统应用，未授予权限。");
        }
        assertDomain(context, app.getDomainOcid(), app.getTenancyOcid());
        return role;
    }

    private GrantMetadata ownedGrant(Context context, Result identity, JsonNode grant) {
        assertDomain(context, text(grant, "domainOcid"), text(grant, "tenancyOcid"));
        Map<String, String> tags = tags(grant);
        String roleKey = ownedRoleKey(context, grant);
        boolean security = SECURITY_ADMIN.equals(roleKey);
        String roleId = security ? identity.securityRoleId : identity.userManagerRoleId;
        String appId = security ? identity.securityAppId : identity.userManagerAppId;
        String granteeId = security ? identity.groupScimId : identity.userScimId;
        String granteeType = security ? "Group" : "User";
        SortedSet<String> scopes = scopeIds(grant);
        String mechanism = security ? "ADMINISTRATOR_TO_GROUP"
                : scopes.isEmpty() ? "ADMINISTRATOR_TO_USER" : "ADMINISTRATOR_TO_DELEGATED_USER";
        if (!hasText(roleId) || !hasText(appId) || !hasText(text(grant, "id"))
                || !roleId.equals(grant.path("entitlement").path("attributeValue").asText())
                || !"appRoles".equals(grant.path("entitlement").path("attributeName").asText())
                || !appId.equals(grant.path("app").path("value").asText())
                || granteeId == null || !granteeId.equals(grant.path("grantee").path("value").asText())
                || !granteeType.equals(grant.path("grantee").path("type").asText())
                || !mechanism.equals(text(grant, "grantMechanism"))
                || grant.path("deleteInProgress").asBoolean(false)
                || !grant.path("isFulfilled").asBoolean(false)
                || hasText(text(grant, "grantedAttributeValuesJson"))
                || (grant.hasNonNull("appEntitlementCollection"))) {
            throw failure("受管身份域授权的角色、受益人或状态不匹配，已停止更新。");
        }
        if (security && !scopes.isEmpty()) {
            throw failure("身份域安全管理授权包含未知范围，已停止更新。");
        }
        GrantMetadata result = desired(identity, roleKey, scopes, scopes.isEmpty());
        result.grantId = text(grant, "id");
        if (!configurationHash(result).equals(tags.get(CONFIG))) {
            throw failure("身份域授权范围已被其他操作修改，未覆盖该变更。");
        }
        return result;
    }

    private void auditUserRoles(User user, Result result) {
        // Core SCIM roles are editable profile data (e.g. Student/Faculty),
        // not administrator grants. Only the read-only appRoles are evidence.
        ExtensionUserUser extension = user.getUrnIetfParamsScimSchemasOracleIdcsExtensionUserUser();
        Set<String> observed = new HashSet<>();
        if (extension != null) {
            for (UserExtAppRoles role : list(extension.getAppRoles())) {
                if (!Boolean.FALSE.equals(role.getAdminRole())) {
                    if (!Boolean.TRUE.equals(role.getAdminRole())
                            || !result.allowedUserAdminRoleIds.contains(role.getValue())
                            || !expectedApp(result, role.getValue()).equals(role.getAppId())) {
                        throw failure("专用用户带有未经审计的身份域管理角色，已停止更新。");
                    }
                    observed.add(role.getValue());
                }
            }
        }
        if (!observed.equals(result.allowedUserAdminRoleIds)) {
            throw failure("身份域角色与受管授权尚未同步，请稍后重试。");
        }
        GrantMetadata manager = byRole(result.grants, USER_MANAGER);
        SortedSet<String> effectiveGroups = new TreeSet<>();
        if (extension != null) {
            for (UserExtIdcsAppRolesLimitedToGroups scope : list(extension.getIdcsAppRolesLimitedToGroups())) {
                if (!Objects.equals(result.userManagerRoleId, scope.getIdcsAppRoleId())
                        || !hasText(scope.getValue())) {
                    throw failure("专用用户带有未知的委派管理范围，已停止更新。");
                }
                effectiveGroups.add(scope.getValue());
            }
        }
        Set<String> expectedGroups = manager == null ? Collections.emptySet() : manager.targetGroupIds;
        if (!effectiveGroups.equals(expectedGroups)) {
            throw failure("用户实际委派范围与受管授权尚未同步，请稍后重试。");
        }
    }

    private void auditGroupRoles(Group group, Result result) {
        ExtensionGroupGroup extension = group.getUrnIetfParamsScimSchemasOracleIdcsExtensionGroupGroup();
        Set<String> observed = new HashSet<>();
        if (extension != null) {
            for (GroupExtAppRoles role : list(extension.getAppRoles())) {
                if (!Boolean.TRUE.equals(role.getAdminRole())
                        || !result.allowedGroupAdminRoleIds.contains(role.getValue())
                        || !expectedApp(result, role.getValue()).equals(role.getAppId())) {
                    throw failure("专用组带有其他身份域角色，已停止更新。");
                }
                observed.add(role.getValue());
            }
        }
        if (!observed.equals(result.allowedGroupAdminRoleIds)) {
            throw failure("专用组角色与受管授权尚未同步，请稍后重试。");
        }
    }

    private SortedSet<String> validateScope(ManagedDomainGrantClient client, Context context, Result identity,
                                            boolean allUsers, Collection<String> groupOcids) {
        SortedSet<String> result = new TreeSet<>();
        Collection<String> targets = groupOcids == null ? Collections.emptyList() : groupOcids;
        if (allUsers) {
            if (!targets.isEmpty()) {
                throw failure("全部用户范围不能同时包含指定用户组。");
            }
            return result;
        }
        if (targets.isEmpty() || targets.size() > 50) {
            throw failure("用户管理必须明确选择 1 至 50 个目标用户组，不能默认授权全部用户。");
        }
        for (String ocid : targets) {
            if (!validOcid(ocid, "group") || context.groupOcid.equals(ocid)) {
                throw failure("不能将专用 API 用户组作为用户管理目标。");
            }
            Group group = uniqueGroup(client, context, ocid);
            String normalized = group.getDisplayName() == null ? "" :
                    group.getDisplayName().toLowerCase(Locale.ROOT).replaceAll("[\\s_-]", "");
            if (normalized.contains("administrat") || normalized.equals("alldomainusers")
                    || normalized.equals("alltenantusers")
                    || list(group.getIdcsPreventedOperations()).contains(IdcsPreventedOperations.Delete)) {
                throw failure("不能选择管理员组、默认全员组或系统用户组作为受限管理目标。");
            }
            ExtensionGroupGroup extension = group.getUrnIetfParamsScimSchemasOracleIdcsExtensionGroupGroup();
            if (extension != null && (!list(extension.getAppRoles()).isEmpty()
                    || !list(extension.getGrants()).isEmpty())) {
                throw failure("目标用户组带有应用或管理角色授权，不能作为普通用户管理范围。");
            }
            for (User user : users(client, "groups.value eq " + quoted(group.getId()))) {
                assertDomain(context, user.getDomainOcid(), user.getTenancyOcid());
                if (context.userOcid.equals(user.getOcid()) || context.adminUserOcid.equals(user.getOcid())) {
                    throw failure("目标用户组包含原管理用户或专用 API 用户，无法限定管理范围。");
                }
                assertNoAdministrator(user);
            }
            result.add(group.getId());
        }
        return result;
    }

    private void assertNoAdministrator(User user) {
        ExtensionUserUser extension = user.getUrnIetfParamsScimSchemasOracleIdcsExtensionUserUser();
        if (extension != null) {
            for (UserExtAppRoles role : list(extension.getAppRoles())) {
                if (!Boolean.FALSE.equals(role.getAdminRole())) {
                    throw failure("目标用户组包含管理员或无法识别的角色，已停止授权。");
                }
            }
        }
    }

    private void createOwned(ManagedDomainGrantClient client, Context context, GrantMetadata desired) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("schemas", Arrays.asList(GRANT_SCHEMA, GRANT_EXTENSION));
        body.put("app", Collections.singletonMap("value", desired.appId));
        Map<String, Object> entitlement = new LinkedHashMap<>();
        entitlement.put("attributeName", "appRoles");
        entitlement.put("attributeValue", desired.roleId);
        body.put("entitlement", entitlement);
        boolean security = SECURITY_ADMIN.equals(desired.roleKey);
        Map<String, Object> grantee = new LinkedHashMap<>();
        grantee.put("type", security ? "Group" : "User");
        grantee.put("value", desired.granteeId);
        body.put("grantee", grantee);
        body.put("grantMechanism", security ? "ADMINISTRATOR_TO_GROUP"
                : desired.allUsers ? "ADMINISTRATOR_TO_USER" : "ADMINISTRATOR_TO_DELEGATED_USER");
        List<Map<String, String>> limitedTo = new ArrayList<>();
        for (String id : desired.targetGroupIds) {
            Map<String, String> target = new LinkedHashMap<>();
            target.put("value", id);
            target.put("type", "Group");
            limitedTo.add(target);
        }
        body.put(GRANT_EXTENSION, Collections.singletonMap("appRoleLimitedTo", limitedTo));
        List<Map<String, String>> tags = new ArrayList<>();
        tags.add(tag(MANAGER, VERSION));
        tags.add(tag(OWNER, context.owner));
        tags.add(tag(ROLE, desired.roleKey));
        tags.add(tag(CONFIG, configurationHash(desired)));
        body.put("tags", tags);
        try {
            client.request(Method.POST, "IDCSAppRoleGrants", null,
                    Collections.singletonMap("attributeSets", "all"), body, null, UUID.randomUUID().toString());
        } catch (BmcException e) {
            if (e.getStatusCode() != 409) {
                throw e;
            }
            // Do not adopt the conflicting grant: subsequent inspect must prove
            // both ownership and exact scope before reconciliation can succeed.
        }
    }

    private void deleteOwned(ManagedDomainGrantClient client, Context context, GrantMetadata expected) {
        ManagedDomainGrantClient.RawResponse response;
        try {
            response = client.request(Method.GET, "IDCSAppRoleGrants", expected.grantId,
                    Collections.singletonMap("attributeSets", "all"), null, null, null);
        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                return; // A subsequent complete audit confirms absence.
            }
            throw e;
        }
        Result identity = new Result();
        if (SECURITY_ADMIN.equals(expected.roleKey)) {
            identity.securityRoleId = expected.roleId;
            identity.securityAppId = expected.appId;
            identity.groupScimId = expected.granteeId;
        } else {
            identity.userManagerRoleId = expected.roleId;
            identity.userManagerAppId = expected.appId;
            identity.userScimId = expected.granteeId;
        }
        GrantMetadata current = ownedGrant(context, identity, response.body);
        if (!sameConfiguration(expected, current)) {
            throw failure("受管授权在更新过程中发生变更，未撤回该授权。");
        }
        String etag = response.header("etag");
        if (!hasText(etag)) {
            etag = response.body.path("meta").path("version").asText(null);
        }
        if (!hasText(etag)) {
            throw failure("身份域未返回授权版本，无法安全撤回权限。");
        }
        client.request(Method.DELETE, "IDCSAppRoleGrants", expected.grantId,
                null, null, etag, null);
    }

    private List<JsonNode> listGrants(ManagedDomainGrantClient client, String resource, String filter) {
        List<JsonNode> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        int start = 1;
        while (true) {
            Map<String, Object> query = new LinkedHashMap<>();
            query.put("filter", filter);
            query.put("startIndex", start);
            query.put("count", PAGE_SIZE);
            query.put("attributeSets", "all");
            JsonNode body = client.request(Method.GET, resource, null, query, null, null, null).body;
            if (body == null || !body.path("Resources").isArray() || !body.path("totalResults").isIntegralNumber()) {
                throw failure("身份域授权查询返回不完整，已停止更新。");
            }
            JsonNode rows = body.path("Resources");
            for (JsonNode grant : rows) {
                if (!hasText(text(grant, "id")) || !seen.add(text(grant, "id"))) {
                    throw failure("身份域授权分页结果重复，已停止更新。");
                }
                result.add(grant);
            }
            if (!more(body.path("totalResults").intValue(),
                    body.path("startIndex").isIntegralNumber() ? body.path("startIndex").intValue() : null,
                    start, rows.size())) {
                break;
            }
            start += rows.size();
        }
        return result;
    }

    private User uniqueUser(ManagedDomainGrantClient client, Context context, String ocid) {
        List<User> matches = users(client, "ocid eq " + quoted(ocid));
        if (matches.size() != 1 || !ocid.equals(matches.get(0).getOcid())) {
            throw failure("专用用户尚未唯一同步到身份域，请稍后重试。");
        }
        User result = matches.get(0);
        assertDomain(context, result.getDomainOcid(), result.getTenancyOcid());
        if (!hasText(result.getId())) {
            throw failure("身份域用户标识缺失。");
        }
        return result;
    }

    private List<User> users(ManagedDomainGrantClient client, String filter) {
        List<User> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        int start = 1;
        while (true) {
            Users page = client.listUsers(ListUsersRequest.builder().filter(filter)
                    .startIndex(start).count(PAGE_SIZE)
                    .attributes("id,ocid,domainOcid,tenancyOcid,groups," + USER_EXTENSION + ":appRoles,"
                            + USER_EXTENSION + ":grants," + USER_EXTENSION + ":idcsAppRolesLimitedToGroups")
                    .build()).getUsers();
            if (page == null) {
                throw failure("无法完整读取身份域用户。");
            }
            List<User> rows = list(page.getResources());
            for (User user : rows) {
                if (!hasText(user.getId()) || !seen.add(user.getId())) {
                    throw failure("身份域用户分页结果重复。");
                }
                result.add(user);
            }
            if (!more(page.getTotalResults(), page.getStartIndex(), start, rows.size())) {
                break;
            }
            start += rows.size();
        }
        return result;
    }

    private Group uniqueGroup(ManagedDomainGrantClient client, Context context, String ocid) {
        Groups result = client.listGroups(ListGroupsRequest.builder().filter("ocid eq " + quoted(ocid))
                .startIndex(1).count(2)
                .attributes("id,ocid,displayName,domainOcid,tenancyOcid,idcsPreventedOperations," + GROUP_EXTENSION)
                .build()).getGroups();
        if (result == null || result.getTotalResults() == null || result.getTotalResults() != 1
                || list(result.getResources()).size() != 1) {
            throw failure("用户组尚未唯一同步到身份域，或不属于当前默认身份域。");
        }
        Group group = result.getResources().get(0);
        if (!ocid.equals(group.getOcid()) || !hasText(group.getId())) {
            throw failure("身份域用户组标识不匹配。");
        }
        assertDomain(context, group.getDomainOcid(), group.getTenancyOcid());
        return group;
    }

    private Context context(SimpleAuthenticationDetailsProvider admin, DomainSummary domain,
                            String tenancyId, String userOcid, String groupOcid, String owner) {
        if (admin == null || !Objects.equals(tenancyId, admin.getTenantId())
                || Objects.equals(userOcid, admin.getUserId())
                || (userOcid != null && !validOcid(userOcid, "user"))
                || (groupOcid != null && !validOcid(groupOcid, "group"))
                || owner == null || !owner.matches("[a-f0-9]{64}")) {
            throw failure("受管身份域授权参数无效，未修改权限。");
        }
        if (domain == null) {
            return null;
        }
        if (!"DEFAULT".equalsIgnoreCase(String.valueOf(domain.getType())) || !hasText(domain.getId())) {
            throw failure("当前仅允许在已核验的默认身份域配置受管角色。");
        }
        String endpoint = hasText(domain.getHomeRegionUrl()) ? domain.getHomeRegionUrl() : domain.getUrl();
        try {
            URI uri = URI.create(endpoint);
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                    || uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null
                    || (hasText(uri.getPath()) && !"/".equals(uri.getPath()))) {
                throw failure("身份域地址无效，未发送管理凭证。");
            }
        } catch (RuntimeException e) {
            throw failure("身份域地址无效，未发送管理凭证。");
        }
        Context context = new Context();
        context.domainId = domain.getId();
        context.endpoint = endpoint.replaceAll("/+$", "");
        context.tenancyId = tenancyId;
        context.userOcid = userOcid;
        context.groupOcid = groupOcid;
        context.adminUserOcid = admin.getUserId();
        context.owner = owner;
        return context;
    }

    private static GrantMetadata desired(Result identity, String key, Collection<String> scopes, boolean allUsers) {
        GrantMetadata result = new GrantMetadata();
        result.roleKey = key;
        boolean security = SECURITY_ADMIN.equals(key);
        result.roleId = security ? identity.securityRoleId : identity.userManagerRoleId;
        result.appId = security ? identity.securityAppId : identity.userManagerAppId;
        result.granteeId = security ? identity.groupScimId : identity.userScimId;
        result.targetGroupIds = new TreeSet<>(scopes);
        result.allUsers = allUsers;
        return result;
    }

    private static SortedSet<String> scopeIds(JsonNode grant) {
        SortedSet<String> result = new TreeSet<>();
        JsonNode scopes = grant.path(GRANT_EXTENSION).path("appRoleLimitedTo");
        if (scopes.isMissingNode() || scopes.isNull()) {
            return result;
        }
        if (!scopes.isArray()) {
            throw failure("身份域角色范围格式无法识别。");
        }
        for (JsonNode scope : scopes) {
            String id = text(scope, "value");
            if (!hasText(id) || (scope.hasNonNull("type") && !"Group".equals(text(scope, "type")))
                    || !result.add(id)) {
                throw failure("身份域角色目标组范围无法识别。");
            }
        }
        return result;
    }

    private static Map<String, String> tags(JsonNode grant) {
        Map<String, String> result = new HashMap<>();
        JsonNode tags = grant.path("tags");
        if (!tags.isArray()) {
            throw failure("身份域角色缺少受管归属标记，未修改该授权。");
        }
        for (JsonNode tag : tags) {
            String key = text(tag, "key");
            if (!hasText(key) || result.put(key, text(tag, "value")) != null) {
                throw failure("身份域授权归属标记存在冲突。");
            }
        }
        return result;
    }

    private static Map<String, String> tag(String key, String value) {
        Map<String, String> result = new LinkedHashMap<>();
        result.put("key", key);
        result.put("value", value);
        return result;
    }

    private static boolean more(Integer total, Integer returnedStart, int start, int count) {
        // Some SCIM collections use startIndex=0 for their empty representation.
        if (Integer.valueOf(0).equals(total) && count == 0 && start == 1
                && (returnedStart == null || returnedStart == 0 || returnedStart == 1)) {
            return false;
        }
        if (total == null || total < 0 || returnedStart == null || returnedStart != start
                || (count == 0 && start <= total) || start > 100000) {
            throw failure("身份域分页信息不完整，无法完成权限审计。");
        }
        return start - 1L + count < total;
    }

    private static void assertDomain(Context context, String domainId, String tenancyId) {
        if (!context.domainId.equals(domainId) || !context.tenancyId.equals(tenancyId)) {
            throw failure("身份域资源不属于当前租户和默认身份域，已停止更新。");
        }
    }

    private static String expectedApp(Result result, String roleId) {
        return Objects.equals(roleId, result.securityRoleId) ? result.securityAppId : result.userManagerAppId;
    }

    private static String configurationHash(GrantMetadata metadata) {
        try {
            String value = metadata.roleKey + "\n" + metadata.roleId + "\n" + metadata.appId
                    + "\n" + metadata.granteeId + "\n" + metadata.allUsers
                    + "\n" + String.join(",", metadata.targetGroupIds);
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder();
            for (byte b : bytes) {
                result.append(String.format("%02x", b & 0xff));
            }
            return result.toString();
        } catch (Exception e) {
            throw failure("无法生成身份域授权校验标记。");
        }
    }

    private static GrantMetadata byRole(List<GrantMetadata> rows, String key) {
        for (GrantMetadata metadata : rows) {
            if (key.equals(metadata.roleKey)) {
                return metadata;
            }
        }
        return null;
    }

    private static boolean sameConfiguration(GrantMetadata a, GrantMetadata b) {
        return b != null && configurationHash(a).equals(configurationHash(b));
    }

    private static <T> List<T> list(List<T> value) {
        return value == null ? Collections.emptyList() : value;
    }

    private static String quoted(String value) {
        if (!hasText(value) || value.indexOf('"') >= 0 || value.indexOf('\\') >= 0
                || value.chars().anyMatch(Character::isISOControl)) {
            throw failure("身份域筛选值无效。");
        }
        return "\"" + value + "\"";
    }

    private static String text(JsonNode node, String field) {
        return node == null ? null : node.path(field).asText(null);
    }

    private static boolean validOcid(String value, String kind) {
        return value != null && value.matches("ocid1\\." + kind + "\\.[A-Za-z0-9._-]+");
    }

    private static boolean hasText(String value) {
        return value != null && !value.trim().isEmpty();
    }

    private static IllegalArgumentException failure(String message) {
        return new DomainRoleException(message);
    }

    static Result safe(ManagedImportDiagnostics.Stage stage, Supplier<Result> operation) {
        try {
            return operation.get();
        } catch (DomainRoleException e) {
            ManagedImportDiagnostics.failed(stage, e);
            throw e;
        } catch (BmcException e) {
            ManagedImportDiagnostics.failed(stage, e);
            if (e.getStatusCode() == 409 || e.getStatusCode() == 412 || e.getStatusCode() == 429) {
                throw failure("身份域授权正在同步或被并发修改，请稍后以相同用户名重试。");
            }
            throw failure("无法完成身份域角色授权或审计，请检查源凭证的身份域管理权限后重试。");
        } catch (Exception e) {
            ManagedImportDiagnostics.failed(stage, e);
            throw failure("身份域角色配置未完成；受管资源保留供重试，不会改用源管理 API。");
        }
    }

    // Only this locally generated exception carries a safe business message across the provisioning boundary.
    static final class DomainRoleException extends IllegalArgumentException {
        DomainRoleException(String message) {
            super(message);
        }
    }

    private static final class Context {
        private String tenancyId;
        private String domainId;
        private String endpoint;
        private String userOcid;
        private String groupOcid;
        private String adminUserOcid;
        private String owner;
    }

    @Getter
    public static final class Result {
        private String domainId;
        private String domainUrl;
        private String userScimId;
        private String groupScimId;
        private String securityRoleId;
        private String userManagerRoleId;
        private String securityAppId;
        private String userManagerAppId;
        private final Map<String, String> managedGrantIds = new LinkedHashMap<>();
        private final Set<String> allowedUserAdminRoleIds = new LinkedHashSet<>();
        private final Set<String> allowedGroupAdminRoleIds = new LinkedHashSet<>();
        private final List<GrantMetadata> grants = new ArrayList<>();
    }

    @Getter
    public static final class GrantMetadata {
        private String roleKey;
        private String roleId;
        private String appId;
        private String granteeId;
        private String grantId;
        /** SCIM group IDs, not OCI group OCIDs. */
        private SortedSet<String> targetGroupIds;
        private boolean allUsers;
    }
}
