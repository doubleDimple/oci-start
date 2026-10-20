package com.doubledimple.ociserver.service.permissions;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Server-owned OCI capability catalog. Policy text is never accepted from a client.
 *
 * The permission AND operation conditions are intentional: OCI uses VOLUME_DELETE
 * for both DeleteVolume and DeleteBootVolume. Similarly, granting INSTANCE_CREATE
 * must not grant the other operations covered by "manage instances".
 *
 * Policy references:
 * https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/corepolicyreference.htm
 * https://docs.oracle.com/en-us/iaas/Content/Identity/policyreference/iampolicyreference.htm
 * https://docs.oracle.com/en-us/iaas/mysql-database/doc/api-operations.html
 */
public final class OciPermissionCatalog {
    public static final int VERSION = 1;

    private static final Pattern GROUP_OCID =
            Pattern.compile("ocid1\\.group\\.[A-Za-z0-9._-]+");
    private static final Map<String, Capability> CATALOG = new LinkedHashMap<>();

    static {
        add("BASIC_READ", "基础资源查询", "Resource inventory", "basic", true, true,
                "查询区域、区间、实例、镜像、网络及存储卷；不包含账号列表。")
                .permissions(null,
                        "TENANCY_INSPECT", "COMPARTMENT_INSPECT", "INSTANCE_INSPECT", "INSTANCE_READ",
                        "INSTANCE_IMAGE_INSPECT", "INSTANCE_IMAGE_READ",
                        "VNIC_READ", "VNIC_ATTACHMENT_READ", "VCN_READ", "SUBNET_READ",
                        "ROUTE_TABLE_READ", "SECURITY_LIST_READ", "DHCP_READ", "INTERNET_GATEWAY_READ",
                        "PRIVATE_IP_READ", "PUBLIC_IP_READ", "IPV6_READ", "NETWORK_SECURITY_GROUP_INSPECT",
                        "NETWORK_SECURITY_GROUP_READ", "NETWORK_SECURITY_GROUP_LIST_SECURITY_RULES",
                        "NETWORK_SECURITY_GROUP_LIST_MEMBERS", "VOLUME_INSPECT", "VOLUME_ATTACHMENT_INSPECT",
                        "VOLUME_BACKUP_INSPECT", "BOOT_VOLUME_BACKUP_INSPECT", "WORKREQUEST_INSPECT");
        add("INSTANCE_POWER", "实例开机、关机与重启", "Start, stop and restart instances", "compute", true, false, "")
                .permissions(ops("InstanceAction"), "INSTANCE_POWER_ACTIONS");
        add("INSTANCE_CREATE", "创建实例与抢机", "Create instances and capacity retry", "compute", true, false,
                "使用已有子网创建实例。自动新建网络、修改路由和安全规则需另选网络管理。")
                .permissions(ops("LaunchInstance", "GetWorkRequest", "ListWorkRequestErrors", "ListWorkRequestLogs"),
                        "INSTANCE_CREATE", "INSTANCE_IMAGE_READ", "VNIC_CREATE", "VNIC_ATTACH",
                        "SUBNET_ATTACH", "NETWORK_SECURITY_GROUP_UPDATE_MEMBERS",
                        "VNIC_ASSOCIATE_NETWORK_SECURITY_GROUP", "APP_CATALOG_LISTING_READ")
                .permissions(ops("CreateComputeCapacityReport"), "COMPUTE_CAPACITY_REPORT_CREATE");
        add("INSTANCE_DELETE", "删除实例", "Terminate instances", "compute", false, false,
                "允许终止实例。OCI 终止接口也可连带删除该实例的启动卷；云端无法按该参数进一步隔离。")
                .permissions(ops("TerminateInstance"), "INSTANCE_DELETE", "VNIC_DELETE", "SUBNET_DETACH",
                        "VOLUME_ATTACHMENT_DELETE", "VOLUME_WRITE", "INSTANCE_DETACH_VOLUME");
        add("INSTANCE_UPDATE", "修改实例配置", "Update instance configuration", "compute", false, false,
                "允许修改规格、名称和实例元数据。")
                .permissions(ops("UpdateInstance"), "INSTANCE_UPDATE");
        add("INSTANCE_REINSTALL", "重装与控制台连接", "Reinstall and console access", "compute", false, false,
                "允许建立实例控制台连接；需同时授权实例开关机。")
                .dependsOn("INSTANCE_POWER")
                .permissions(ops("CreateInstanceConsoleConnection", "DeleteInstanceConsoleConnection",
                                "GetInstanceConsoleConnection", "ListInstanceConsoleConnections"),
                        "INSTANCE_CONSOLE_CONNECTION_CREATE", "INSTANCE_CONSOLE_CONNECTION_DELETE",
                        "INSTANCE_CONSOLE_CONNECTION_READ", "INSTANCE_CONSOLE_CONNECTION_INSPECT",
                        "INSTANCE_READ", "INSTANCE_INSPECT");
        add("BOOT_VOLUME_DELETE", "独立删除启动卷", "Delete boot volumes directly", "storage", false, false,
                "控制 DeleteBootVolume；不限制终止实例接口连带删除启动卷的行为。")
                .permissions(ops("DeleteBootVolume"), "VOLUME_DELETE");
        add("BLOCK_VOLUME_DELETE", "删除块存储卷", "Delete block volumes", "storage", false, false, "")
                .permissions(ops("DeleteVolume"), "VOLUME_DELETE");
        add("VOLUME_MANAGE", "创建、调整、挂载及备份存储卷", "Create, update, attach and back up volumes", "storage", false, false,
                "包含创建卷备份；不包含删除启动卷、块存储卷或卷备份。")
                .permissions(ops("CreateVolume", "CreateBootVolume", "UpdateVolume", "UpdateBootVolume",
                                "AttachVolume", "DetachVolume", "AttachBootVolume", "DetachBootVolume"),
                        "VOLUME_CREATE", "VOLUME_UPDATE", "VOLUME_WRITE", "VOLUME_BACKUP_READ",
                        "BOOT_VOLUME_BACKUP_READ", "VOLUME_ATTACHMENT_CREATE", "VOLUME_ATTACHMENT_DELETE",
                        "VOLUME_ATTACHMENT_UPDATE", "INSTANCE_ATTACH_VOLUME", "INSTANCE_DETACH_VOLUME")
                .permissions(ops("CreateBootVolumeBackup", "CreateVolumeBackup"),
                        "BOOT_VOLUME_BACKUP_CREATE", "VOLUME_BACKUP_CREATE", "VOLUME_WRITE");

        add("NETWORK_MANAGE", "网络与安全规则管理", "Manage networking and security rules", "network", false, false,
                "允许网络初始化、网卡及公网 IP 管理、安全规则和路由修改，也包括网络资源删除。")
                // Keep each operation family small and independently reviewable.
                .permissions(ops("CreateVcn", "UpdateVcn", "DeleteVcn",
                                "AddVcnCidr", "ModifyVcnCidr", "RemoveVcnCidr"),
                        "VCN_CREATE", "VCN_UPDATE", "VCN_DELETE")
                .permissions(ops("CreateSubnet", "UpdateSubnet", "DeleteSubnet",
                                "CreateSecurityList", "UpdateSecurityList", "DeleteSecurityList",
                                "CreateDhcpOptions", "UpdateDhcpOptions", "DeleteDhcpOptions"),
                        "SUBNET_CREATE", "SUBNET_UPDATE", "SUBNET_DELETE", "VCN_ATTACH", "VCN_DETACH",
                        "ROUTE_TABLE_ATTACH", "ROUTE_TABLE_DETACH",
                        "SECURITY_LIST_CREATE", "SECURITY_LIST_UPDATE", "SECURITY_LIST_DELETE",
                        "SECURITY_LIST_ATTACH", "SECURITY_LIST_DETACH",
                        "DHCP_CREATE", "DHCP_UPDATE", "DHCP_DELETE", "DHCP_ATTACH", "DHCP_DETACH")
                .permissions(ops("CreateInternetGateway", "UpdateInternetGateway", "DeleteInternetGateway"),
                        "INTERNET_GATEWAY_CREATE", "INTERNET_GATEWAY_UPDATE", "INTERNET_GATEWAY_DELETE",
                        "VCN_ATTACH", "VCN_DETACH")
                .permissions(ops("CreateRouteTable", "UpdateRouteTable", "DeleteRouteTable"),
                        "ROUTE_TABLE_CREATE", "ROUTE_TABLE_UPDATE", "ROUTE_TABLE_DELETE",
                        "VCN_ATTACH", "VCN_DETACH", "INTERNET_GATEWAY_ATTACH", "INTERNET_GATEWAY_DETACH",
                        "PRIVATE_IP_ROUTE_TABLE_ATTACH", "PRIVATE_IP_ROUTE_TABLE_DETACH",
                        "DRG_ATTACH", "DRG_DETACH", "NAT_GATEWAY_ATTACH", "NAT_GATEWAY_DETACH",
                        "SERVICE_GATEWAY_ATTACH", "SERVICE_GATEWAY_DETACH",
                        "LOCAL_PEERING_GATEWAY_ATTACH", "LOCAL_PEERING_GATEWAY_DETACH")
                .permissions(ops("CreateNetworkSecurityGroup", "UpdateNetworkSecurityGroup", "DeleteNetworkSecurityGroup",
                                "AddNetworkSecurityGroupSecurityRules", "UpdateNetworkSecurityGroupSecurityRules",
                                "RemoveNetworkSecurityGroupSecurityRules"),
                        "NETWORK_SECURITY_GROUP_CREATE", "NETWORK_SECURITY_GROUP_UPDATE", "NETWORK_SECURITY_GROUP_DELETE",
                        "NETWORK_SECURITY_GROUP_UPDATE_SECURITY_RULES", "NETWORK_SECURITY_GROUP_INSPECT",
                        "VCN_ATTACH", "VCN_DETACH")
                .permissions(ops("AttachVnic", "DetachVnic", "UpdateVnic"),
                        "INSTANCE_ATTACH_SECONDARY_VNIC", "INSTANCE_DETACH_SECONDARY_VNIC",
                        "VNIC_CREATE", "VNIC_DELETE", "VNIC_ATTACH", "VNIC_DETACH",
                        "VNIC_UPDATE", "SUBNET_ATTACH", "SUBNET_DETACH",
                        "NETWORK_SECURITY_GROUP_UPDATE_MEMBERS", "VNIC_ASSOCIATE_NETWORK_SECURITY_GROUP")
                .permissions(ops("CreatePublicIp", "UpdatePublicIp", "DeletePublicIp",
                                "CreatePrivateIp", "UpdatePrivateIp", "DeletePrivateIp",
                                "CreateIpv6", "UpdateIpv6", "DeleteIpv6"),
                        "PUBLIC_IP_CREATE", "PUBLIC_IP_UPDATE", "PUBLIC_IP_DELETE",
                        "PUBLIC_IP_ASSIGN_PRIVATE_IP", "PUBLIC_IP_UNASSIGN_PRIVATE_IP",
                        "PRIVATE_IP_CREATE", "PRIVATE_IP_UPDATE", "PRIVATE_IP_DELETE",
                        "PRIVATE_IP_ASSIGN", "PRIVATE_IP_UNASSIGN",
                        "PRIVATE_IP_ASSIGN_PUBLIC_IP", "PRIVATE_IP_UNASSIGN_PUBLIC_IP",
                        "VNIC_ASSIGN", "VNIC_UNASSIGN", "SUBNET_ATTACH", "SUBNET_DETACH",
                        "IPV6_CREATE", "IPV6_UPDATE", "IPV6_DELETE")
                .permissions(ops("ListNetworkLoadBalancers", "GetNetworkLoadBalancer", "GetWorkRequest",
                                "ListWorkRequests", "ListWorkRequestErrors", "ListWorkRequestLogs",
                                "CreateNetworkLoadBalancer", "UpdateNetworkLoadBalancer", "DeleteNetworkLoadBalancer",
                                "CreateListener", "UpdateListener", "DeleteListener",
                                "CreateBackendSet", "UpdateBackendSet", "DeleteBackendSet",
                                "CreateBackend", "UpdateBackend", "DeleteBackend"),
                        "NETWORK_LOAD_BALANCER_INSPECT", "NETWORK_LOAD_BALANCER_READ",
                        "NETWORK_LOAD_BALANCER_CREATE", "NETWORK_LOAD_BALANCER_UPDATE", "NETWORK_LOAD_BALANCER_DELETE");
        add("REGION_SUBSCRIBE", "订阅区域", "Subscribe to regions", "network", false, false, "")
                .permissions(ops("CreateRegionSubscription"), "TENANCY_UPDATE");

        add("COST_READ", "账单与费用查询", "Cost and usage queries", "observability", true, false, "")
                // Oracle's Cost Analysis documentation uses the singular resource type.
                .readResource("usage-report");
        add("TRAFFIC_READ", "流量与监控查询", "Traffic and metric queries", "observability", true, false, "")
                .permissions(ops("ListMetrics", "SummarizeMetricsData"), "METRIC_INSPECT", "METRIC_READ");
        add("AUDIT_READ", "审计日志查询", "Read audit events", "observability", false, false, "")
                .permissions(ops("ListEvents"), "AUDIT_EVENT_READ");
        add("MYSQL_READ", "MySQL 查询", "Read MySQL systems", "database", false, false, "")
                .permissions(ops("ListDbSystems", "GetDbSystem", "ListShapes", "ListVersions",
                                "ListWorkRequests", "GetWorkRequest"),
                        "MYSQL_INSTANCE_INSPECT", "MYSQL_INSTANCE_READ");
        add("MYSQL_MANAGE", "MySQL 创建、修改及删除", "Manage MySQL systems", "database", false, false,
                "新建网络和公网负载均衡还需单独授权网络管理。")
                .dependsOn("MYSQL_READ")
                .permissions(ops("CreateDbSystem", "UpdateDbSystem", "DeleteDbSystem",
                                "StartDbSystem", "StopDbSystem", "RestartDbSystem"),
                        "MYSQL_INSTANCE_CREATE", "MYSQL_INSTANCE_UPDATE", "MYSQL_INSTANCE_DELETE",
                        "MYSQL_INSTANCE_START", "MYSQL_INSTANCE_STOP", "MYSQL_INSTANCE_USE",
                        "SUBNET_ATTACH", "SUBNET_READ", "SUBNET_DETACH", "PRIVATE_IP_UPDATE");
        add("USER_READ", "查询账号与用户组", "Read users and groups", "account", false, false, "")
                .permissions(ops("ListUsers", "GetUser", "ListGroups", "GetGroup",
                                "ListUserGroupMemberships", "GetUserGroupMembership"),
                        "USER_INSPECT", "GROUP_INSPECT");
        add("USER_CREATE", "创建普通用户", "Create unprivileged users", "account", false, false,
                "仅创建用户，不设置控制台密码、不加入用户组，也不授予管理权限。")
                .dependsOn("USER_READ")
                .permissions(ops("CreateUser"), "USER_CREATE");
        add("USER_DELETE", "删除用户", "Delete users", "account", false, false,
                "允许删除租户用户，请谨慎授权。")
                .dependsOn("USER_READ")
                .permissions(ops("DeleteUser"), "USER_DELETE");

        add("USER_PASSWORD_RESET", "重置指定用户密码", "Reset selected users' passwords", "account", false, false,
                "仅为明确指定的用户 OCID 授权密码重置；不会授权用户组或 API 密钥修改。")
                .dependsOn("USER_READ")
                .permissions(ops("CreateOrResetUIPassword"), "USER_UPDATE", "USER_UIPASS_RESET");
        add("DOMAIN_USER_MANAGE", "指定用户组内的账号管理", "Manage users in selected groups", "account", false, false,
                "授予身份域 User Manager 角色：在指定用户组范围内启用、禁用、编辑、删除用户及重置密码、认证因素和生成绕过码；这些角色能力不能单独拆分。")
                .dependsOn("USER_READ")
                .permissions(ops("ListDomains", "GetDomain"), "DOMAIN_INSPECT", "DOMAIN_READ");
        add("DOMAIN_SECURITY_MANAGE", "身份域安全设置与应用管理", "Manage identity-domain security and applications", "account", false, false,
                "授予 Security Administrator 角色，包含通知邮箱、MFA、社交登录、密码策略及身份提供者、应用和应用密钥等管理；不是四个独立的云端权限。")
                .dependsOn("USER_READ")
                .permissions(ops("ListDomains", "GetDomain"), "DOMAIN_INSPECT", "DOMAIN_READ");
    }

