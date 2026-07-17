package com.doubledimple.ociserver.utils.oracle;

import cn.hutool.core.util.IdUtil;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.enums.oci.OciSocialType;
import com.doubledimple.ocicommon.utils.DateTimeUtils;
import com.doubledimple.ociserver.pojo.response.ResetOciPassResponse;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.User;
import com.oracle.bmc.identity.requests.CreateOrResetUIPasswordRequest;
import com.oracle.bmc.identity.requests.DeleteUserRequest;
import com.oracle.bmc.identity.requests.ListIdentityProvidersRequest;
import com.oracle.bmc.identity.requests.ListUsersRequest;
import com.oracle.bmc.identity.requests.UpdateUserRequest;
import com.oracle.bmc.identity.responses.CreateOrResetUIPasswordResponse;
import com.oracle.bmc.identity.responses.DeleteUserResponse;
import com.oracle.bmc.identity.responses.GetUserResponse;
import com.oracle.bmc.identity.responses.ListUsersResponse;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.App;
import com.oracle.bmc.identitydomains.model.AppIdpPolicy;
import com.oracle.bmc.identitydomains.model.Condition;
import com.oracle.bmc.identitydomains.model.Group;
import com.oracle.bmc.identitydomains.model.IdentityProvider;
import com.oracle.bmc.identitydomains.model.Operations;
import com.oracle.bmc.identitydomains.model.PatchOp;
import com.oracle.bmc.identitydomains.model.Policy;
import com.oracle.bmc.identitydomains.model.Rule;
import com.oracle.bmc.identitydomains.model.RuleExtensionOciconsolesignonpolicyconsentPolicy;
import com.oracle.bmc.identitydomains.model.RuleReturn;
import com.oracle.bmc.identitydomains.model.SocialIdentityProvider;
import com.oracle.bmc.identitydomains.model.SocialIdentityProviders;
import com.oracle.bmc.identitydomains.requests.CreateSocialIdentityProviderRequest;
import com.oracle.bmc.identitydomains.requests.GetPolicyRequest;
import com.oracle.bmc.identitydomains.requests.GetRuleRequest;
import com.oracle.bmc.identitydomains.requests.GetUserRequest;
import com.oracle.bmc.identitydomains.requests.ListAppsRequest;
import com.oracle.bmc.identitydomains.requests.ListConditionsRequest;
import com.oracle.bmc.identitydomains.requests.ListGroupsRequest;
import com.oracle.bmc.identitydomains.requests.ListPoliciesRequest;
import com.oracle.bmc.identitydomains.requests.ListRulesRequest;
import com.oracle.bmc.identitydomains.requests.ListSocialIdentityProvidersRequest;
import com.oracle.bmc.identitydomains.requests.PatchAppRequest;
import com.oracle.bmc.identitydomains.requests.PatchRuleRequest;
import com.oracle.bmc.identitydomains.requests.PatchSocialIdentityProviderRequest;
import com.oracle.bmc.identitydomains.requests.PatchUserRequest;
import com.oracle.bmc.identitydomains.requests.PutConditionRequest;
import com.oracle.bmc.identitydomains.requests.PutRuleRequest;
import com.oracle.bmc.identitydomains.responses.CreateSocialIdentityProviderResponse;
import com.oracle.bmc.identitydomains.responses.GetPolicyResponse;
import com.oracle.bmc.identitydomains.responses.GetRuleResponse;
import com.oracle.bmc.identitydomains.responses.ListAppsResponse;
import com.oracle.bmc.identitydomains.responses.ListConditionsResponse;
import com.oracle.bmc.identitydomains.responses.ListGroupsResponse;
import com.oracle.bmc.identitydomains.responses.ListIdentityProvidersResponse;
import com.oracle.bmc.identitydomains.responses.ListPoliciesResponse;
import com.oracle.bmc.identitydomains.responses.ListRulesResponse;
import com.oracle.bmc.identitydomains.responses.ListSocialIdentityProvidersResponse;
import com.oracle.bmc.identitydomains.responses.PatchRuleResponse;
import com.oracle.bmc.identitydomains.responses.PatchSocialIdentityProviderResponse;
import com.oracle.bmc.identitydomains.responses.PatchUserResponse;
import com.oracle.bmc.identitydomains.responses.PutRuleResponse;
import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import oshi.driver.mac.net.NetStat;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;
import com.doubledimple.ociserver.config.ProxyContext;

/**
 * 登录策略管理工具类
 * 管理 Sign-On Policies，配置 MFA 要求和登录规则
 *
 * @author doubleDimple
 * @date 2025-08-25
 */
@Slf4j
public class SignOnPolicyUtils {

    public static final String OCI_CONSOLE_POLICY_ID = "OciConsolePolicy";
    public static final String DEFAULT_SIGN_ON_POLICY_ID = "DefaultSignOnPolicy";
    public static final String USER_CATEGORY_BASED_SIGN_ON_POLICY_ID = "UserCategoryBasedSignOnPolicy";

    private static final String SOCIAL_IDP_SCHEMA = "urn:ietf:params:scim:schemas:oracle:idcs:SocialIdentityProvider";


    //控制台admin登录规则
    public static final String RULE_CONSOLE_ADMIN_ID = "OciConsoleAdminMFARule";
    //控制台非admin登录规则
    public static final String RULE_CONSOLE_NO_ADMIN_ID = "OciConsoleMFANonAdminRule";

    private static final String DEFAULT_IDP_POLICY_NAME = "Default Identity Provider Policy";
    private static final String DEFAULT_IDP_RULE_NAME   = "Default IDP Rule";
    private static final String OCI_CONSOLE_APP_NAME    = "OCI Console";

    private static final String DEFAULT_IDP_POLICY_Id = "OciConsolePolicy";
    private static final String DEFAULT_IDP_RULE_ID = "DefaultIDPRule";


    public static final List<String> DEFAULT_RULE_IDS = Arrays.asList(RULE_CONSOLE_ADMIN_ID, RULE_CONSOLE_NO_ADMIN_ID);


    // SCIM Schema 常量
    private static final String CONDITION_SCHEMA = "urn:ietf:params:scim:schemas:oracle:idcs:Condition";
    private static final String RULE_SCHEMA = "urn:ietf:params:scim:schemas:oracle:idcs:Rule";
    private static final String POLICY_SCHEMA = "urn:ietf:params:scim:schemas:oracle:idcs:Policy";
    private static final String PATCH_ON_SCHEMA = "urn:ietf:params:scim:api:messages:2.0:PatchOp";

