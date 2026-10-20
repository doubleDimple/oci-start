package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.ociserver.config.ProxyContext;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.*;
import com.oracle.bmc.identity.requests.*;
import com.oracle.bmc.identity.responses.*;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.ExtensionGroupGroup;
import com.oracle.bmc.identitydomains.model.ExtensionUserUser;
import com.oracle.bmc.identitydomains.model.GroupExtAppRoles;
import com.oracle.bmc.identitydomains.model.IdcsPreventedOperations;
import com.oracle.bmc.identitydomains.model.UserExtAppRoles;
import com.oracle.bmc.identitydomains.model.UserGroups;
import com.oracle.bmc.model.BmcException;
import lombok.Getter;
import lombok.Setter;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.Function;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Creates or reconciles a dedicated OCI API identity. The supplied administrative
 * provider is used only during this call and is never retained or written to disk.
 */
@Service
public class ManagedOciIdentityProvisioner {
    @Resource private ManagedDomainRoleService domainRoles;
    private static final String MANAGED_BY = "oci-start-managed-by";
    private static final String OWNER = "oci-start-identity";
    private static final String MANAGER_VERSION = "managed-v1";
    private static final String DOMAIN_USER_EXTENSION = "urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User";
    private static final String DOMAIN_GROUP_EXTENSION = "urn:ietf:params:scim:schemas:oracle:idcs:extension:group:Group";
    private static final Pattern USER_NAME = Pattern.compile("[a-zA-Z0-9][a-zA-Z0-9._@+\\-]{0,99}");
    private static final Pattern POLICY_SUBJECT = Pattern.compile(
            "(?is)^\\s*(allow|admit|endorse)\\s+(.+?)\\s+to\\s+.+$");
    private static final Pattern POLICY_DEFINITION = Pattern.compile(
            "(?is)^\\s*define\\s+(group|dynamic-group|tenancy)\\s+([a-z0-9_-]+)\\s+as\\s+(ocid1\\.[a-z0-9._-]+)\\s*$");
    private static final Object[] LOCKS = new Object[64];

    static {
        for (int i = 0; i < LOCKS.length; i++) {
            LOCKS[i] = new Object();
        }
    }

    /**
     * The policy factory receives the dedicated group's OCID, never a user-provided
     * policy fragment. ExistingIdentity.fingerprint may only be supplied after the
     * caller has verified the corresponding local private key.
     */
    public Result provision(SimpleAuthenticationDetailsProvider adminProvider,
                            String tenancyId, String adminUserId, String targetUserName,
                            Function<String, List<String>> statementsForGroupId,
                            ExistingIdentity existing, Set<String> selected, AccountPermissionScope scope) {
        if (adminProvider == null || !Objects.equals(tenancyId, adminProvider.getTenantId())
                || !Objects.equals(adminUserId, adminProvider.getUserId())
                || targetUserName == null || !USER_NAME.matcher(targetUserName).matches()
                || statementsForGroupId == null || selected == null || scope == null) {
            throw new ProvisioningException("管理凭证或专用用户名无效；用户名只能包含字母、数字、点、下划线、@、+ 和连字符。");
        }
        String owner = digest(tenancyId + "\n" + targetUserName.toLowerCase(Locale.ROOT));
        synchronized (LOCKS[(owner.hashCode() & Integer.MAX_VALUE) % LOCKS.length]) {
            try {
                return reconcile(adminProvider, tenancyId, adminUserId, targetUserName,
                        statementsForGroupId, existing, owner, selected, scope);
            } catch (ProvisioningException e) {
                throw e;
            } catch (BmcException e) {
                // SDK exception bodies and request data must not escape this boundary.
                if (e.getStatusCode() == 401 || e.getStatusCode() == 403 || e.getStatusCode() == 404) {
                    throw new ProvisioningException("无法完成 OCI 授权校验。请提供可读取租户全部策略、身份域及管理专用用户的管理凭证后重试。");
                }
                if (e.getStatusCode() == 409 || e.getStatusCode() == 412 || e.getStatusCode() == 429) {
                    throw new ProvisioningException("OCI 资源正在同步、被并发修改或请求过于频繁，请稍后以相同用户名重试。");
                }
                throw new ProvisioningException("OCI 专用身份配置未完成，请稍后以相同用户名重试；原用户及原 API 密钥未修改。");
            } catch (Exception e) {
                throw new ProvisioningException("专用身份配置未完成，请检查管理凭证和网络后重试；不会改用原管理凭证导入。");
            }
        }
    }

