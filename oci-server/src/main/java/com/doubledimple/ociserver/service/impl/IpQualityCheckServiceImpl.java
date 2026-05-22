package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.OperatorEnum;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.utils.JschUtils;
import com.doubledimple.ocicommon.utils.PingResultParser;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import com.doubledimple.ociserver.pojo.request.IpSwitchRequest;
import com.doubledimple.ociserver.pojo.request.VPSConfig;
import com.doubledimple.ociserver.pojo.request.VPSConfigRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.pojo.response.InstanceDetailsRes;
import com.doubledimple.ociserver.service.IpQualityCheckService;
import com.doubledimple.ociserver.service.SecurityRuleService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.domain.Page;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static com.doubledimple.ocicommon.utils.JschUtils.generatePingScript;

/**
 * @version 1.0.0
 * ip质量检测
 */
@Service
@Slf4j
public class IpQualityCheckServiceImpl implements IpQualityCheckService {

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    private SystemConfigRepository systemConfigRepository;

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    SecurityRuleService securityRuleService;

    @Override
    public void checkAllInstancesIpQuality() {

        Map<String, InstanceDetailsRes> ipMaps = new HashMap<>();
        List<String> scriptsIps = new ArrayList<>();
        List<VPSConfig> vpsConfigs = checkConnection();
        if (vpsConfigs.size() == 0){
            log.warn("当前没有配置可以连接的ssh的运营商vps或者vps无法连接,不能执行ip质量检测");
            return;
        }

        log.info("开始执行ip质量检测");
        Page<InstanceDetailsRes> userPage = oracleInstanceService.getAllInstances(0, 1000,null);
        if (userPage != null && userPage.getContent().size() > 0){
             List<InstanceDetailsRes> content = userPage.getContent();
            for (InstanceDetailsRes instanceDetailsRes : content) {
                //需要判断当前api是否已经开启所有协议网络规则
                Optional<Tenant> byId = tenantRepository.findById(instanceDetailsRes.getTenantId());
                if (!byId.isPresent()){
                    continue;
                }
                if (!byId.get().getEnableIcmp()){
                    log.warn("当前租户:{}的api未开启网络规则,先执行icmp开启",instanceDetailsRes.getTenantId());
                    //执行规则开启
                    Tenant tenant = byId.get();
                    ApiResponse apiResponse = securityRuleService.singleSecurityAllRule(tenant);
                    if (!apiResponse.isSuccess()){
                        log.error("当前租户:{}开启协议失败,无法执行ip质量检测,原因为:{}",tenant.getUserName(),apiResponse.getMessage());
                        continue;
                    }
                }
                String publicIps = instanceDetailsRes.getPublicIps();
                 String[] split = publicIps.split(",");
                 for (String ip : split) {
                     if (ip.length() > 0){
                         ipMaps.put(ip,instanceDetailsRes);
                     }
                 }
            }
        }

        for (Map.Entry<String, InstanceDetailsRes> entry : ipMaps.entrySet()) {
            scriptsIps.add(entry.getKey());
        }

        Set<String> strings = doCheckIpQuiality(vpsConfigs, scriptsIps);

        //执行ip自动变更操作
        doAutoChangeIp(strings,ipMaps);
    }

    /**
    * ip自动切换
    */
    private void doAutoChangeIp(Set<String> strings,Map<String, InstanceDetailsRes> ipMaps) {
        if (strings.size() == 0){

            return;
        }
        for (String string : strings) {
            InstanceDetailsRes instanceDetailsRes = ipMaps.get(string);
            IpSwitchRequest request = new IpSwitchRequest();
            request.setTenantId(Long.valueOf(instanceDetailsRes.getId()));
            oracleInstanceService.switchToSpecificIpRange(request);
        }
    }