    /**
     * 获取所有激活的登录策略
     *
     * @param tenant 租户信息
     * @return 激活的登录策略列表
     */
    public static Map<String, Object> getActiveSignOnPolicies(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;
        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);
            // 获取激活的登录策略
            ListPoliciesRequest request = ListPoliciesRequest.builder()
                    .limit(100)
                    .build();

            ListPoliciesResponse listResponse = identityDomainsClient.listPolicies(request);
            List<Policy> policies = listResponse.getPolicies().getResources();

            List<Map<String, Object>> policyList = policies.stream()
                    .filter(policy -> Boolean.TRUE.equals(policy.getActive()))
                    .map(policy -> {
                        Map<String, Object> policyInfo = new HashMap<>();
                        policyInfo.put("name", policy.getName());
                        policyInfo.put("description", policy.getDescription());
                        policyInfo.put("active", policy.getActive());
                        policyInfo.put("id", policy.getId());
                        policyInfo.put("ocid", policy.getOcid());
                        return policyInfo;
                    }).collect(Collectors.toList());

            response.put("success", true);
            response.put("schemas", Arrays.asList("urn:ietf:params:scim:api:messages:2.0:ListResponse"));
            response.put("totalResults", policyList.size());
            response.put("Resources", policyList);
            response.put("startIndex", 1);
            response.put("itemsPerPage", Math.min(100, policyList.size()));
            response.put("message", "激活的登录策略获取成功");