    private OciPermissionCatalog() {
    }

    public static List<Map<String, Object>> describe() {
        List<Map<String, Object>> result = new ArrayList<>();
        for (Capability capability : CATALOG.values()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("code", capability.code);
            item.put("label", capability.label);
            item.put("labelEn", capability.labelEn);
            item.put("group", capability.group);
            item.put("defaultEnabled", capability.defaultEnabled);
            item.put("required", capability.required);
            item.put("supported", capability.supported);
            item.put("reason", capability.reason);
            item.put("dependencies", new ArrayList<>(capability.dependencies));
            result.add(item);
        }
        return result;
    }

    /** Null means no optional selections, not an implicit grant of defaults. */
    public static Set<String> normalize(Collection<String> requested) {
        Set<String> selected = new LinkedHashSet<>();
        if (requested != null) {
            for (String code : requested) {
                Capability capability = CATALOG.get(code);
                if (capability == null || !capability.supported) {
                    throw new IllegalArgumentException("包含未知或暂不支持的 OCI 权限");
                }
                selected.add(code);
            }
        }
        selected.add("BASIC_READ");
        boolean changed;
        do {
            changed = false;
            for (String code : new ArrayList<>(selected)) {
                changed |= selected.addAll(CATALOG.get(code).dependencies);
            }
        } while (changed);
        Set<String> ordered = new LinkedHashSet<>();
        for (String code : CATALOG.keySet()) {
            if (selected.contains(code)) {
                ordered.add(code);
            }
        }
        return Collections.unmodifiableSet(ordered);
    }