    private Set<String> doCheckIpQuiality(List<VPSConfig> vpsConfigs, List<String> scriptsIps) {
        // 使用Map统计每个IP在不同运营商中失败的次数
        Map<String, Integer> failCountMap = new HashMap<>();
        int totalProviders = vpsConfigs.size();

        for (VPSConfig vpsConfig : vpsConfigs) {
            log.info("运营商:{}开始执行ssh质量检测测试", vpsConfig.getType());
            ScriptResult scriptResult = JschUtils.executeScriptJsch(vpsConfig.getServerIp(), vpsConfig.getUsername(),
                    vpsConfig.getPassword(),vpsConfig.getSshPort(), generatePingScript(scriptsIps, 6));
            List<String> failedIPs = PingResultParser.getFailedIPs(scriptResult.getOutput());
            log.warn("运营商:[{}]检测出ip:[{}]不可达",vpsConfig.getType(),failedIPs);
            // 更新每个失败IP的计数
            for (String ip : failedIPs) {
                failCountMap.put(ip, failCountMap.getOrDefault(ip, 0) + 1);
            }
        }

        // 筛选出所有运营商都检测失败的IP
        Set<String> failIps = failCountMap.entrySet().stream()
                .filter(entry -> entry.getValue() == totalProviders) // 只有当失败次数等于运营商总数时才认为IP不可达
                .map(Map.Entry::getKey)
                .collect(Collectors.toSet());

        log.info("运营商执行ssh质量检测测试结束,共有{}个ip在所有运营商中均失败", failIps.size());

        return failIps;
    }

    private List<VPSConfig> checkConnection() {
        List<VPSConfig> vpsConfigs = new ArrayList<>();
        doAdd(getVPSConfig(OperatorEnum.TELECOM.getType()),OperatorEnum.TELECOM,vpsConfigs);
        doAdd(getVPSConfig(OperatorEnum.UNICOM.getType()),OperatorEnum.UNICOM,vpsConfigs);
        doAdd(getVPSConfig(OperatorEnum.MOBILE.getType()),OperatorEnum.MOBILE,vpsConfigs);

        return vpsConfigs;
    }

    private void doAdd(VPSConfig config,OperatorEnum operatorEnum, List<VPSConfig> vpsConfigs) {
        if (config != null && config.isEnabled()){
            //执行测试
            VPSConfigRequest request = new VPSConfigRequest();
            request.setUsername(config.getUsername());
            request.setPassword(config.getPassword());
            request.setServerIp(config.getServerIp());
            request.setSshPort(config.getSshPort());
            request.setType(operatorEnum.getType());
            config.setType(operatorEnum.getType());
            if (testSSHConnection(request)){
                vpsConfigs.add(config);
            }else {
                log.warn("当前配置运营商:{},的ip:{}的vps无法链接ssh",operatorEnum.getName(),config.getServerIp());
            }
        }
    }


    public VPSConfig getVPSConfig(String type) {
        VPSConfig config = new VPSConfig();
        String prefix = "vps." + type + ".";

        // 获取启用状态
        SystemConfig enabledConfig = systemConfigRepository.findByKey(prefix + "enabled")
                .orElse(new SystemConfig());
        config.setEnabled(enabledConfig.isEnabled());

        // 获取服务器IP
        SystemConfig ipConfig = systemConfigRepository.findByKey(prefix + "ip")
                .orElse(new SystemConfig());
        config.setServerIp(ipConfig.getValue());

        // 获取用户名
        SystemConfig usernameConfig = systemConfigRepository.findByKey(prefix + "username")
                .orElse(new SystemConfig());
        config.setUsername(usernameConfig.getValue() != null ? usernameConfig.getValue() : "root");

        // 获取密码
        SystemConfig passwordConfig = systemConfigRepository.findByKey(prefix + "password")
                .orElse(new SystemConfig());
        config.setPassword(passwordConfig.getValue());

        // 获取SSH端口
        SystemConfig portConfig = systemConfigRepository.findByKey(prefix + "ssh.port")
                .orElse(new SystemConfig());
        String portStr = portConfig.getValue();
        int port = 22; // 默认值
        if (portStr != null && !portStr.isEmpty()) {
            try {
                port = Integer.parseInt(portStr);
            } catch (NumberFormatException e) {
                log.warn("无法解析SSH端口值：{}", portStr);
            }
        }
        config.setSshPort(port);

        return config;
    }

    private boolean testSSHConnection(VPSConfigRequest request) {
        try {
            ScriptResult scriptResult = JschUtils.executeScriptJsch(request.getServerIp(), request.getUsername(), request.getPassword(),request.getSshPort(), "echo 'Hello, World!'");
            String error = scriptResult.getError();
            if (StringUtils.isNotBlank(error)){
                return false;
            }
            return true;
        } catch (Exception e) {
            log.error("SSH连接测试失败: {}", e.getMessage());
            return false;
        }
    }
}