    private Result reconcile(SimpleAuthenticationDetailsProvider admin, String tenancyId,
                             String adminUserId, String username,
                             Function<String, List<String>> statementsForGroupId,
                             ExistingIdentity existing, String owner, Set<String> selected,
                             AccountPermissionScope scope) throws Exception {
        try (IdentityClient identity = IdentityClient.builder()
                .clientConfigurator(ProxyContext.get()).build(admin)) {
            Tenancy tenancy = identity.getTenancy(GetTenancyRequest.builder()
                    .tenancyId(tenancyId).build()).getTenancy();
            List<RegionSubscription> regions = identity.listRegionSubscriptions(
                    ListRegionSubscriptionsRequest.builder().tenancyId(tenancyId).build()).getItems();
            RegionSubscription home = null;
            for (RegionSubscription region : regions) {
                if (Boolean.TRUE.equals(region.getIsHomeRegion())) {
                    if (home != null) {
                        throw new ProvisioningException("无法唯一确定租户主区域，未修改云端身份。");
                    }
                    home = region;
                }
            }
            if (home == null || home.getRegionName() == null) {
                throw new ProvisioningException("无法查询租户主区域，未修改云端身份。");
            }
            identity.setRegion(home.getRegionName());
            String groupName = "oci-start-api-" + owner.substring(0, 32);
            String policyName = groupName + "-policy";
            Map<String, String> tags = new HashMap<>();
            tags.put(MANAGED_BY, MANAGER_VERSION);
            tags.put(OWNER, owner);

            User user = findUser(identity, tenancyId, username);
            if (user != null) {
                assertNotAdmin(user.getId(), adminUserId);
                assertOwned(user.getFreeformTags(), owner, "同名用户");
                assertExpected(existing == null ? null : existing.getUserId(), user.getId(), "专用用户");
                assertActive(user.getLifecycleState() == User.LifecycleState.Active, "专用用户");
                if (hasText(user.getIdentityProviderId())) {
                    throw new ProvisioningException("该用户名属于联合身份用户，不能作为本系统专用 API 用户接管。");
                }
            }
            Group group = findGroup(identity, tenancyId, groupName);
            if (group != null) {
                assertOwned(group.getFreeformTags(), owner, "专用组");
                assertExpected(existing == null ? null : existing.getGroupId(), group.getId(), "专用组");
                assertActive(group.getLifecycleState() == Group.LifecycleState.Active, "专用组");
            }
            Policy policy = findPolicy(identity, tenancyId, policyName);
            if (policy != null) {
                assertOwned(policy.getFreeformTags(), owner, "专用策略");
                assertExpected(existing == null ? null : existing.getPolicyId(), policy.getId(), "专用策略");
                assertActive(policy.getLifecycleState() == Policy.LifecycleState.Active, "专用策略");
            }

            DomainSummary domain = defaultDomain(identity, tenancyId);
            boolean securityManagement = selected.contains("DOMAIN_SECURITY_MANAGE");
            boolean userManagement = selected.contains("DOMAIN_USER_MANAGE");
            if (domain == null && (securityManagement || userManagement)) {
                throw new ProvisioningException("当前租户没有可用的默认身份域，不能配置身份域管理权限。");
            }
            assertExpected(existing == null ? null : existing.getDomainId(),
                    domain == null ? null : domain.getId(), "身份域");
            if (domain == null && hasText(tenancy.getUpiIdcsCompatibilityLayerEndpoint())) {
                throw new ProvisioningException("租户存在身份域兼容端点，但无法读取默认身份域，不能跳过角色校验。");
            }
            Map<String, String> baselineGroups = baselineDomainGroups(admin, domain, tenancyId);
            assertMemberships(identity, tenancyId, user, group, baselineGroups);
            boolean existingMayLaunch = group != null && permitsLaunch(statementsForGroupId.apply(group.getId()));
            assertNoExternalPolicies(identity, tenancyId, user, group, groupName, policy, baselineGroups, existingMayLaunch);
            ManagedDomainRoleService.Result roleState = domain == null ? null : domainRoles.audit(
                    admin, domain, tenancyId, user == null ? null : user.getId(),
                    group == null ? null : group.getId(), owner);
            if (user != null || group != null) {
                assertDomainIdentity(admin, domain, tenancyId, user, group, baselineGroups, roleState);
            }
            validatePasswordResetTargets(identity, tenancyId, adminUserId, user, selected, scope);

            if (user == null) {
                try {
                    user = identity.createUser(CreateUserRequest.builder()
                            .createUserDetails(CreateUserDetails.builder().compartmentId(tenancyId)
                                    .name(username).description("OCI Start managed API identity")
                                    .freeformTags(tags).build())
                            .opcRetryToken(UUID.randomUUID().toString()).build()).getUser();
                } catch (BmcException e) {
                    if (e.getStatusCode() != 409) {
                        throw e;
                    }
                    user = findUser(identity, tenancyId, username);
                    if (user == null) {
                        throw e;
                    }
                }
                assertNotAdmin(user.getId(), adminUserId);
                assertOwned(user.getFreeformTags(), owner, "同名用户");
            }
            if (group == null) {
                try {
                    group = identity.createGroup(CreateGroupRequest.builder()
                            .createGroupDetails(CreateGroupDetails.builder().compartmentId(tenancyId)
                                    .name(groupName).description("OCI Start dedicated API identity group")
                                    .freeformTags(tags).build())
                            .opcRetryToken(UUID.randomUUID().toString()).build()).getGroup();
                } catch (BmcException e) {
                    if (e.getStatusCode() != 409) {
                        throw e;
                    }
                    group = findGroup(identity, tenancyId, groupName);
                    if (group == null) {
                        throw e;
                    }
                }
                assertOwned(group.getFreeformTags(), owner, "专用组");
            }
            assertMemberships(identity, tenancyId, user, group, baselineGroups);
            roleState = domain == null ? null : domainRoles.audit(admin, domain, tenancyId,
                    user.getId(), group.getId(), owner);
            assertDomainIdentity(admin, domain, tenancyId, user, group, baselineGroups, roleState);
            List<String> statements = new ArrayList<>(statementsForGroupId.apply(group.getId()));
            if (statements.isEmpty()) {
                throw new ProvisioningException("专用用户的权限策略不能为空。");
            }
            String expectedPrefix = "allow group id " + group.getId() + " to ";
            for (String statement : statements) {
                if (statement == null || !statement.toLowerCase(Locale.ROOT).startsWith(
                        expectedPrefix.toLowerCase(Locale.ROOT))) {
                    throw new ProvisioningException("权限策略包含专用组以外的授权，已停止配置。");
                }
            }
            // Launching an instance can inherit a dynamic group's resource-principal
            // privileges. Reject an unknown boundary instead of silently extending
            // the permissions selected for the API identity.
            assertNoExternalPolicies(identity, tenancyId, user, group, groupName, policy, baselineGroups,
                    permitsLaunch(statements));
            if (policy == null) {
                try {
                    policy = identity.createPolicy(CreatePolicyRequest.builder()
                            .createPolicyDetails(CreatePolicyDetails.builder().compartmentId(tenancyId)
                                    .name(policyName).description("OCI Start selected API permissions")
                                    .statements(statements).freeformTags(tags).build())
                            .opcRetryToken(UUID.randomUUID().toString()).build()).getPolicy();
                } catch (BmcException e) {
                    if (e.getStatusCode() != 409) {
                        throw e;
                    }
                    policy = findPolicy(identity, tenancyId, policyName);
                    if (policy == null) {
                        throw e;
                    }
                    assertOwned(policy.getFreeformTags(), owner, "专用策略");
                    policy = updatePolicy(identity, policy, owner, statements);
                }
            } else {
                policy = updatePolicy(identity, policy, owner, statements);
            }

            // Only the managed API identity is changed, never the source user.
            identity.updateUserCapabilities(UpdateUserCapabilitiesRequest.builder().userId(user.getId())
                    .updateUserCapabilitiesDetails(UpdateUserCapabilitiesDetails.builder()
                            .canUseApiKeys(true).canUseConsolePassword(false).canUseAuthTokens(false)
                            .canUseSmtpCredentials(false).canUseCustomerSecretKeys(false)
                            .canUseDBCredentials(false).canUseOAuth2ClientCredentials(false).build()).build());
            boolean member = false;
            for (UserGroupMembership membership : memberships(identity, tenancyId, user.getId(), null)) {
                if (Objects.equals(group.getId(), membership.getGroupId())) {
                    member = true;
                }
            }
            if (!member) {
                identity.addUserToGroup(AddUserToGroupRequest.builder()
                        .addUserToGroupDetails(AddUserToGroupDetails.builder()
                                .userId(user.getId()).groupId(group.getId()).build()).build());
            }
            assertMemberships(identity, tenancyId, user, group, baselineGroups);
            // Reconcile roles as well as tenancy policies. Unchecking a combination
            // revokes only the role grants owned by this dedicated identity.
            if (domain != null) {
                roleState = domainRoles.reconcile(admin, domain, tenancyId, user.getId(), group.getId(),
                        owner, securityManagement, userManagement, scope.isAllUsers(),
                        scope.getUserManagementGroupIds());
                assertDomainIdentity(admin, domain, tenancyId, user, group, baselineGroups, roleState);
            }

            List<ApiKey> keys = identity.listApiKeys(ListApiKeysRequest.builder()
                    .userId(user.getId()).build()).getItems();
            String fingerprint = null;
            if (existing != null && (!hasText(existing.getUserId())
                    || Objects.equals(existing.getUserId(), user.getId()))
                    && hasText(existing.getFingerprint())) {
                for (ApiKey key : keys) {
                    if (existing.getFingerprint().equalsIgnoreCase(key.getFingerprint())
                            && key.getLifecycleState() == ApiKey.LifecycleState.Active) {
                        fingerprint = key.getFingerprint();
                    }
                }
            }
            byte[] privateKeyPem = null;
            if (fingerprint == null) {
                if (keys.size() >= 3) {
                    throw new ProvisioningException("专用用户已有 3 把 API 密钥，且本地没有匹配的私钥。请在 OCI 中自行清理不再使用的密钥后重试。");
                }
                KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
                generator.initialize(2048);
                KeyPair keyPair = generator.generateKeyPair();
                String publicPem = pem("PUBLIC KEY", keyPair.getPublic().getEncoded());
                ApiKey uploaded = identity.uploadApiKey(UploadApiKeyRequest.builder().userId(user.getId())
                        .createApiKeyDetails(CreateApiKeyDetails.builder().key(publicPem).build())
                        .opcRetryToken(UUID.randomUUID().toString()).build()).getApiKey();
                fingerprint = uploaded.getFingerprint();
                privateKeyPem = pem("PRIVATE KEY", keyPair.getPrivate().getEncoded())
                        .getBytes(StandardCharsets.US_ASCII);
            }
            Result result = new Result();
            result.setTargetUserId(user.getId());
            result.setGroupId(group.getId());
            result.setPolicyId(policy.getId());
            result.setFingerprint(fingerprint);
            result.setPrivateKeyPem(privateKeyPem);
            result.setHomeRegion(home.getRegionName());
            result.setTenancyName(tenancy.getName());
            result.setTenancyDescription(tenancy.getDescription());
            result.setRegions(Collections.unmodifiableList(new ArrayList<>(regions)));
            result.setDomainId(domain == null ? null : domain.getId());
            result.setDomainUrl(domain == null ? null : domainEndpoint(domain));
            result.setDomainGrantsJson(roleState == null ? "[]" : com.alibaba.fastjson2.JSON.toJSONString(roleState.getGrants()));
            return result;
        }
    }