    public static List<String> statements(String groupOcid, Collection<String> capabilities) {
        return statements(groupOcid, capabilities, null);
    }

    public static List<String> statements(String groupOcid, Collection<String> capabilities,
                                          AccountPermissionScope scope) {
        if (groupOcid == null || !GROUP_OCID.matcher(groupOcid).matches()) {
            throw new IllegalArgumentException("无效的 OCI 用户组 OCID");
        }
        Set<String> selected = normalize(capabilities);
        if (selected.contains("USER_PASSWORD_RESET")
                && (scope == null || (!scope.isAllUsers() && scope.getPasswordResetUserIds().isEmpty()))) {
            throw new IllegalArgumentException("密码重置必须明确配置可管理的用户范围");
        }
        if (selected.contains("DOMAIN_USER_MANAGE")
                && (scope == null || (!scope.isAllUsers() && scope.getUserManagementGroupIds().isEmpty()))) {
            throw new IllegalArgumentException("账号管理必须明确配置可管理的用户组范围");
        }
        String prefix = "Allow group id " + groupOcid + " to ";
        Set<String> result = new LinkedHashSet<>();
        for (String code : selected) {
            for (Rule rule : CATALOG.get(code).rules) {
                if (rule.readResource != null) {
                    result.add(prefix + "read " + rule.readResource + " in tenancy");
                    continue;
                }
                String permissionCondition = anyEquals("request.permission", rule.permissions);
                String condition = rule.operations == null ? permissionCondition
                        : "all {" + anyEquals("request.operation", rule.operations) + ", "
                        + permissionCondition + "}";
                if ("USER_PASSWORD_RESET".equals(code) && !scope.isAllUsers()) {
                    List<String> targetIds = new ArrayList<>(scope.getPasswordResetUserIds());
                    for (String targetId : targetIds) {
                        if (targetId == null || !targetId.matches("ocid1\\.user\\.[A-Za-z0-9._-]+")) {
                            throw new IllegalArgumentException("密码重置范围包含无效的用户 OCID");
                        }
                    }
                    condition = "all {" + anyEquals("request.operation", rule.operations) + ", "
                            + permissionCondition + ", " + anyEquals("target.user.id", targetIds) + "}";
                }
                result.add(prefix + "manage all-resources in tenancy where " + condition);
            }
        }
        return new ArrayList<>(result);
    }

