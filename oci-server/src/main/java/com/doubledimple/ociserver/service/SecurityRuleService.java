package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociserver.pojo.request.SecurityRuleDTO;
import com.doubledimple.ocicommon.param.ApiResponse;

import java.util.List;

public interface SecurityRuleService {

    /**
     * 获取规则列表
     * @param tenantId
     * @param type
     * @return
     */
    public List<SecurityRuleDTO> getSecurityRules(String tenantId, String type);


    /**
     * 添加规则
     * @param ruleDTO
     * @return
     */
    public SecurityRuleDTO addSecurityRule(SecurityRuleDTO ruleDTO);


    /**
     * 删除规则
     * @param
     * @return
     */
    public void deleteSecurityRule(String id);

    /**
    * 批量开启icmp协议
    */
    ApiResponse batchAllSecurityRule(String protocol);

    /**
    * @Description: 检查并开启所有相关协议
    * @Param: [com.doubledimple.ociserver.domain.Tenant]
    * @return: com.doubledimple.ociserver.response.ApiResponse
    * @Author doubleDimple
    * @Date: 5/3/25 11:09 AM
    */
    ApiResponse checkAndEnableRule(Tenant tenant);

    ApiResponse singleSecurityAllRule(Tenant tenant);
    ApiResponse singleIpv6Rule(Tenant tenant);


    public void addSecurityBaseRule(Tenant tenant, SecurityRuleDTO ruleDTO);

    /**
    * 开启所有协议
    */
    ApiResponse enableAllForAllTenants();

}
