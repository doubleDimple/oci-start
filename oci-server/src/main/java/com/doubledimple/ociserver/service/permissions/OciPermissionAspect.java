package com.doubledimple.ociserver.service.permissions;

import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.DbConfigRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.dao.repository.TenantSocialRepository;
import com.doubledimple.dao.repository.TenantEmailConfigRepository;
import org.aspectj.lang.JoinPoint;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Before;
import org.springframework.beans.BeanWrapperImpl;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.util.*;

/**
 * Service 边界负责拦截直接 API、TG 等调用；Controller 边界覆盖仍直接调用
 * 静态 OCI 工具的入口。资源 ID 始终从数据库反查租户，不信任调用者拼接的 tenantId。
 * 云端 IAM 策略另行约束脱离本应用的调用。
 */
@Aspect
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
public class OciPermissionAspect {
    @Resource private TenantRepository tenantRepository;
    @Resource private OracleInstanceDetailRepository instanceRepository;
    @Resource private DbConfigRepository dbRepository;
    @Resource private TenantSocialRepository socialRepository;
    @Resource private TenantEmailConfigRepository emailConfigRepository;

    private static final Map<String, Rule> RULES = new HashMap<>();
    static {
        rule("OracleInstanceServiceImpl", "killInstance", "instance", 0, "", "INSTANCE_DELETE");
        rule("OracleInstanceServiceImpl", "sendCode", "instance", 0, "", "INSTANCE_DELETE");
        rule("OracleInstanceServiceImpl", "startInstance,stopInstanceByInstanceId", "instance", 0, "", "INSTANCE_POWER");
        rule("OracleInstanceServiceImpl", "updateInstanceConfig,updateInstanceName", "instance", 0, "", "INSTANCE_UPDATE");
        rule("OracleInstanceServiceImpl", "handleShrink,handleExpansion", "instance", 0, "", "VOLUME_MANAGE");
        rule("OracleInstanceServiceImpl", "enableOrRefreshIpv6,changePublicIp,changePublicIp2", "instance", 0, "", "NETWORK_MANAGE");
        // This historical DTO calls the local InstanceDetails ID "tenantId".
        rule("OracleInstanceServiceImpl", "switchToSpecificIpRange", "instance", 0, "tenantId", "NETWORK_MANAGE");
        rule("OracleInstanceServiceImpl", "switchVnicToSpecificIpRange", "instance", 0, "instanceId", "NETWORK_MANAGE");
        rule("OracleInstanceServiceImpl", "sysImageBackUp", "instance", 0, "instanceId", "VOLUME_MANAGE");
        rule("OracleInstanceServiceImpl", "createOciUser,createOciAdminUser", "tenant", 0, "", "USER_CREATE");
        rule("OracleInstanceServiceImpl", "findGroup", "tenant", 0, "", "USER_READ");
        rule("VnicServiceImpl", "configureLoadBalancer,restoreNetwork", "instance", 0, "", "NETWORK_MANAGE");
        rule("QuickDdServiceImpl", "quickDd,quickDdSse", "instance", 0, "instanceId", "INSTANCE_REINSTALL");
        rule("InstanceDetailsServiceImpl", "doBootVolumeBackUp,doBootVolumeBackUpNoAuth,doBootVolumeBackUpNoAuthReplace",
                "api-user", 1, "userId", "VOLUME_MANAGE");
        rule("BootVolumeServiceImpl", "handleShrink", "instance", 0, "", "VOLUME_MANAGE");
        rule("TenantServiceImpl", "listUsers,getPageUsers", "tenant", 0, "", "USER_READ");
        rule("TenantServiceImpl", "createUser", "tenant", 0, "", "USER_CREATE");
        rule("TenantServiceImpl", "deleteUser", "tenant", 0, "tenantId", "USER_DELETE");
        rule("TenantServiceImpl", "resetPassword", "tenant", 0, "tenantId", "USER_PASSWORD_RESET");
        rule("TenantServiceImpl", "updateUserState", "tenant", 0, "tenantId", "DOMAIN_USER_MANAGE");
        rule("TenantServiceImpl", "updateUserPasswordPolicy", "tenant", 0, "", "PASSWORD_POLICY");
        rule("TenantServiceImpl", "getPasspolicy", "tenant", 0, "", "PASSWORD_POLICY");
        rule("TenantServiceImpl", "resetAccountFactor", "tenant", 0, "", "MFA_MANAGE");
        rule("TenantServiceImpl", "enableEmailService,disableEmailService,testEmailService",
                "tenant", 0, "tenantId", "EMAIL_MANAGE");
        rule("TenantServiceImpl", "getEmailServiceStatus", "tenant", 0, "", "EMAIL_MANAGE");
        rule("TenantServiceImpl", "queryAuditLogs", "tenant", 0, "tenantId", "AUDIT_READ");
        rule("EmailServiceImpl", "disableEmailForTenant", "email-config", 0, "id", "EMAIL_MANAGE");
        rule("TenantServiceImpl", "findGroups", "tenant", 0, "", "USER_READ");
        rule("TenantServiceImpl", "deleteBootVolume", "tenant", 0, "", "BOOT_VOLUME_DELETE");
        rule("TenantServiceImpl", "updateBootVolumeVpus", "tenant", 1, "tenantId", "VOLUME_MANAGE");
        rule("CloudBusinessServiceImpl", "queryDailyCost", "tenant", 0, "tenantId", "COST_READ");
        rule("OciCostServiceImpl", "queryCurrentMonthCostSimple,queryYesterdayCost,queryCurrentMonthCost,queryLastMonthCost,queryCustomCost",
                "tenant", 0, "", "COST_READ");
        rule("SocialTypeServiceImpl", "getAllSocialType,addSocial", "tenant", 0, "tenantId", "SOCIAL_MANAGE");
        rule("SocialTypeServiceImpl", "updateSocial,disable,delete", "social", 0, "id", "SOCIAL_MANAGE");
        rule("DbConfigServiceImpl", "findByTenantId,syncMysqlFromCloud", "tenant", 0, "", "MYSQL_READ");
        rule("DbConfigServiceImpl", "syncSingleMysqlFromCloud", "db", 0, "", "MYSQL_READ");
        rule("DbConfigServiceImpl", "createMysql", "tenant", 0, "", "MYSQL_MANAGE", "NETWORK_MANAGE");
        rule("DbConfigServiceImpl", "bindPublicIp", "db", 0, "", "MYSQL_MANAGE", "NETWORK_MANAGE");
        rule("DbConfigServiceImpl", "handleMysqlAction", "db", 0, "id", "MYSQL_MANAGE");
        rule("DbConfigServiceImpl", "resetMysqlAuth", "db", 0, "", "MYSQL_MANAGE");
        rule("TenantController", "subscribeToRegions", "tenant", 0, "tenantId", "REGION_SUBSCRIBE");
        rule("TenantController", "resetAccountFactor,getMfaStatus", "tenant", 0, "", "MFA_MANAGE");
        rule("TenantController", "toggleEmailMFA", "tenant", 0, "tenantId", "MFA_MANAGE");
        rule("TenantController", "getNotificationRecipients,updateNotificationRecipients", "tenant", 0, "tenantId", "NOTIFICATION_EMAIL");
        rule("TenantController", "enableEmailService,disableEmailService,testEmailService", "tenant", 0, "tenantId", "EMAIL_MANAGE");
        rule("TenantController", "getEmailServiceStatus", "tenant", 0, "", "EMAIL_MANAGE");
        rule("TenantController", "getPasspolicy", "tenant", 0, "tenantId", "PASSWORD_POLICY");
        rule("TenantController", "updateUserState", "tenant", 0, "tenantId", "DOMAIN_USER_MANAGE");
        rule("TenantController", "getAuditLogs", "tenant", 0, "tenantId", "AUDIT_READ");
        rule("CloudShellController", "consoleMetadata", "instance", 0, "", "INSTANCE_REINSTALL");
        rule("CloudShellController", "createConsoleConnection,createConsoleConnectionAndSaveKey", "instance", 0, "instanceId", "INSTANCE_REINSTALL");
        rule("CloudShellController", "heavyNewRestart", "instance", 0, "instanceId", "INSTANCE_POWER");
        rule("CloudShellController", "listConsoleConnections,cleanupConsoleConnections", "instance", 0, "", "INSTANCE_REINSTALL");
        rule("CloudShellController", "getConsoleConnectionDetails,deleteConsoleConnection", "tenant", 1, "", "INSTANCE_REINSTALL");
        rule("TrafficStatisticsController", "getAllInstanceTraffic", "tenant-list", 0, "tenantIds", "TRAFFIC_READ");
    }