    private void validatePasswordResetTargets(IdentityClient identity, String tenancyId,
            String adminUserId, User managedUser, Set<String> selected, AccountPermissionScope scope) {
        if (!selected.contains("USER_PASSWORD_RESET") || scope.isAllUsers()) return;
        for (String targetId : scope.getPasswordResetUserIds()) {
            if (targetId.equals(adminUserId) || (managedUser != null && targetId.equals(managedUser.getId()))) {
                throw new ProvisioningException("限定范围的密码重置不能包含原管理 API 用户或专用 API 用户。");
            }
            User target = identity.getUser(GetUserRequest.builder().userId(targetId).build()).getUser();
            if (target == null || !targetId.equals(target.getId()) || !tenancyId.equals(target.getCompartmentId())
                    || target.getLifecycleState() != User.LifecycleState.Active) {
                throw new ProvisioningException("密码重置范围包含不属于当前租户或不可用的用户。");
            }
        }
    }

    private Policy updatePolicy(IdentityClient identity, Policy policy, String owner, List<String> statements) {
        GetPolicyResponse current = identity.getPolicy(GetPolicyRequest.builder().policyId(policy.getId()).build());
        assertOwned(current.getPolicy().getFreeformTags(), owner, "专用策略");
        if (statements.equals(current.getPolicy().getStatements())) {
            return current.getPolicy();
        }
        return identity.updatePolicy(UpdatePolicyRequest.builder().policyId(policy.getId())
                .ifMatch(current.getEtag())
                .updatePolicyDetails(UpdatePolicyDetails.builder().statements(statements).build())
                .build()).getPolicy();
    }