            log.info("租户 [{}] 的激活登录策略已获取，共 {} 个策略", tenant.getTenancyName(), policyList.size());

        } catch (Exception e) {
            log.error("获取激活登录策略失败: {}", e.getMessage(), e);
            response.put("message", "获取激活登录策略失败: " + e.getMessage());
            response.put("schemas", Arrays.asList("urn:ietf:params:scim:api:messages:2.0:Error"));
        }finally {
            if (identityDomainsClient != null){
                identityDomainsClient.close();
            }
        }

        return response;
    }

    /**
    * @Description: 获取租户下的登录策略
    * @Param: [com.doubledimple.dao.entity.Tenant]
    * @return: java.util.Map<java.lang.String,java.lang.Object>
    * @Author: doubleDimple
    * @Date: 8/30/25 8:56 AM
    */
    public static Map<String, Object> getSignOnPolicies(Tenant tenant) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;

        try {
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 获取登录策略列表
            ListPoliciesRequest request = ListPoliciesRequest.builder()
                    .limit(100)
                    .build();

            ListPoliciesResponse listResponse = identityDomainsClient.listPolicies(request);
            List<Policy> policies = listResponse.getPolicies().getResources();

            // 转换为所需的格式
            List<Map<String, Object>> policyList = policies.stream().map(policy -> {
                Map<String, Object> policyInfo = new HashMap<>();
                policyInfo.put("name", policy.getName());
                policyInfo.put("description", policy.getDescription());
                policyInfo.put("active", policy.getActive());
                policyInfo.put("id", policy.getId());
                policyInfo.put("ocid", policy.getOcid());
                return policyInfo;
            }).collect(Collectors.toList());

            // 构建返回数据，格式与你提供的JSON一致（Java 8兼容）
            response.put("success", true);
            response.put("schemas", Arrays.asList("urn:ietf:params:scim:api:messages:2.0:ListResponse"));
            response.put("totalResults", policies.size());
            response.put("Resources", policyList);
            response.put("startIndex", 1);
            response.put("itemsPerPage", Math.min(100, policies.size()));
            response.put("message", "登录策略获取成功");

            log.info("租户 [{}] 的登录策略已获取，共 {} 个策略", tenant.getTenancyName(), policies.size());

        } catch (Exception e) {
            log.error("获取登录策略失败: {}", e.getMessage(), e);
            response.put("message", "获取登录策略失败: " + e.getMessage());
            response.put("schemas", Arrays.asList("urn:ietf:params:scim:api:messages:2.0:Error"));
        }finally {
            if (identityDomainsClient != null){
                identityDomainsClient.close();
            }
        }

        return response;
    }

    public static Map<String, Object> getSignOnPolicyById(Tenant tenant) {
        return getSignOnPolicyById(tenant,OCI_CONSOLE_POLICY_ID);
    }


    /**
     * 根据策略ID获取特定的登录策略详情
     *
     * @param tenant 租户信息
     * @param policyId 策略ID
     * @return 策略详情
     */
    public static Map<String, Object> getSignOnPolicyById(Tenant tenant, String policyId) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;
        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 通过策略ID直接获取策略详情
            GetPolicyRequest request = GetPolicyRequest.builder()
                    .policyId(policyId)
                    .build();

            GetPolicyResponse getPolicyResponse = identityDomainsClient.getPolicy(request);
            Policy policy = getPolicyResponse.getPolicy();

            Map<String, Object> policyInfo = new HashMap<>();
            policyInfo.put("name", policy.getName());
            policyInfo.put("description", policy.getDescription());
            policyInfo.put("active", policy.getActive());
            policyInfo.put("id", policy.getId());
            policyInfo.put("ocid", policy.getOcid());

            response.put("success", true);
            response.put("policy", policyInfo);
            response.put("message", "登录策略详情获取成功");

            log.info("租户 [{}] 的登录策略 [{}] 详情已获取", tenant.getTenancyName(), policyId);

        } catch (Exception e) {
            log.error("获取登录策略详情失败: {}", e.getMessage(), e);
            response.put("message", "获取登录策略详情失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null){
                identityDomainsClient.close();
            }
        }

        return response;
    }



    /**
     * 获取指定策略下的登录规则列表（单独查询规则）
     *
     * @param tenant 租户信息
     * @param policyId 策略ID
     * @return 登录规则列表
     */
    public static Map<String, Object> getSignOnRulesByPolicy(Tenant tenant, String policyId) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;
        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            // 单独查询策略下的规则
            ListRulesRequest request = ListRulesRequest.builder()
                    .limit(100)
                    .build();

            ListRulesResponse listResponse = identityDomainsClient.listRules(request);
            List<Rule> rules = listResponse.getRules().getResources();

            // 转换为你需要的格式
            List<Map<String, Object>> ruleList = rules.stream()
                    .filter(rule -> DEFAULT_RULE_IDS.contains(rule.getId()))
                    .map(rule -> {
                        Map<String, Object> ruleInfo = new HashMap<>();
                        ruleInfo.put("name", rule.getName());  // 规则名称
                        ruleInfo.put("id", rule.getId());
                        /*
                        String refUrl = String.format("%s/admin/v1/Rules/%s", domainUrl, rule.getId());
                        ruleInfo.put("$ref", refUrl);*/
                        return ruleInfo;
                    }).collect(Collectors.toList());

            // 构建返回数据
            response.put("success", true);
            response.put("policyId", policyId);
            response.put("rules", ruleList);
            response.put("totalRules", ruleList.size());
            response.put("message", "策略规则列表获取成功");

            log.info("租户 [{}] 策略 [{}] 下的规则已获取，共 {} 个规则",
                    tenant.getTenancyName(), policyId, ruleList.size());

        } catch (Exception e) {
            log.error("获取策略规则列表失败: {}", e.getMessage(), e);
            response.put("message", "获取策略规则列表失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null){
                identityDomainsClient.close();
            }
        }

        return response;
    }


    /**
     * 修改登录规则，启用邮箱登录
     *
     * @param tenant 租户信息
     * @param ruleId 规则ID
     * @param enableEmailLogin 是否启用邮箱登录
     * @return 操作结果
     */
    /*public static Map<String, Object> updateSignOnRuleEmailLogin(IdentityDomainsClient identityDomainsClient,Tenant tenant, String ruleId, boolean enableEmailLogin) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            if (identityDomainsClient == null){
                identityDomainsClient = initIdentityDomainsClient(tenant);
            }
            GetRuleResponse getRuleResponse = identityDomainsClient.getRule(GetRuleRequest.builder().ruleId(ruleId).build());
            Rule currentRule = getRuleResponse.getRule();

            // 2. 构建更新的规则
            Rule.Builder ruleBuilder = Rule.builder().copy(currentRule);

            // 3. 修改规则的2FAFactors以启用/禁用邮箱登录
            List<RuleReturn> returnList = new ArrayList<>();
            if (currentRule.getRuleReturn() != null) {
                returnList = new ArrayList<>(currentRule.getRuleReturn());
            }

            // 查找2FAFactors设置并修改
            boolean factorsUpdated = false;
            for (int i = 0; i < returnList.size(); i++) {
                RuleReturn returnItem = returnList.get(i);
                if ("2FAFactors".equals(returnItem.getName())) {
                    // 解析当前的2FA因子列表
                    String factorsValue = returnItem.getValue().toString();
                    // 移除JSON数组的括号和引号，获取因子列表
                    factorsValue = factorsValue.replaceAll("[\\[\\]\"]", "");
                    List<String> currentFactors = new ArrayList<>();
                    if (!factorsValue.trim().isEmpty()) {
                        String[] factorArray = factorsValue.split(",");
                        for (String factor : factorArray) {
                            currentFactors.add(factor.trim());
                        }
                    }

                    // 添加或移除EMAIL因子
                    if (enableEmailLogin) {
                        if (!currentFactors.contains("EMAIL")) {
                            currentFactors.add("EMAIL");
                        }
                    } else {
                        currentFactors.remove("EMAIL");
                    }

                    // 构建新的JSON数组格式
                    StringBuilder newFactorsValue = new StringBuilder("[");
                    for (int j = 0; j < currentFactors.size(); j++) {
                        if (j > 0) newFactorsValue.append(",");
                        newFactorsValue.append("\"").append(currentFactors.get(j)).append("\"");
                    }
                    newFactorsValue.append("]");

                    RuleReturn updatedReturn = RuleReturn.builder()
                            .name("2FAFactors")
                            .value(newFactorsValue.toString())
                            .build();

                    returnList.set(i, updatedReturn);
                    factorsUpdated = true;
                    break;
                }
            }

            // 如果没有找到2FAFactors，并且要启用EMAIL，则添加新的
            if (!factorsUpdated && enableEmailLogin) {
                RuleReturn emailReturn = RuleReturn.builder()
                        .name("2FAFactors")
                        .value("[\"EMAIL\"]")
                        .build();
                returnList.add(emailReturn);
            }

            ruleBuilder.ruleReturn(returnList);
            Rule updatedRule = ruleBuilder.build();

            // 4. 更新规则
            PutRuleRequest putRuleRequest = PutRuleRequest.builder()
                    .ruleId(ruleId)
                    .rule(updatedRule)
                    .build();

            PutRuleResponse putRuleResponse = identityDomainsClient.putRule(putRuleRequest);

            response.put("success", true);
            response.put("ruleId", ruleId);
            response.put("emailLoginEnabled", enableEmailLogin);
            response.put("message", String.format("登录规则已更新，邮箱登录%s", enableEmailLogin ? "已启用" : "已禁用"));

            // 返回更新后的规则信息
            Rule updatedRuleResult = putRuleResponse.getRule();
            Map<String, Object> ruleInfo = new HashMap<>();
            ruleInfo.put("id", updatedRuleResult.getId());
            ruleInfo.put("name", updatedRuleResult.getName());
            ruleInfo.put("active", updatedRuleResult.getActive());
            ruleInfo.put("return", updatedRuleResult.getRuleReturn());
            response.put("updatedRule", ruleInfo);

            log.info("租户 [{}] 规则的邮箱登录设置已更新：{}",
                    tenant.getTenancyName(), enableEmailLogin ? "启用" : "禁用");

        } catch (Exception e) {
            log.error("更新登录规则失败: {}", e.getMessage(), e);
            response.put("message", "更新登录规则失败: " + e.getMessage());
        }

        return response;
    }*/

    public static Map<String, Object> updateSignOnRuleEmailLoginPatch(IdentityDomainsClient identityDomainsClient, Tenant tenant, String ruleId, boolean enableEmailLogin) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            if (identityDomainsClient == null) {
                identityDomainsClient = initIdentityDomainsClient(tenant);
            }
            GetRuleResponse getRuleResponse = identityDomainsClient.getRule(GetRuleRequest.builder().ruleId(ruleId).build());
            Rule currentRule = getRuleResponse.getRule();

            Rule.Builder ruleBuilder = Rule.builder().copy(currentRule);

            List<RuleReturn> returnList = new ArrayList<>();
            if (currentRule.getRuleReturn() != null) {
                returnList = new ArrayList<>(currentRule.getRuleReturn());
            }

            boolean factorsUpdated = false;
            for (int i = 0; i < returnList.size(); i++) {
                RuleReturn returnItem = returnList.get(i);
                if ("2FAFactors".equals(returnItem.getName())) {
                    String factorsValue = returnItem.getValue().toString();
                    factorsValue = factorsValue.replaceAll("[\\[\\]\"]", "");
                    List<String> currentFactors = new ArrayList<>();
                    if (!factorsValue.trim().isEmpty()) {
                        String[] factorArray = factorsValue.split(",");
                        for (String factor : factorArray) {
                            currentFactors.add(factor.trim());
                        }
                    }

                    if (enableEmailLogin) {
                        if (!currentFactors.contains("EMAIL")) {
                            currentFactors.add("EMAIL");
                        }
                    } else {
                        currentFactors.remove("EMAIL");
                    }

                    StringBuilder newFactorsValue = new StringBuilder("[");
                    for (int j = 0; j < currentFactors.size(); j++) {
                        if (j > 0) newFactorsValue.append(",");
                        newFactorsValue.append("\"").append(currentFactors.get(j)).append("\"");
                    }
                    newFactorsValue.append("]");

                    RuleReturn updatedReturn = RuleReturn.builder()
                            .name("2FAFactors")
                            .value(newFactorsValue.toString())
                            .build();

                    returnList.set(i, updatedReturn);
                    factorsUpdated = true;
                    break;
                }
            }

            if (!factorsUpdated && enableEmailLogin) {
                returnList.add(RuleReturn.builder().name("2FAFactors").value("[\"EMAIL\"]").build());
            }

            RuleExtensionOciconsolesignonpolicyconsentPolicy consentExtension =
                    RuleExtensionOciconsolesignonpolicyconsentPolicy.builder()
                            .consent(true)
                            .justification("Other")
                            .reason("Updating 2FAFactors to " + (enableEmailLogin ? "include" : "exclude") + " EMAIL")
                            .build();

            ruleBuilder.urnIetfParamsScimSchemasOracleIdcsExtensionOciconsolesignonpolicyconsentPolicy(consentExtension);

            ruleBuilder.ruleReturn(returnList);
            Rule updatedRule = ruleBuilder.build();

            // 5. 执行更新 (PUT 方式)
            PutRuleRequest putRuleRequest = PutRuleRequest.builder()
                    .ruleId(ruleId)
                    .rule(updatedRule)
                    .build();

            PutRuleResponse putRuleResponse = identityDomainsClient.putRule(putRuleRequest);

            response.put("success", true);
            response.put("ruleId", ruleId);
            response.put("message", String.format("登录规则已更新，邮箱登录%s", enableEmailLogin ? "已启用" : "已禁用"));

            Rule updatedRuleResult = putRuleResponse.getRule();
            Map<String, Object> ruleInfo = new HashMap<>();
            ruleInfo.put("id", updatedRuleResult.getId());
            ruleInfo.put("name", updatedRuleResult.getName());
            ruleInfo.put("return", updatedRuleResult.getRuleReturn());
            response.put("updatedRule", ruleInfo);

            log.info("租户 [{}] 规则的邮箱登录设置已更新：{}",
                    tenant.getTenancyName(), enableEmailLogin ? "启用" : "禁用");

        } catch (Exception e) {
            log.error("更新登录规则失败: {}", e.getMessage(), e);
            throw new RuntimeException("更新登录规则失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 获取指定规则的详细信息
     *
     * @param tenant 租户信息
     * @param ruleId 规则ID
     * @return 规则详情
     */
    public static Map<String, Object> getSignOnRuleDetail(Tenant tenant, String ruleId) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        IdentityDomainsClient identityDomainsClient = null;
        try{
            identityDomainsClient = initIdentityDomainsClient(tenant);

            GetRuleResponse getRuleResponse = identityDomainsClient.getRule(GetRuleRequest.builder().ruleId(ruleId).build());
            Rule rule = getRuleResponse.getRule();
            List<Map<String, Object>> ruleLinkedGroups = getRuleLinkedGroups(rule.getId(), identityDomainsClient);
            // 构建规则详细信息
            Map<String, Object> ruleInfo = new HashMap<>();
            ruleInfo.put("id", rule.getId());
            ruleInfo.put("name", rule.getName());
            ruleInfo.put("description", rule.getDescription());
            ruleInfo.put("active", rule.getActive());
            ruleInfo.put("condition", rule.getCondition());
            ruleInfo.put("policyType", rule.getPolicyType());
            ruleInfo.put("return", rule.getRuleReturn());
            ruleInfo.put("ocid", rule.getOcid());
            ruleInfo.put("ruleLinkedGroups", ruleLinkedGroups);

            // 分析当前的2FA因子设置
            boolean emailEnabled = false;
            List<String> current2FAFactors = new ArrayList<>();

            if (rule.getRuleReturn() != null) {
                for (RuleReturn returnItem : rule.getRuleReturn()) {
                    if ("2FAFactors".equals(returnItem.getName())) {
                        String factorsValue = returnItem.getValue().toString();
                        // 解析JSON数组格式的2FA因子
                        factorsValue = factorsValue.replaceAll("[\\[\\]\"]", "");
                        if (!factorsValue.trim().isEmpty()) {
                            String[] factorArray = factorsValue.split(",");
                            for (String factor : factorArray) {
                                String cleanFactor = factor.trim();
                                current2FAFactors.add(cleanFactor);
                                if ("EMAIL".equals(cleanFactor)) {
                                    emailEnabled = true;
                                    break;
                                }
                            }
                        }
                        break;
                    }
                }
            }


            List<Group> groups = getGroups(tenant, identityDomainsClient,null);
            ruleInfo.put("emailLoginEnabled", emailEnabled);
            ruleInfo.put("current2FAFactors", current2FAFactors);
            ruleInfo.put("groups", groups);

            response.put("success", true);
            response.put("rule", ruleInfo);
            response.put("message", "规则详情获取成功");

            log.info("租户 [{}] 规则 [{}] 的详情已获取，邮箱登录状态：{}",
                    tenant.getTenancyName(), ruleId, emailEnabled ? "已启用" : "未启用");

        } catch (Exception e) {
            log.error("获取规则详情失败: {}", e.getMessage(), e);
            response.put("message", "获取规则详情失败: " + e.getMessage());
        }finally {
            if (identityDomainsClient != null){
                identityDomainsClient.close();
            }
        }

        return response;
    }


    /**
     * 获取管理员组列表（常用的管理员组）
     *
     * @param tenant 租户信息
     * @return 管理员组列表
     */
    public static List<Group> getGroups(Tenant tenant,IdentityDomainsClient identityDomainsClient,String groupId) {
        List<Group> groups = new ArrayList<>();
        IdentityDomainsClient identityDomainsClientNow = null;
        try {
            if (identityDomainsClient == null){
                identityDomainsClientNow = initIdentityDomainsClient(tenant);
            }else{
                identityDomainsClientNow = identityDomainsClient;
            }
            ListGroupsResponse listResponse = identityDomainsClientNow.listGroups(ListGroupsRequest.builder().limit(50).build());
            if (listResponse.getGroups() != null && !listResponse.getGroups().getResources().isEmpty()){
                //过滤AllUsersId
                if (StringUtils.isBlank(groupId)){
                    groups = listResponse.getGroups().getResources().stream().
                            filter(group -> !group.getId().equals("AllUsersId"))
                            .collect(Collectors.toList());
                }else {
                    groups = listResponse.getGroups().getResources().stream().
                            filter(group -> !group.getId().equals("AllUsersId"))
                            .filter(group -> group.getDisplayName().equals(groupId))
                            .collect(Collectors.toList());
                    if (groups.isEmpty()){
                        log.warn("未找到组 [{}]，使用组 ID 搜索", groupId);
                        groups = listResponse.getGroups().getResources().stream().
                                filter(group -> !group.getId().equals("AllUsersId"))
                                .filter(group -> group.getId().equals(groupId))
                                .collect(Collectors.toList());
                        if (groups.isEmpty()){
                            log.warn("未找到组 [{}]，返回原始组", groupId);
                            groups = listResponse.getGroups().getResources().stream().
                                    filter(group -> !group.getId().equals("AllUsersId"))
                                    .collect(Collectors.toList());
                        }
                    }

                }

            }
            log.debug("租户 [{}] 的管理员组列表已获取，共 {} 个组", tenant.getTenancyName(), groups.size());
            return groups;
        } catch (Exception e) {
            log.warn("获取管理员组列表失败: {}", e.getMessage(), e);
        }
        return groups;
    }

    public static List<Map<String, Object>> getRuleLinkedGroups(String ruleId,IdentityDomainsClient identityDomainsClient) {
        List<Map<String, Object>> linkedGroups = new ArrayList<>();
        try  {
            // 1. 获取规则信息
            GetRuleRequest getRuleRequest = GetRuleRequest.builder()
                    .ruleId(ruleId)
                    .build();

            GetRuleResponse getRuleResponse = identityDomainsClient.getRule(getRuleRequest);
            Rule rule = getRuleResponse.getRule();

            if (rule.getConditionGroup() != null) {
                String conditionGroupId = rule.getConditionGroup().getValue();
                log.debug("规则关联的ConditionGroup: {}", conditionGroupId);

                // 2. 查询OciConsoleGroupCondition条件
                ListConditionsRequest conditionsRequest = ListConditionsRequest.builder()
                        .filter("id eq \"OciConsoleGroupCondition\"")
                        .attributes("id,name,attributeName,attributeValue,operator")
                        .build();

                ListConditionsResponse conditionsResponse = identityDomainsClient.listConditions(conditionsRequest);
                List<Condition> conditions = conditionsResponse.getConditions().getResources();

                for (Condition condition : conditions) {
                    if ("OciConsoleGroupCondition".equals(condition.getId()) &&
                            "user.groups[*].value".equals(condition.getAttributeName())) {

                        String attributeValue = condition.getAttributeValue();
                        log.debug("找到组条件: {}", attributeValue);

                        // 3. 解析组ID列表
                        List<String> groupIds = parseGroupIds(attributeValue);

                        // 4. 查询每个组的详细信息
                        for (String groupId : groupIds) {
                            try {
                                ListGroupsRequest groupRequest = ListGroupsRequest.builder()
                                        .filter(String.format("id eq \"%s\"", groupId))
                                        .build();

                                ListGroupsResponse groupResponse = identityDomainsClient.listGroups(groupRequest);
                                List<Group> groups = groupResponse.getGroups().getResources();

                                if (!groups.isEmpty()) {
                                    Group group = groups.get(0);
                                    Map<String, Object> groupInfo = new HashMap<>();
                                    groupInfo.put("id", group.getId());
                                    groupInfo.put("displayName", group.getDisplayName());
                                    groupInfo.put("ocid", group.getOcid());
                                    groupInfo.put("conditionId", condition.getId());
                                    linkedGroups.add(groupInfo);
                                    log.info("找到关联组: {} (ID: {})", group.getDisplayName(), group.getId());
                                }
                            } catch (Exception e) {
                                log.warn("查询组 [{}] 详情失败: {}", groupId, e.getMessage());
                            }
                        }
                        break;
                    }
                }
            }

            log.debug("规则 [{}] 关联的组: {}", ruleId,
                    linkedGroups.stream().map(g -> g.get("displayName")).collect(Collectors.toList()));

        } catch (Exception e) {
            log.error("获取规则关联组失败: {}", e.getMessage(), e);
        }

        return linkedGroups;
    }

    private static List<String> parseGroupIds(String attributeValue) {
        List<String> groupIds = new ArrayList<>();

        if (StringUtils.isEmpty(attributeValue)) {
            return groupIds;
        }

        try {
            // attributeValue格式: ["cce632d4287445279916a8a3670b51ab","5bbe9a032637414f845e7625f5a9fa66"]
            // 去除方括号和引号，按逗号分割
            String cleaned = attributeValue.replaceAll("[\\[\\]\"]", "");
            if (!cleaned.trim().isEmpty()) {
                String[] ids = cleaned.split(",");
                for (String id : ids) {
                    String trimmedId = id.trim();
                    if (!trimmedId.isEmpty()) {
                        groupIds.add(trimmedId);
                    }
                }
            }

            log.debug("从 [{}] 中解析到组ID: {}", attributeValue, groupIds);

        } catch (Exception e) {
            log.warn("解析组ID失败: {}", e.getMessage());
        }

        return groupIds;
    }


    public static IdentityDomainsClient  initIdentityDomainsClient(Tenant tenant){
        try {
            SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
            String compartmentId = provider.getTenantId();

            IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider);
            IdentityDomainsClient identityDomainsClient = IdentityDomainsClient.builder().clientConfigurator(ProxyContext.get()).build(provider);

            String domainUrl = OciUtils.getDomain(identityClient, compartmentId);
            identityDomainsClient.setEndpoint(domainUrl);
            return identityDomainsClient;
        } catch (Exception e) {
            log.warn("初始化IdentityDomainsClient失败: {}", e.getMessage(),e);
            throw new RuntimeException("初始化IdentityDomainsClient失败: " + e.getMessage());
        }
    }


    /**
     * 向指定规则添加组
     *
     * @param tenant 租户信息
     * @param ruleId 规则ID
     * @param groupIds 要添加的组ID列表
     * @return 操作结果
     */
    public static Map<String, Object> addGroupsToSignOnRule(IdentityDomainsClient identityDomainsClient,Tenant tenant, String ruleId, List<String> groupIds) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);

        try {
            if (identityDomainsClient == null){
                identityDomainsClient = initIdentityDomainsClient(tenant);
            }
            // 1. 获取当前规则关联的组信息
            List<Map<String, Object>> currentLinkedGroups = getRuleLinkedGroups(ruleId, identityDomainsClient);

            // 2. 提取当前已关联的组ID列表
            List<String> currentGroupIds = currentLinkedGroups.stream()
                    .map(group -> (String) group.get("id"))
                    .collect(Collectors.toList());

            // 3. 检查哪些组需要添加（避免重复）
            List<String> actuallyAddedGroups = new ArrayList<>();

            for (String groupId : groupIds) {
                if (!currentGroupIds.contains(groupId)) {
                    actuallyAddedGroups.add(groupId);
                }
            }

            // 4. 如果没有新组要添加，直接返回
            if (actuallyAddedGroups.isEmpty()) {
                response.put("success", true);
                response.put("ruleId", ruleId);
                response.put("message", "所有组都已存在，无需添加");
                response.put("currentGroups", currentGroupIds);
                return response;
            }

            // 5. 追加新组到现有组列表
            List<String> mergedGroupIds = new ArrayList<>(currentGroupIds);
            mergedGroupIds.addAll(actuallyAddedGroups);

            // 6. 构建新的组ID数组字符串
            String newAttributeValue = buildGroupAttributeValue(mergedGroupIds);

            // 7. 更新OciConsoleGroupCondition条件
            boolean conditionUpdated = updateGroupCondition(identityDomainsClient, newAttributeValue);

            if (conditionUpdated) {
                response.put("success", true);
                response.put("ruleId", ruleId);
                response.put("addedGroups", actuallyAddedGroups);
                response.put("skippedGroups", groupIds.stream()
                        .filter(id -> !actuallyAddedGroups.contains(id))
                        .collect(Collectors.toList()));
                response.put("totalGroups", mergedGroupIds.size());
                response.put("message", String.format("成功向规则 [%s] 添加 %d 个组", ruleId, actuallyAddedGroups.size()));

                log.info("租户 [{}] 规则 [{}] 已添加组: {}, 跳过重复组: {}",
                        tenant.getTenancyName(), ruleId, actuallyAddedGroups,
                        groupIds.stream().filter(id -> !actuallyAddedGroups.contains(id)).collect(Collectors.toList()));
            } else {
                response.put("message", "更新组条件失败");
            }

        } catch (Exception e) {
            log.error("向规则添加组失败: {}", e.getMessage(), e);
            response.put("message", "向规则添加组失败: " + e.getMessage());
        }

        return response;
    }

    /**
     * 构建组属性值字符串
     */
    private static String buildGroupAttributeValue(List<String> groupIds) {
        if (groupIds.isEmpty()) {
            return "[]";
        }

        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < groupIds.size(); i++) {
            if (i > 0) {
                sb.append(",");
            }
            sb.append("\"").append(groupIds.get(i)).append("\"");
        }
        sb.append("]");

        return sb.toString();
    }

    /**
     * 更新组条件
     */
    private static boolean updateGroupCondition(IdentityDomainsClient identityDomainsClient, String newAttributeValue) {
        try {
            // 1. 查询OciConsoleGroupCondition条件 - 按照getRuleLinkedGroups的方式
            ListConditionsRequest conditionsRequest = ListConditionsRequest.builder()
                    .filter("id eq \"OciConsoleGroupCondition\"")
                    .attributes("id,name,attributeName,attributeValue,operator")
                    .build();

            ListConditionsResponse conditionsResponse = identityDomainsClient.listConditions(conditionsRequest);
            List<Condition> conditions = conditionsResponse.getConditions().getResources();

            for (Condition condition : conditions) {
                if ("OciConsoleGroupCondition".equals(condition.getId()) &&
                        "user.groups[*].value".equals(condition.getAttributeName())) {

                    log.debug("找到组条件，当前值: {}", condition.getAttributeValue());
                    log.debug("更新为新值: {}", newAttributeValue);

                    // 2. 构建更新的条件对象
                    Condition updatedCondition = Condition.builder()
                            .copy(condition)
                            .attributeValue(newAttributeValue)
                            .schemas(Arrays.asList(CONDITION_SCHEMA))
                            .build();
                    PutConditionRequest putRequest = PutConditionRequest.builder()
                        .conditionId("OciConsoleGroupCondition")
                        .condition(updatedCondition)
                        .build();
                    identityDomainsClient.putCondition(putRequest);

                    log.info("组条件已更新: {} -> {}", condition.getAttributeValue(), newAttributeValue);
                    return true;
                }
            }

            log.warn("未找到OciConsoleGroupCondition条件");
            return false;

        } catch (Exception e) {
            log.error("更新组条件失败: {}", e.getMessage(), e);
            return false;
        }
    }

    /**
    * @Description: 重置控制台密码
    * @Param: [com.doubledimple.dao.entity.Tenant]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/7/25 8:58 AM
    */
    public static ResetOciPassResponse resetPass(Tenant tenant,String userId){
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        ResetOciPassResponse resetOciPassResponse = new ResetOciPassResponse();

        try(IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)){
            // 直接尝试重置密码
            CreateOrResetUIPasswordRequest request = CreateOrResetUIPasswordRequest.builder()
                    .userId(userId)
                    .build();

            CreateOrResetUIPasswordResponse response = identityClient.createOrResetUIPassword(request);
            String temporaryPassword = response.getUIPassword().getPassword();
            String loginUser = response.getUIPassword().getUserId();
            resetOciPassResponse.setTemporaryPassword(temporaryPassword);
            resetOciPassResponse.setLoginUser(loginUser);
            resetOciPassResponse.setResetTime(DateTimeUtils.formatDate(response.getUIPassword().getTimeCreated()));

            log.info("=====================================================");
            log.info("用户:{}控制台密码重置成功", tenant.getUserName());
            log.info("临时密码: {}",temporaryPassword);
            log.info("密码状态: {}",response.getUIPassword().getLifecycleState());
            log.info("创建时间: {}",response.getUIPassword().getTimeCreated());
            log.info("=====================================================");

        } catch (BmcException e) {
            log.error("重置密码失败: {}", e.getMessage(), e);

            // 根据错误类型设置特殊标记
            if (e.getStatusCode() == 404 && e.getMessage().contains("NotAuthorizedOrNotFound")) {
                // 身份域用户或权限不足
                resetOciPassResponse.setResetTime("IDENTITY_DOMAIN_USER");
            } else if (e.getStatusCode() == 401) {
                // 权限不足
                resetOciPassResponse.setResetTime("PERMISSION_DENIED");
            }
        } catch (Exception e) {
            log.error("重置密码失败: {}", e.getMessage(), e);
        }

        return resetOciPassResponse;
    }

    private static String generateTemporaryPassword() {
        final String s = "TP-Oci-Start" + IdUtil.getSnowflakeNextId() + "!";
        log.info("生成临时密码: {}", s);
        return s;
    }

    public static void deleteUser(Tenant tenant, String userId) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        try(IdentityClient identityClient = IdentityClient.builder().clientConfigurator(ProxyContext.get()).build(provider)){
            identityClient.deleteUser(DeleteUserRequest.builder().userId(userId).build());
            log.info("用户:{}删除成功", tenant.getUserName());
        }catch (Exception e){
            log.error("用户:{}删除失败: {}", tenant.getUserName(), e.getMessage(), e);
        }
    }

    public static void doRemoveSocialFromRule(Tenant tenant, OciSocialType socialType){
        String providerName = socialType.getServiceProviderName();
        String filterString = String.format("serviceProviderName eq \"%s\"", providerName);
        try(IdentityDomainsClient idc= initIdentityDomainsClient(tenant)) {
            ListSocialIdentityProvidersResponse listResp = idc.listSocialIdentityProviders(
                    ListSocialIdentityProvidersRequest.builder()
                            .filter(filterString)
                            .limit(1)
                            .build());

            List<SocialIdentityProvider> resources = Collections.emptyList();
            if (listResp.getSocialIdentityProviders() != null
                    && listResp.getSocialIdentityProviders().getResources() != null) {
                resources = listResp.getSocialIdentityProviders().getResources();
            }

            if (!resources.isEmpty()){
                SocialIdentityProvider resource = resources.get(0);
                String idpIdToRemove = resource.getId();
                ListRulesResponse rulesResp = idc.listRules(
                        ListRulesRequest.builder()
                                .filter("id eq \"" + DEFAULT_IDP_RULE_ID + "\"")
                                .limit(1)
                                .build()
                );
                if (rulesResp.getRules().getResources() == null || rulesResp.getRules().getResources().isEmpty()) {
                    log.error("未找到规则，无法执行移除操作。");
                    return;
                }

                Rule rule = rulesResp.getRules().getResources().get(0);
                List<RuleReturn> currentReturns = rule.getRuleReturn();
                if (currentReturns == null) return;

                for (int i = 0; i < currentReturns.size(); i++) {
                    RuleReturn ret = currentReturns.get(i);
                    if ("SocialIDPs".equals(ret.getName())) {
                        String valueStr = ret.getValue();

                        if (valueStr.contains(idpIdToRemove)) {
                            String cleanValue = valueStr.replace("[", "").replace("]", "").replace("\"", "");
                            List<String> idpList = new ArrayList<>(Arrays.asList(cleanValue.split(",\\s*")));
                            idpList.removeIf(id -> id.trim().equals(idpIdToRemove));
                            String newValueStr = idpList.stream()
                                    .map(id -> "\"" + id + "\"")
                                    .collect(Collectors.joining(", ", "[", "]"));

                            log.debug("旧配置: {}, 新配置: {}", valueStr, newValueStr);
                            List<RuleReturn> newReturnsList = new ArrayList<>(currentReturns);
                            newReturnsList.set(i, RuleReturn.builder().name("SocialIDPs").value(newValueStr).build());
                            PatchOp patchOp = PatchOp.builder()
                                    .schemas(Collections.singletonList(PATCH_ON_SCHEMA))
                                    .operations(Collections.singletonList(
                                            Operations.builder()
                                                    .op(Operations.Op.Replace)
                                                    .path("return")
                                                    .value(newReturnsList)
                                                    .build())).build();

                            idc.patchRule(PatchRuleRequest.builder()
                                    .ruleId(rule.getId())
                                    .patchOp(patchOp)
                                    .build());
                            log.info("成功更新规则，已移除 IDP: {}", idpIdToRemove);
                        }
                        break;
                    }
                }
            }

        } catch (Exception e) {
            log.error("remove fail: {}", e.getMessage(), e);
            throw new RuntimeException("remove fail");
        }
    }

    /**
     * 三方登录
     */
    public static String enableSocialLogin(Tenant tenant, OciSocialType socialType, String clientId, String clientSecret) {
        String providerName = socialType.getServiceProviderName();
        String filterString = String.format("serviceProviderName eq \"%s\"", providerName);
        try(IdentityDomainsClient idc= initIdentityDomainsClient(tenant)) {
            ListSocialIdentityProvidersResponse listResp = idc.listSocialIdentityProviders(
                    ListSocialIdentityProvidersRequest.builder()
                            .filter(filterString)
                            .limit(1)
                            .build());

            List<SocialIdentityProvider> resources = Collections.emptyList();
            if (listResp.getSocialIdentityProviders() != null
                    && listResp.getSocialIdentityProviders().getResources() != null) {
                resources = listResp.getSocialIdentityProviders().getResources();
            }
            if (resources.isEmpty()) {
                SocialIdentityProvider body = SocialIdentityProvider.builder()
                        .schemas(Collections.singletonList(SOCIAL_IDP_SCHEMA))
                        .name(providerName)
                        .serviceProviderName(providerName)
                        .enabled(true)
                        .showOnLogin(true)
                        .accountLinkingEnabled(true)
                        .registrationEnabled(false)
                        .consumerKey(clientId)
                        .consumerSecret(clientSecret)
                        .scope(Arrays.asList("openid", "email", "profile"))
                        .build();

                CreateSocialIdentityProviderResponse createResp =
                        idc.createSocialIdentityProvider(
                                CreateSocialIdentityProviderRequest.builder()
                                        .socialIdentityProvider(body)
                                        .build()
                        );
                SocialIdentityProvider created = createResp.getSocialIdentityProvider();
                doAddIdpRuleAndAddApp(idc,tenant,created);
                return getSocialCallbackUrl(idc.getEndpoint());
            }
            SocialIdentityProvider existing = resources.get(0);
            SocialIdentityProvider updated = updateIdpParams(idc, existing.getId(), clientId, clientSecret);
            doAddIdpRuleAndAddApp(idc,tenant,updated);
            return getSocialCallbackUrl(idc.getEndpoint());
        } catch (Exception e) {
            log.error("Google 登录配置失败: {}", e.getMessage(), e);
            return null;
        }
    }

    private static void doAddIdpRuleAndAddApp(IdentityDomainsClient idc, Tenant tenant, SocialIdentityProvider socialIdentityProvider) {
        try {
            String googleIdpId = socialIdentityProvider.getId();
            log.debug("开始配置 IDP 规则与应用绑定...");
            String targetPolicyId = StringUtils.EMPTY;
            ListRulesResponse rulesResp = idc.listRules(
                    ListRulesRequest.builder()
                            .filter("id eq \"" + DEFAULT_IDP_RULE_ID + "\"")
                            .limit(1)
                            .build()
            );

            if (rulesResp.getRules().getResources() != null && !rulesResp.getRules().getResources().isEmpty()) {
                Rule rule = rulesResp.getRules().getResources().get(0);
                List<RuleReturn> currentReturns = rule.getRuleReturn();
                if (currentReturns == null) currentReturns = new ArrayList<>();
                RuleReturn socialIdpsReturn = null;
                int index = -1;
                for (int i = 0; i < currentReturns.size(); i++) {
                    if ("SocialIDPs".equals(currentReturns.get(i).getName())) {
                        socialIdpsReturn = currentReturns.get(i);
                        index = i;
                        break;
                    }
                }

                if (socialIdpsReturn != null) {
                    String valueStr = socialIdpsReturn.getValue();
                    if (!valueStr.contains(googleIdpId)) {
                        log.debug("在规则中未发现 Google ID，正在添加...");
                        String inner = valueStr.replace("[", "").replace("]", "").trim();
                        String newValueStr;
                        if (inner.isEmpty()) {
                            newValueStr = String.format("[\"%s\"]", googleIdpId);
                        } else {
                            newValueStr = String.format("[%s, \"%s\"]", inner, googleIdpId);
                        }

                        List<RuleReturn> newReturnsList = new ArrayList<>(currentReturns);
                        RuleReturn newRuleReturn = RuleReturn.builder()
                                .name("SocialIDPs")
                                .value(newValueStr)
                                .build();

                        newReturnsList.set(index, newRuleReturn);
                        PatchOp patchOp = PatchOp.builder()
                                .schemas(Collections.singletonList(PATCH_ON_SCHEMA))
                                .operations(Collections.singletonList(
                                        Operations.builder()
                                                .op(Operations.Op.Replace)
                                                .path("return")
                                                .value(newReturnsList)
                                                .build())).build();
                        idc.patchRule(
                                PatchRuleRequest.builder()
                                        .ruleId(rule.getId())
                                        .patchOp(patchOp)
                                        .build()
                        );
                        log.debug("成功更新 Default IDP Rule，已勾选 Google。");
                    } else {
                        log.debug("Default IDP Rule 中已包含 Google，无需修改。");
                    }
                }
            } else {
                log.error("未找到规则: " + DEFAULT_IDP_RULE_ID);
                return;
            }
            String ociConsoleId = "OciConsole_APPID";
            ListAppsResponse appResp = idc.listApps(
                    ListAppsRequest.builder()
                            .filter("id eq \"" + ociConsoleId + "\"")
                            .limit(1)
                            .build()
            );

            ListPoliciesResponse policyResp = idc.listPolicies(
                    ListPoliciesRequest.builder()
                            .filter("id eq \"" + DEFAULT_IDP_POLICY_Id+ "\"")
                            .limit(1)
                            .build()
            );
            if (policyResp.getPolicies().getResources() != null && !policyResp.getPolicies().getResources().isEmpty()) {
                targetPolicyId = policyResp.getPolicies().getResources().get(0).getId();
                log.debug("已通过 API 查询到策略 ID: {}", targetPolicyId);
            } else {
                log.warn("未按名称查到策略，将尝试使用默认 ID: {}", targetPolicyId);
            }

            if (appResp.getApps().getResources() != null && !appResp.getApps().getResources().isEmpty()) {
                App app = appResp.getApps().getResources().get(0);
                boolean needBind = true;
                if (app.getIdpPolicy() != null && targetPolicyId.equals(app.getIdpPolicy().getValue())) {
                    needBind = false;
                    log.debug("App 已经绑定了正确的策略 ({})，无需操作。", targetPolicyId);
                }
                if (needBind) {
                    log.debug("准备将 App ({}) 绑定到 Policy ({})", app.getId(), targetPolicyId);
                    AppIdpPolicy policyRef = AppIdpPolicy.builder()
                            .value(targetPolicyId)
                            .build();
                    PatchOp patchOp = PatchOp.builder()
                            .schemas(Collections.singletonList(PATCH_ON_SCHEMA))
                            .operations(Collections.singletonList(
                                    Operations.builder()
                                            .op(Operations.Op.Replace)
                                            .path("idpPolicy")
                                            .value(policyRef)
                                            .build())).build();
                    idc.patchApp(PatchAppRequest.builder()
                                    .appId(app.getId())
                                    .patchOp(patchOp)
                                    .build());
                    log.debug("成功！已参考控制台逻辑完成 App 绑定。");
                }
            } else {
                log.error("应用不存在: ");
            }
        } catch (Exception e) {
            log.error("doAddIdpRuleAndAddApp 执行失败: {}", e.getMessage(), e);
        }
    }

    public static SocialIdentityProvider updateIdpParams(IdentityDomainsClient idc, String idpId, String clientId, String clientSecret) {
        try {
            List<Operations> operations = new ArrayList<>();
            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("enabled")
                    .value(true)
                    .build());
            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("showOnLogin")
                    .value(true)
                    .build());

            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("accountLinkingEnabled")
                    .value(true)
                    .build());

            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("registrationEnabled")
                    .value(false) // 不允许自动注册
                    .build());
            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("consumerKey")
                    .value(clientId)
                    .build());

            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("consumerSecret")
                    .value(clientSecret)
                    .build());
            operations.add(Operations.builder()
                    .op(Operations.Op.Replace)
                    .path("scope")
                    .value(Arrays.asList("openid", "email", "profile"))
                    .build());
            PatchOp patchOp = PatchOp.builder()
                    .schemas(Collections.singletonList(PATCH_ON_SCHEMA))
                    .operations(operations)
                    .build();
            PatchSocialIdentityProviderRequest request = PatchSocialIdentityProviderRequest.builder()
                    .socialIdentityProviderId(idpId)
                    .patchOp(patchOp)
                    .build();
            PatchSocialIdentityProviderResponse response = idc.patchSocialIdentityProvider(request);
            return response.getSocialIdentityProvider();
        } catch (Exception e) {
            log.error("更新 IdP 配置失败: {}", e.getMessage(), e);
        }
        return null;
    }

    public static String getSocialCallbackUrl(String domainEndpoint) {
        if (domainEndpoint == null || domainEndpoint.isEmpty()) {
            return null;
        }
        String baseUrl = domainEndpoint.replace(":443", "");
        if (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        return baseUrl + "/oauth2/v1/social/callback";
    }
}