    private static void rule(String type, String methods, String source, int argument, String property, String... permissions) {
        for (String method : methods.split(",")) {
            RULES.put(type + "." + method, new Rule(source, argument, property, permissions));
        }
    }

    @Before("execution(public * com.doubledimple.ociserver.service..*(..)) || execution(public * com.doubledimple.ociserver.controller..*(..))")
    public void authorize(JoinPoint point) {
        Class<?> type = org.springframework.util.ClassUtils.getUserClass(point.getTarget());
        String method = point.getSignature().getName();
        Object[] args = point.getArgs();
        // Trend queries prioritize instanceId over tenantIds in the service. Check
        // that actual instance, rather than trusting an unrelated selected tenant.
        if ("TrafficStatisticsController".equals(type.getSimpleName()) && "getTrafficTrend".equals(method)) {
            if (args.length == 0) deny();
            authorizeTraffic(property(args[0], "instanceId"), property(args[0], "tenantIds"));
            return;
        }
        if ("InstanceTrafficServiceImpl".equals(type.getSimpleName())) {
            if ("getTrafficTrend".equals(method)) {
                if (args.length < 2) deny();
                authorizeTraffic(args[0], args[1]);
                return;
            }
            if ("getAllInstanceTraffic".equals(method)) {
                if (args.length == 0) deny();
                authorizeTraffic(null, args[0]);
                return;
            }
        }
        Rule rule = RULES.get(type.getSimpleName() + "." + point.getSignature().getName());
        if (rule == null) return;
        if (rule.argument >= args.length) deny();
        Object value = args[rule.argument];
        if (!rule.property.isEmpty()) value = property(value, rule.property);
        if ("tenant-list".equals(rule.source)) {
            authorizeTraffic(null, value);
            return;
        }
        if (value instanceof Collection) {
            for (Object id : (Collection<?>) value) check(rule, id);
        } else {
            check(rule, value);
        }
    }