    public static String serialize(Collection<String> capabilities) {
        return JSON.toJSONString(normalize(capabilities));
    }

    /**
     * Persisted metadata fails closed. A malformed/future capability must never
     * turn an imported tenant into an unrestricted legacy tenant.
     */
    public static Set<String> parse(String value) {
        if (value == null || value.trim().isEmpty()) {
            return Collections.emptySet();
        }
        try {
            Object parsed = JSON.parse(value);
            if (!(parsed instanceof JSONArray)) {
                return Collections.emptySet();
            }
            List<String> codes = new ArrayList<>();
            for (Object code : (JSONArray) parsed) {
                if (!(code instanceof String)) {
                    return Collections.emptySet();
                }
                codes.add((String) code);
            }
            if (!codes.contains("BASIC_READ")) {
                return Collections.emptySet();
            }
            Set<String> normalized = normalize(codes);
            // Missing dependencies indicate incomplete or tampered metadata.
            return new LinkedHashSet<>(codes).equals(normalized) ? normalized : Collections.emptySet();
        } catch (RuntimeException ignored) {
            return Collections.emptySet();
        }
    }

    private static String anyEquals(String variable, List<String> values) {
        List<String> conditions = values.stream()
                .map(value -> variable + " = '" + value + "'")
                .collect(Collectors.toList());
        return conditions.size() == 1 ? conditions.get(0) : "any {" + String.join(", ", conditions) + "}";
    }