    private User findUser(IdentityClient client, String tenancyId, String username) {
        User match = null;
        String page = null;
        do {
            ListUsersResponse response = client.listUsers(ListUsersRequest.builder()
                    .compartmentId(tenancyId).page(page).build());
            for (User user : response.getItems()) {
                if (username.equalsIgnoreCase(user.getName())) {
                    if (match != null) {
                        throw new ProvisioningException("用户名对应多个云端身份，不能自动选择。");
                    }
                    match = user;
                }
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        return match;
    }

    private Group findGroup(IdentityClient client, String tenancyId, String name) {
        Group match = null;
        String page = null;
        do {
            ListGroupsResponse response = client.listGroups(ListGroupsRequest.builder()
                    .compartmentId(tenancyId).page(page).build());
            for (Group group : response.getItems()) {
                if (name.equalsIgnoreCase(group.getName())) {
                    if (match != null) {
                        throw new ProvisioningException("专用组名称不唯一，不能自动选择。");
                    }
                    match = group;
                }
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        return match;
    }

    private Policy findPolicy(IdentityClient client, String tenancyId, String name) {
        Policy match = null;
        for (Policy policy : policies(client, tenancyId)) {
            if (name.equalsIgnoreCase(policy.getName())) {
                if (match != null) {
                    throw new ProvisioningException("专用策略名称不唯一，不能自动选择。");
                }
                match = policy;
            }
        }
        return match;
    }

    private List<Policy> policies(IdentityClient client, String compartmentId) {
        List<Policy> result = new ArrayList<>();
        String page = null;
        do {
            ListPoliciesResponse response = client.listPolicies(ListPoliciesRequest.builder()
                    .compartmentId(compartmentId).page(page).build());
            result.addAll(response.getItems());
            page = response.getOpcNextPage();
        } while (hasText(page));
        return result;
    }

    private List<UserGroupMembership> memberships(IdentityClient client, String tenancyId,
                                                   String userId, String groupId) {
        List<UserGroupMembership> result = new ArrayList<>();
        String page = null;
        do {
            ListUserGroupMembershipsResponse response = client.listUserGroupMemberships(
                    ListUserGroupMembershipsRequest.builder().compartmentId(tenancyId)
                            .userId(userId).groupId(groupId).page(page).build());
            for (UserGroupMembership membership : response.getItems()) {
                if (membership.getLifecycleState() != UserGroupMembership.LifecycleState.Deleted) {
                    result.add(membership);
                }
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        return result;
    }

    private void assertMemberships(IdentityClient client, String tenancyId, User user, Group group,
                                   Map<String, String> baselineGroups) {
        if (user != null) {
            for (UserGroupMembership member : memberships(client, tenancyId, user.getId(), null)) {
                if ((group == null || !group.getId().equals(member.getGroupId()))
                        && !baselineGroups.containsKey(member.getGroupId())) {
                    throw new ProvisioningException("专用用户还属于其他用户组，无法保证所选权限边界；请先在 OCI 中处理额外授权。");
                }
            }
        }
        if (group != null) {
            for (UserGroupMembership member : memberships(client, tenancyId, null, group.getId())) {
                if (user == null || !user.getId().equals(member.getUserId())) {
                    throw new ProvisioningException("专用组包含其他用户，已停止更新，避免影响其他账号。");
                }
            }
        }
    }

    private void assertNoExternalPolicies(IdentityClient client, String tenancyId, User user,
                                          Group group, String groupName, Policy managedPolicy,
                                          Map<String, String> baselineGroups, boolean mayLaunch) {
        List<String> compartments = new ArrayList<>();
        compartments.add(tenancyId);
        String page = null;
        do {
            ListCompartmentsResponse response = client.listCompartments(ListCompartmentsRequest.builder()
                    .compartmentId(tenancyId).compartmentIdInSubtree(true)
                    .accessLevel(ListCompartmentsRequest.AccessLevel.Any)
                    .lifecycleState(Compartment.LifecycleState.Active).page(page).build());
            for (Compartment compartment : response.getItems()) {
                compartments.add(compartment.getId());
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        for (String compartmentId : compartments) {
            for (Policy policy : policies(client, compartmentId)) {
                if (managedPolicy != null && managedPolicy.getId().equals(policy.getId())) {
                    continue;
                }
                if (policy.getLifecycleState() == Policy.LifecycleState.Deleted) {
                    continue;
                }
                Set<String> aliases = new HashSet<>();
                for (String statement : policy.getStatements()) {
                    if (!statement.trim().toLowerCase(Locale.ROOT).startsWith("define ")) {
                        continue;
                    }
                    Matcher definition = POLICY_DEFINITION.matcher(statement);
                    if (!definition.matches()) {
                        throw new ProvisioningException("存在无法解析的 OCI 策略别名，不能确认专用用户权限边界。");
                    }
                    String definedId = definition.group(3);
                    if ((group != null && group.getId().equalsIgnoreCase(definedId))
                            || baselineGroups.containsKey(definedId)
                            || (user != null && user.getId().equalsIgnoreCase(definedId))
                            || (mayLaunch && definedId.toLowerCase(Locale.ROOT).startsWith("ocid1.dynamicgroup."))) {
                        aliases.add(definition.group(2).toLowerCase(Locale.ROOT));
                    }
                }
                for (String statement : policy.getStatements()) {
                    String normalized = statement.trim().toLowerCase(Locale.ROOT);
                    if (normalized.startsWith("define ") || normalized.startsWith("deny ")) {
                        continue;
                    }
                    Matcher matcher = POLICY_SUBJECT.matcher(statement);
                    if (!matcher.matches()) {
                        throw new ProvisioningException("存在无法判断授权对象的 OCI 策略，不能确认专用用户的权限边界。");
                    }
                    String subject = matcher.group(2).toLowerCase(Locale.ROOT);
                    boolean additionalGrant = subject.contains("any-user") || subject.contains("any-group")
                            || (mayLaunch && subject.contains("dynamic-group"))
                            || subject.contains(groupName.toLowerCase(Locale.ROOT))
                            || (group != null && subject.contains(group.getId().toLowerCase(Locale.ROOT)))
                            || (user != null && subject.contains(user.getId().toLowerCase(Locale.ROOT)))
                            || (user != null && subject.startsWith("user ")
                            && subject.contains(user.getName().toLowerCase(Locale.ROOT)));
                    for (String alias : aliases) {
                        additionalGrant |= subject.contains(alias);
                    }
                    for (Map.Entry<String, String> baseline : baselineGroups.entrySet()) {
                        additionalGrant |= subject.contains(baseline.getKey().toLowerCase(Locale.ROOT))
                                || subject.contains(baseline.getValue().toLowerCase(Locale.ROOT));
                    }
                    if (additionalGrant) {
                        throw new ProvisioningException("检测到专用策略以外的潜在授权（策略：" + policy.getName()
                                + "），无法保证只具有勾选权限；请先在 OCI 中收紧该授权。");
                    }
                }
            }
        }
    }

    private boolean permitsLaunch(List<String> statements) {
        for (String statement : statements) {
            if (statement != null && statement.toUpperCase(Locale.ROOT).contains("'INSTANCE_CREATE'")) {
                return true;
            }
        }
        return false;
    }

    /**
     * IAM automatically places every domain user in its immutable all-users
     * group. It is a permitted membership only after its roles are checked; its
     * name and OCID are also included when checking every tenancy policy.
     */
    private Map<String, String> baselineDomainGroups(SimpleAuthenticationDetailsProvider admin,
                                                     DomainSummary domain, String tenancyId) throws Exception {
        Map<String, String> result = new HashMap<>();
        if (domain == null) {
            return result;
        }
        try (IdentityDomainsClient client = IdentityDomainsClient.builder()
                .clientConfigurator(ProxyContext.get()).build(admin)) {
            client.setEndpoint(domainEndpoint(domain));
            String page = null;
            do {
                com.oracle.bmc.identitydomains.responses.ListGroupsResponse response = client.listGroups(
                        com.oracle.bmc.identitydomains.requests.ListGroupsRequest.builder()
                                .filter("displayName eq \"All-Domain-Users\" or displayName eq \"All-Tenant-Users\""
                                        + " or displayName eq \"All Domain Users\" or displayName eq \"All Tenant Users\"")
                                .attributes("id,ocid,displayName,tenancyOcid,domainOcid,idcsPreventedOperations,"
                                        + DOMAIN_GROUP_EXTENSION + ":appRoles")
                                .page(page).build());
                if (response.getGroups() == null || response.getGroups().getResources() == null) {
                    throw new ProvisioningException("无法校验默认身份域的全体用户组。");
                }
                for (com.oracle.bmc.identitydomains.model.Group group : response.getGroups().getResources()) {
                    if (!tenancyId.equals(group.getTenancyOcid()) || !domain.getId().equals(group.getDomainOcid())
                            || !hasText(group.getOcid()) || group.getIdcsPreventedOperations() == null
                            || !group.getIdcsPreventedOperations().contains(IdcsPreventedOperations.Delete)) {
                        throw new ProvisioningException("无法确认默认全体用户组的系统身份，已停止配置。");
                    }
                    ExtensionGroupGroup extension = group.getUrnIetfParamsScimSchemasOracleIdcsExtensionGroupGroup();
                    if (extension != null && extension.getAppRoles() != null) {
                        for (GroupExtAppRoles role : extension.getAppRoles()) {
                            if (!Boolean.FALSE.equals(role.getAdminRole())) {
                                throw new ProvisioningException("默认全体用户组带有管理员角色或无法识别的角色，无法隔离专用用户权限。");
                            }
                        }
                    }
                    result.put(group.getOcid(), group.getDisplayName());
                }
                page = response.getOpcNextPage();
            } while (hasText(page));
        }
        if (result.isEmpty()) {
            throw new ProvisioningException("无法找到并验证默认身份域的全体用户组，已停止配置。");
        }
        return result;
    }

    private DomainSummary defaultDomain(IdentityClient client, String tenancyId) {
        DomainSummary found = null;
        boolean hasDomains = false;
        String page = null;
        do {
            ListDomainsResponse response = client.listDomains(ListDomainsRequest.builder()
                    .compartmentId(tenancyId).page(page).build());
            for (DomainSummary domain : response.getItems()) {
                hasDomains = true;
                if ("DEFAULT".equalsIgnoreCase(String.valueOf(domain.getType()))) {
                    if (found != null) {
                        throw new ProvisioningException("无法唯一确定默认身份域。");
                    }
                    found = domain;
                }
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        if (hasDomains && found == null) {
            throw new ProvisioningException("只能读取部分身份域，无法确认默认域及管理员角色。");
        }
        return found;
    }

    /**
     * The IAM compatibility APIs create local users in the default domain.
     * Domain roles must be checked separately because tenancy policies do not
     * remove privileges granted by an identity-domain administrator role.
     */
    private void assertDomainIdentity(SimpleAuthenticationDetailsProvider admin, DomainSummary domain,
                                      String tenancyId, User user, Group group,
                                      Map<String, String> baselineGroups,
                                      ManagedDomainRoleService.Result roleState) throws Exception {
        if (domain == null) {
            return; // A successful, empty domain listing denotes classic IAM.
        }
        Set<String> allowedUserRoles = roleState == null ? Collections.emptySet() : roleState.getAllowedUserAdminRoleIds();
        Set<String> allowedGroupRoles = roleState == null ? Collections.emptySet() : roleState.getAllowedGroupAdminRoleIds();
        Collection<String> allowedGrantIds = roleState == null ? Collections.emptySet() : roleState.getManagedGrantIds().values();
        try (IdentityDomainsClient domains = IdentityDomainsClient.builder()
                .clientConfigurator(ProxyContext.get()).build(admin)) {
            domains.setEndpoint(domainEndpoint(domain));
            if (user != null) {
                com.oracle.bmc.identitydomains.model.User domainUser = domainUser(domains, user.getId());
                if (domainUser == null || !tenancyId.equals(domainUser.getTenancyOcid())
                        || !domain.getId().equals(domainUser.getDomainOcid())) {
                    throw new ProvisioningException("专用用户尚未同步到默认身份域，或身份域不匹配，请稍后重试。");
                }
                // SCIM User.roles contains profile labels, not OCI administrator grants.
                // Only verified application-role IDs from the grant audit may be allowed.
                ExtensionUserUser extension = domainUser.getUrnIetfParamsScimSchemasOracleIdcsExtensionUserUser();
                if (extension != null && extension.getAppRoles() != null) {
                    for (UserExtAppRoles role : extension.getAppRoles()) {
                        if (!Boolean.FALSE.equals(role.getAdminRole()) && !allowedUserRoles.contains(role.getValue())) {
                            throw new ProvisioningException("专用用户带有管理员角色或无法识别的角色，已停止更新。");
                        }
                    }
                }
                if (domainUser.getGroups() != null) {
                    for (UserGroups membership : domainUser.getGroups()) {
                        if ((group == null || !group.getId().equals(membership.getOcid()))
                                && !baselineGroups.containsKey(membership.getOcid())) {
                            throw new ProvisioningException("专用用户在身份域中还属于其他用户组，已停止更新。");
                        }
                    }
                }
            }
            if (group != null) {
                com.oracle.bmc.identitydomains.model.Group domainGroup = domainGroup(domains, group.getId());
                if (domainGroup == null || !tenancyId.equals(domainGroup.getTenancyOcid())
                        || !domain.getId().equals(domainGroup.getDomainOcid())) {
                    throw new ProvisioningException("专用组尚未同步到默认身份域，或身份域不匹配，请稍后重试。");
                }
                ExtensionGroupGroup extension = domainGroup.getUrnIetfParamsScimSchemasOracleIdcsExtensionGroupGroup();
                if (extension != null) {
                    if (extension.getAppRoles() != null) {
                        for (GroupExtAppRoles role : extension.getAppRoles()) {
                            if (!allowedGroupRoles.contains(role.getValue())) {
                                throw new ProvisioningException("专用组带有未勾选或非本系统管理的身份域角色，已停止更新。");
                            }
                        }
                    }
                    if (extension.getGrants() != null) {
                        for (com.oracle.bmc.identitydomains.model.GroupExtGrants grant : extension.getGrants()) {
                            if (!allowedGrantIds.contains(grant.getValue())) {
                                throw new ProvisioningException("专用组带有非本系统管理的应用授权，已停止更新。");
                            }
                        }
                    }
                }
            }
        }
    }

    private String domainEndpoint(DomainSummary domain) {
        String endpoint = hasText(domain.getHomeRegionUrl()) ? domain.getHomeRegionUrl() : domain.getUrl();
        if (!hasText(endpoint)) {
            throw new ProvisioningException("默认身份域缺少可查询的地址，无法验证管理员角色。");
        }
        return endpoint;
    }

    private com.oracle.bmc.identitydomains.model.User domainUser(IdentityDomainsClient client, String ocid) {
        com.oracle.bmc.identitydomains.model.User found = null;
        String page = null;
        do {
            com.oracle.bmc.identitydomains.responses.ListUsersResponse response = client.listUsers(
                    com.oracle.bmc.identitydomains.requests.ListUsersRequest.builder()
                            .filter("ocid eq \"" + ocid + "\"")
                            .attributes("id,ocid,userName,tenancyOcid,domainOcid,groups,roles,"
                                    + DOMAIN_USER_EXTENSION + ":appRoles")
                            .page(page).build());
            if (response.getUsers() == null || response.getUsers().getResources() == null) {
                throw new ProvisioningException("身份域未返回可校验的用户信息。");
            }
            for (com.oracle.bmc.identitydomains.model.User value : response.getUsers().getResources()) {
                if (!ocid.equals(value.getOcid()) || found != null) {
                    throw new ProvisioningException("身份域用户查询结果不唯一，已停止更新。");
                }
                found = value;
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        return found;
    }

    private com.oracle.bmc.identitydomains.model.Group domainGroup(IdentityDomainsClient client, String ocid) {
        com.oracle.bmc.identitydomains.model.Group found = null;
        String page = null;
        do {
            com.oracle.bmc.identitydomains.responses.ListGroupsResponse response = client.listGroups(
                    com.oracle.bmc.identitydomains.requests.ListGroupsRequest.builder()
                            .filter("ocid eq \"" + ocid + "\"")
                            .attributes("id,ocid,tenancyOcid,domainOcid,"
                                    + DOMAIN_GROUP_EXTENSION + ":appRoles," + DOMAIN_GROUP_EXTENSION + ":grants")
                            .page(page).build());
            if (response.getGroups() == null || response.getGroups().getResources() == null) {
                throw new ProvisioningException("身份域未返回可校验的用户组信息。");
            }
            for (com.oracle.bmc.identitydomains.model.Group value : response.getGroups().getResources()) {
                if (!ocid.equals(value.getOcid()) || found != null) {
                    throw new ProvisioningException("身份域用户组查询结果不唯一，已停止更新。");
                }
                found = value;
            }
            page = response.getOpcNextPage();
        } while (hasText(page));
        return found;
    }

    private void assertOwned(Map<String, String> tags, String owner, String resource) {
        if (tags == null || !MANAGER_VERSION.equals(tags.get(MANAGED_BY)) || !owner.equals(tags.get(OWNER))) {
            throw new ProvisioningException(resource + "不是本系统创建的专用身份资源，不能自动接管，请使用其他用户名。");
        }
    }

    private void assertExpected(String expected, String actual, String resource) {
        if (hasText(expected) && !expected.equals(actual)) {
            throw new ProvisioningException(resource + "的 OCID 与已保存记录不同，不能按同名资源覆盖。");
        }
    }

    private void assertNotAdmin(String userId, String adminUserId) {
        if (Objects.equals(userId, adminUserId)) {
            throw new ProvisioningException("专用用户名对应原管理 API 用户，禁止修改原用户，请填写新的专用用户名。");
        }
    }

    private void assertActive(boolean active, String resource) {
        if (!active) {
            throw new ProvisioningException(resource + "尚未处于可用状态，请稍后重试。");
        }
    }

    private static boolean hasText(String value) {
        return value != null && !value.trim().isEmpty();
    }

    private static String digest(String value) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder();
            for (byte b : hash) {
                result.append(String.format(Locale.ROOT, "%02x", b & 0xff));
            }
            return result.toString();
        } catch (GeneralSecurityException e) {
            throw new ProvisioningException("无法生成专用身份标识。");
        }
    }

    private static String pem(String label, byte[] der) {
        return "-----BEGIN " + label + "-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(der)
                + "\n-----END " + label + "-----\n";
    }

    @Getter
    @Setter
    public static class ExistingIdentity {
        private String userId;
        private String groupId;
        private String policyId;
        private String fingerprint;
        private String domainId;

        public String getDomainId() { return domainId; }
        public void setDomainId(String domainId) { this.domainId = domainId; }
    }

    // Deliberately no generated toString: this internal result contains a private key.
    @Getter
    @Setter
    public static class Result {
        private String targetUserId;
        private String groupId;
        private String policyId;
        private String fingerprint;
        private byte[] privateKeyPem;
        private String homeRegion;
        private String tenancyName;
        private String tenancyDescription;
        private String domainId;
        private String domainUrl;
        private String domainGrantsJson;
        private List<RegionSubscription> regions;

        public String getDomainUrl() { return domainUrl; }
        public void setDomainUrl(String domainUrl) { this.domainUrl = domainUrl; }
        public String getDomainGrantsJson() { return domainGrantsJson; }
        public void setDomainGrantsJson(String domainGrantsJson) { this.domainGrantsJson = domainGrantsJson; }
    }

    public static class ProvisioningException extends IllegalArgumentException {
        public ProvisioningException(String safeMessage) {
            super(safeMessage);
        }
    }
}