    private void check(Rule rule, Object value) {
        Tenant tenant;
        if (value instanceof Tenant) {
            // 重新读取，避免异步任务持有更新权限前的实体快照。
            if (((Tenant) value).getId() == null) deny();
            tenant = tenantRepository.findById(((Tenant) value).getId()).orElse(null);
        } else if ("api-user".equals(rule.source)) {
            List<Tenant> identities = tenantRepository.findByTenantId(String.valueOf(value));
            if (identities.isEmpty()) deny();
            for (Tenant identity : identities) {
                for (String permission : rule.permissions) OciPermissions.require(identity, permission);
            }
            return;
        } else if ("instance".equals(rule.source)) {
            String id = value == null ? "" : value.toString();
            InstanceDetails instance = id.startsWith("ocid1.instance.") ? instanceRepository.findByInstanceId(id)
                    : instanceRepository.findById(id(value)).orElse(null);
            if (instance == null) { deny(); return; }
            tenant = tenantRepository.findById(instance.getTenantId()).orElse(null);
        } else if ("db".equals(rule.source)) {
            com.doubledimple.dao.entity.DbConfig db = dbRepository.findById(id(value)).orElse(null);
            if (db == null) { deny(); return; }
            tenant = tenantRepository.findById(db.getTenantId()).orElse(null);
        } else if ("social".equals(rule.source)) {
            com.doubledimple.dao.entity.TenantSocial social = socialRepository.findById(id(value)).orElse(null);
            if (social == null) { deny(); return; }
            tenant = tenantRepository.findById(social.getTenantId()).orElse(null);
        } else if ("email-config".equals(rule.source)) {
            com.doubledimple.dao.entity.TenantEmailConfig config = emailConfigRepository.findById(id(value)).orElse(null);
            if (config == null) { deny(); return; }
            tenant = tenantRepository.findById(config.getTenantId()).orElse(null);
        } else {
            tenant = tenantRepository.findById(id(value)).orElse(null);
        }
        if (tenant == null) { deny(); return; }
        for (String permission : rule.permissions) OciPermissions.require(tenant, permission);
    }

    private void authorizeTraffic(Object instanceId, Object tenantIds) {
        if (instanceId != null && !instanceId.toString().trim().isEmpty()) {
            check(new Rule("instance", 0, "", new String[]{"TRAFFIC_READ"}), instanceId);
            return;
        }
        Rule tenantRule = new Rule("tenant", 0, "", new String[]{"TRAFFIC_READ"});
        if (tenantIds instanceof Collection && !((Collection<?>) tenantIds).isEmpty()) {
            for (Object tenantId : (Collection<?>) tenantIds) check(tenantRule, tenantId);
        } else if (tenantIds != null && !(tenantIds instanceof Collection)
                && !tenantIds.toString().trim().isEmpty()) {
            check(tenantRule, tenantIds);
        } else {
            // An omitted/empty filter means "all tenants" in the existing service.
            for (Tenant tenant : tenantRepository.findAll()) {
                OciPermissions.require(tenant, "TRAFFIC_READ");
            }
        }
    }

    private Object property(Object bean, String name) {
        if (bean instanceof Map) return ((Map<?, ?>) bean).get(name);
        if (bean == null) { deny(); return null; }
        BeanWrapperImpl wrapper = new BeanWrapperImpl(bean);
        if (!wrapper.isReadableProperty(name)) { deny(); return null; }
        return wrapper.getPropertyValue(name);
    }

    private Long id(Object value) {
        try {
            return Long.valueOf(String.valueOf(value));
        } catch (NumberFormatException e) {
            throw new OciPermissionDeniedException("无法确认操作所属租户");
        }
    }

    private static void deny() { throw new OciPermissionDeniedException("无法确认操作所属租户"); }

    private static final class Rule {
        final String source;
        final int argument;
        final String property;
        final String[] permissions;
        Rule(String source, int argument, String property, String[] permissions) {
            this.source = source;
            this.argument = argument;
            this.property = property;
            this.permissions = permissions;
        }
    }
}