    private static List<String> ops(String... operations) {
        return Arrays.asList(operations);
    }

    private static Capability add(String code, String label, String labelEn, String group,
                                  boolean defaultEnabled, boolean required, String reason) {
        Capability capability = new Capability(code, label, labelEn, group, defaultEnabled, required, reason);
        CATALOG.put(code, capability);
        return capability;
    }

    private static void unsupported(String code, String label, String labelEn, String reason) {
        add(code, label, labelEn, "account", false, false, reason).supported = false;
    }

    private static final class Capability {
        private final String code;
        private final String label;
        private final String labelEn;
        private final String group;
        private final boolean defaultEnabled;
        private final boolean required;
        private final String reason;
        private boolean supported = true;
        private final List<String> dependencies = new ArrayList<>();
        private final List<Rule> rules = new ArrayList<>();

        private Capability(String code, String label, String labelEn, String group,
                           boolean defaultEnabled, boolean required, String reason) {
            this.code = code;
            this.label = label;
            this.labelEn = labelEn;
            this.group = group;
            this.defaultEnabled = defaultEnabled;
            this.required = required;
            this.reason = reason;
        }

        private Capability dependsOn(String code) {
            dependencies.add(code);
            return this;
        }

        private Capability permissions(List<String> operations, String... permissions) {
            rules.add(new Rule(operations, Arrays.asList(permissions), null));
            return this;
        }

        private Capability readResource(String resource) {
            rules.add(new Rule(null, Collections.emptyList(), resource));
            return this;
        }
    }

    private static final class Rule {
        private final List<String> operations;
        private final List<String> permissions;
        private final String readResource;

        private Rule(List<String> operations, List<String> permissions, String readResource) {
            this.operations = operations;
            this.permissions = permissions;
            this.readResource = readResource;
        }
    }
}
