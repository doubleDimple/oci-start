package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociserver.pojo.domain.dto.OciClassLoaderPojo;
import com.doubledimple.ociserver.utils.oracle.OciClassLoader;
import com.doubledimple.ociserver.pojo.request.SecurityRuleDTO;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.SecurityRuleService;
import com.doubledimple.ociserver.utils.oracle.OciUtils;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.*;
import com.oracle.bmc.core.requests.ListSecurityListsRequest;
import com.oracle.bmc.core.requests.UpdateSecurityListRequest;
import com.oracle.bmc.core.responses.ListSecurityListsResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

/**
 * @author doubleDimple
 * @date 2024:11:28
 */
@Service
@Slf4j
public class SecurityRuleServiceImpl implements SecurityRuleService {

    @Resource
    private TenantRepository tenantRepository;

    @Resource
    private OciClassLoader ociClassLoader;

    @Override
    public List<SecurityRuleDTO> getSecurityRules(String tenantId, String type) {
        List<SecurityRuleDTO> rules = new ArrayList<>();
        // 获取租户信息
        Tenant tenant = tenantRepository.findById(Long.valueOf(tenantId))
                .orElseThrow(() -> new RuntimeException("Tenant not found"));
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try(VirtualNetworkClient vcnClient =VirtualNetworkClient.builder().build(provider)) {
            // 创建OCI客户端
            String compartmentId = provider.getTenantId(); // 使用租户的compartmentId

            ListSecurityListsRequest listRequest = ListSecurityListsRequest.builder()
                    .compartmentId(compartmentId)
                    .build();

            ListSecurityListsResponse response = vcnClient.listSecurityLists(listRequest);

            // 处理安全规则
            for (SecurityList securityList : response.getItems()) {
                if ("ingress".equals(type)) {
                    securityList.getIngressSecurityRules().forEach(rule -> {
                        SecurityRuleDTO dto = convertToDTO(rule, "入站");
                        rules.add(dto);
                    });
                } else {
                    securityList.getEgressSecurityRules().forEach(rule -> {
                        SecurityRuleDTO dto = convertToDTO(rule, "出站");
                        rules.add(dto);
                    });
                }
            }
        } catch (RuntimeException e) {
            log.warn("query rule security fail:{}", e.getMessage());
        }
        return rules;
    }

    @Override
    public SecurityRuleDTO addSecurityRule(SecurityRuleDTO ruleDTO) {
        Tenant tenant = tenantRepository.findById(ruleDTO.getTenantId())
                .orElseThrow(() -> new RuntimeException("Tenant not found"));

        addSecurityBaseRule(tenant, ruleDTO);

        return ruleDTO;
    }

    /**
     * 添加协议规则 - 自动删除重复规则后重新添加
     */
    public void addSecurityBaseRule(Tenant tenant, SecurityRuleDTO ruleDTO) {
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try(VirtualNetworkClient vcnClient = VirtualNetworkClient.builder().build(provider)) {
            // 获取当前安全列表
            String compartmentId = provider.getTenantId();
            ListSecurityListsRequest listRequest = ListSecurityListsRequest.builder()
                    .compartmentId(compartmentId)
                    .build();

            ListSecurityListsResponse response = vcnClient.listSecurityLists(listRequest);
            SecurityList securityList = response.getItems().get(0); // 获取默认安全列表

            if ("ingress".equals(ruleDTO.getType())) {
                addIngressRuleWithReplace(vcnClient, securityList, ruleDTO);
            } else {
                addEgressRuleWithReplace(vcnClient, securityList, ruleDTO);
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /**
     * 添加入站规则 - 删除重复后重新添加
     */
    private void addIngressRuleWithReplace(VirtualNetworkClient vcnClient, SecurityList securityList, SecurityRuleDTO ruleDTO) {
        List<IngressSecurityRule> currentRules = new ArrayList<>(securityList.getIngressSecurityRules());
        IngressSecurityRule newRule = createIngressRule(ruleDTO);

        // 找到所有匹配的规则 - 按照协议、源地址、端口匹配
        List<Integer> duplicateIndices = new ArrayList<>();
        for (int i = 0; i < currentRules.size(); i++) {
            if (isIngressRuleMatch(currentRules.get(i), newRule)) {
                duplicateIndices.add(i);
            }
        }

        // 删除重复的规则 (从后往前删除以保持索引准确)
        if (!duplicateIndices.isEmpty()) {
            for (int i = duplicateIndices.size() - 1; i >= 0; i--) {
                currentRules.remove(duplicateIndices.get(i).intValue());
            }
            log.info("删除了 {} 条重复的入站规则，索引位置: {}", duplicateIndices.size(), duplicateIndices);
        }

        // 添加新规则
        currentRules.add(newRule);
        log.debug("添加新的入站规则: Protocol={}, Source={}, Port={}",
                getProtocolName(newRule.getProtocol()),
                newRule.getSource(),
                getPortInfo(newRule));

        // 更新安全列表
        UpdateSecurityListRequest updateRequest = UpdateSecurityListRequest.builder()
                .securityListId(securityList.getId())
                .updateSecurityListDetails(
                        UpdateSecurityListDetails.builder()
                                .ingressSecurityRules(currentRules)
                                .build()
                )
                .build();

        vcnClient.updateSecurityList(updateRequest);
    }

    /**
     * 添加出站规则 - 删除重复后重新添加
     */
    private void addEgressRuleWithReplace(VirtualNetworkClient vcnClient, SecurityList securityList, SecurityRuleDTO ruleDTO) {
        List<EgressSecurityRule> currentRules = new ArrayList<>(securityList.getEgressSecurityRules());
        EgressSecurityRule newRule = createEgressRule(ruleDTO);

        // 找到所有匹配的规则 - 按照协议、目标地址、端口匹配
        List<Integer> duplicateIndices = new ArrayList<>();
        for (int i = 0; i < currentRules.size(); i++) {
            if (isEgressRuleMatch(currentRules.get(i), newRule)) {
                duplicateIndices.add(i);
            }
        }

        // 删除重复的规则 (从后往前删除以保持索引准确)
        if (!duplicateIndices.isEmpty()) {
            for (int i = duplicateIndices.size() - 1; i >= 0; i--) {
                currentRules.remove(duplicateIndices.get(i).intValue());
            }
            log.info("删除了 {} 条重复的出站规则，索引位置: {}", duplicateIndices.size(), duplicateIndices);
        }

        // 添加新规则
        currentRules.add(newRule);
        log.info("添加新的出站规则: Protocol={}, Destination={}, Port={}",
                getProtocolName(newRule.getProtocol()),
                newRule.getDestination(),
                getPortInfo(newRule));

        // 更新安全列表
        UpdateSecurityListRequest updateRequest = UpdateSecurityListRequest.builder()
                .securityListId(securityList.getId())
                .updateSecurityListDetails(
                        UpdateSecurityListDetails.builder()
                                .egressSecurityRules(currentRules)
                                .build()
                )
                .build();

        vcnClient.updateSecurityList(updateRequest);
    }

    @Override
    public ApiResponse enableAllForAllTenants() {
        return null;
    }

    @Override
    public void deleteSecurityRule(String compositeId) {
        // 解析复合ID
        String[] parts = compositeId.split("_");
        String tenantId = parts[0];
        int ruleIndex = Integer.parseInt(parts[1]);
        String type = parts[2];

        // 获取租户信息
        Tenant tenant = tenantRepository.findById(Long.valueOf(tenantId))
                .orElseThrow(() -> new RuntimeException("Tenant not found"));

        // 获取安全列表
        SimpleAuthenticationDetailsProvider provider = OciUtils.getProvider(tenant);

        try(VirtualNetworkClient vcnClient = VirtualNetworkClient.builder().build(provider)) {
            // 获取当前安全列表
            String compartmentId = provider.getTenantId();
            ListSecurityListsRequest listRequest = ListSecurityListsRequest.builder()
                    .compartmentId(compartmentId)
                    .build();

            ListSecurityListsResponse response = vcnClient.listSecurityLists(listRequest);

            // 遍历所有安全列表，找到对应的规则
            if ("ingress".equals(type)) {
                deleteIngressRuleByGlobalIndex(vcnClient, response.getItems(), ruleIndex);
            } else if ("egress".equals(type)) {
                deleteEgressRuleByGlobalIndex(vcnClient, response.getItems(), ruleIndex);
            } else {
                throw new IllegalArgumentException("Invalid rule type: " + type);
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to delete security rule", e);
        }
    }

    /**
     * 根据全局索引删除入站规则
     */
    private void deleteIngressRuleByGlobalIndex(VirtualNetworkClient vcnClient,
                                                List<SecurityList> securityLists,
                                                int globalIndex) {
        int currentIndex = 0;

        // 遍历所有安全列表，找到包含目标索引的安全列表
        for (SecurityList securityList : securityLists) {
            List<IngressSecurityRule> rules = securityList.getIngressSecurityRules();

            if (currentIndex + rules.size() > globalIndex) {
                // 目标规则在当前安全列表中
                int localIndex = globalIndex - currentIndex;

                log.debug("在安全列表 {} 中找到目标规则，本地索引: {}",
                        securityList.getId(), localIndex);

                deleteMatchingIngressRulesInSecurityList(vcnClient, securityList, localIndex);
                return;
            }

            currentIndex += rules.size();
        }

        // 如果到这里说明索引超出范围
        throw new IllegalArgumentException(
                String.format("规则索引 %d 超出范围，总规则数: %d", globalIndex, currentIndex));
    }

    /**
     * 根据全局索引删除出站规则
     */
    private void deleteEgressRuleByGlobalIndex(VirtualNetworkClient vcnClient,
                                               List<SecurityList> securityLists,
                                               int globalIndex) {
        int currentIndex = 0;

        // 遍历所有安全列表，找到包含目标索引的安全列表
        for (SecurityList securityList : securityLists) {
            List<EgressSecurityRule> rules = securityList.getEgressSecurityRules();

            if (currentIndex + rules.size() > globalIndex) {
                // 目标规则在当前安全列表中
                int localIndex = globalIndex - currentIndex;

                log.debug("在安全列表 {} 中找到目标规则，本地索引: {}",
                        securityList.getId(), localIndex);

                deleteMatchingEgressRulesInSecurityList(vcnClient, securityList, localIndex);
                return;
            }

            currentIndex += rules.size();
        }

        // 如果到这里说明索引超出范围
        throw new IllegalArgumentException(
                String.format("规则索引 %d 超出范围，总规则数: %d", globalIndex, currentIndex));
    }

    /**
     * 在指定安全列表中删除匹配的入站规则
     */
    private void deleteMatchingIngressRulesInSecurityList(VirtualNetworkClient vcnClient,
                                                          SecurityList securityList,
                                                          int localIndex) {
        List<IngressSecurityRule> currentRules = new ArrayList<>(securityList.getIngressSecurityRules());

        // 检查本地索引是否有效
        if (localIndex < 0 || localIndex >= currentRules.size()) {
            throw new IllegalArgumentException(
                    String.format("本地索引 %d 无效，当前安全列表规则数量: %d",
                            localIndex, currentRules.size()));
        }

        // 获取目标规则
        IngressSecurityRule targetRule = currentRules.get(localIndex);

        log.debug("准备删除入站规则，协议: {}, 源地址: {}, 端口: {}",
                getProtocolName(targetRule.getProtocol()),
                targetRule.getSource(),
                getPortInfo(targetRule));

        // 找出所有匹配的规则并删除
        List<IngressSecurityRule> filteredRules = new ArrayList<>();
        int deletedCount = 0;

        for (IngressSecurityRule rule : currentRules) {
            if (!isIngressRuleMatch(rule, targetRule)) {
                filteredRules.add(rule);
            } else {
                deletedCount++;
            }
        }

        log.debug("在安全列表 {} 中删除了 {} 条匹配的入站规则",
                securityList.getId(), deletedCount);

        // 更新安全列表
        UpdateSecurityListRequest updateRequest = UpdateSecurityListRequest.builder()
                .securityListId(securityList.getId())
                .updateSecurityListDetails(
                        UpdateSecurityListDetails.builder()
                                .ingressSecurityRules(filteredRules)
                                .build())
                .build();

        vcnClient.updateSecurityList(updateRequest);
    }

    /**
     * 在指定安全列表中删除匹配的出站规则
     */
    private void deleteMatchingEgressRulesInSecurityList(VirtualNetworkClient vcnClient,
                                                         SecurityList securityList,
                                                         int localIndex) {
        List<EgressSecurityRule> currentRules = new ArrayList<>(securityList.getEgressSecurityRules());

        // 检查本地索引是否有效
        if (localIndex < 0 || localIndex >= currentRules.size()) {
            throw new IllegalArgumentException(
                    String.format("本地索引 %d 无效，当前安全列表规则数量: %d",
                            localIndex, currentRules.size()));
        }

        // 获取目标规则
        EgressSecurityRule targetRule = currentRules.get(localIndex);

        log.info("准备删除出站规则，协议: {}, 目标地址: {}, 端口: {}",
                getProtocolName(targetRule.getProtocol()),
                targetRule.getDestination(),
                getPortInfo(targetRule));

        // 找出所有匹配的规则并删除
        List<EgressSecurityRule> filteredRules = new ArrayList<>();
        int deletedCount = 0;

        for (EgressSecurityRule rule : currentRules) {
            if (!isEgressRuleMatch(rule, targetRule)) {
                filteredRules.add(rule);
            } else {
                deletedCount++;
            }
        }

        log.debug("在安全列表 {} 中删除了 {} 条匹配的出站规则",
                securityList.getId(), deletedCount);

        // 更新安全列表
        UpdateSecurityListRequest updateRequest = UpdateSecurityListRequest.builder()
                .securityListId(securityList.getId())
                .updateSecurityListDetails(
                        UpdateSecurityListDetails.builder()
                                .egressSecurityRules(filteredRules)
                                .build())
                .build();

        vcnClient.updateSecurityList(updateRequest);
    }

    /**
     * 入站规则匹配逻辑：协议 + 源地址 + 端口
     */
    private boolean isIngressRuleMatch(IngressSecurityRule rule1, IngressSecurityRule rule2) {
        // 协议必须匹配
        if (!Objects.equals(rule1.getProtocol(), rule2.getProtocol())) {
            return false;
        }

        // 源地址必须匹配
        if (!Objects.equals(rule1.getSource(), rule2.getSource())) {
            return false;
        }

        // 根据协议类型匹配端口选项
        String protocol = rule1.getProtocol();

        switch (protocol) {
            case "6": // TCP
                return tcpOptionsMatch(rule1.getTcpOptions(), rule2.getTcpOptions());
            case "17": // UDP
                return udpOptionsMatch(rule1.getUdpOptions(), rule2.getUdpOptions());
            case "1": // ICMP
                return icmpOptionsMatch(rule1.getIcmpOptions(), rule2.getIcmpOptions());
            case "all":
                // "all" 协议不需要检查端口选项
                return true;
            default:
                // 其他协议也不检查端口
                return true;
        }
    }

    /**
     * 出站规则匹配逻辑：协议 + 目标地址 + 端口
     */
    private boolean isEgressRuleMatch(EgressSecurityRule rule1, EgressSecurityRule rule2) {
        // 协议必须匹配
        if (!Objects.equals(rule1.getProtocol(), rule2.getProtocol())) {
            return false;
        }

        // 目标地址必须匹配
        if (!Objects.equals(rule1.getDestination(), rule2.getDestination())) {
            return false;
        }

        // 根据协议类型匹配端口选项
        String protocol = rule1.getProtocol();

        switch (protocol) {
            case "6": // TCP
                return tcpOptionsMatch(rule1.getTcpOptions(), rule2.getTcpOptions());
            case "17": // UDP
                return udpOptionsMatch(rule1.getUdpOptions(), rule2.getUdpOptions());
            case "1": // ICMP
                return icmpOptionsMatch(rule1.getIcmpOptions(), rule2.getIcmpOptions());
            case "all":
                // "all" 协议不需要检查端口选项
                return true;
            default:
                // 其他协议也不检查端口
                return true;
        }
    }

    /**
     * TCP 选项匹配
     */
    private boolean tcpOptionsMatch(TcpOptions tcp1, TcpOptions tcp2) {
        if (tcp1 == null && tcp2 == null) return true;
        if (tcp1 == null || tcp2 == null) return false;

        return Objects.equals(tcp1.getDestinationPortRange(), tcp2.getDestinationPortRange()) &&
                Objects.equals(tcp1.getSourcePortRange(), tcp2.getSourcePortRange());
    }

    /**
     * UDP 选项匹配
     */
    private boolean udpOptionsMatch(UdpOptions udp1, UdpOptions udp2) {
        if (udp1 == null && udp2 == null) return true;
        if (udp1 == null || udp2 == null) return false;

        return Objects.equals(udp1.getDestinationPortRange(), udp2.getDestinationPortRange()) &&
                Objects.equals(udp1.getSourcePortRange(), udp2.getSourcePortRange());
    }

    /**
     * ICMP 选项匹配
     */
    private boolean icmpOptionsMatch(IcmpOptions icmp1, IcmpOptions icmp2) {
        if (icmp1 == null && icmp2 == null) return true;
        if (icmp1 == null || icmp2 == null) return false;

        return Objects.equals(icmp1.getType(), icmp2.getType()) &&
                Objects.equals(icmp1.getCode(), icmp2.getCode());
    }

    /**
     * 获取端口信息用于日志
     */
    private String getPortInfo(Object rule) {
        if (rule instanceof IngressSecurityRule) {
            IngressSecurityRule ingressRule = (IngressSecurityRule) rule;
            if (ingressRule.getTcpOptions() != null && ingressRule.getTcpOptions().getDestinationPortRange() != null) {
                return formatPortRange(ingressRule.getTcpOptions().getDestinationPortRange());
            }
            if (ingressRule.getUdpOptions() != null && ingressRule.getUdpOptions().getDestinationPortRange() != null) {
                return formatPortRange(ingressRule.getUdpOptions().getDestinationPortRange());
            }
            if (ingressRule.getIcmpOptions() != null) {
                return "ICMP Type: " + ingressRule.getIcmpOptions().getType();
            }
        } else if (rule instanceof EgressSecurityRule) {
            EgressSecurityRule egressRule = (EgressSecurityRule) rule;
            if (egressRule.getTcpOptions() != null && egressRule.getTcpOptions().getDestinationPortRange() != null) {
                return formatPortRange(egressRule.getTcpOptions().getDestinationPortRange());
            }
            if (egressRule.getUdpOptions() != null && egressRule.getUdpOptions().getDestinationPortRange() != null) {
                return formatPortRange(egressRule.getUdpOptions().getDestinationPortRange());
            }
            if (egressRule.getIcmpOptions() != null) {
                return "ICMP Type: " + egressRule.getIcmpOptions().getType();
            }
        }
        return "All Ports";
    }

    /**
     * 格式化端口范围
     */
    private String formatPortRange(PortRange portRange) {
        if (Objects.equals(portRange.getMin(), portRange.getMax())) {
            return portRange.getMin().toString();
        } else {
            return portRange.getMin() + "-" + portRange.getMax();
        }
    }

    /**
     * 获取协议名称
     */
    private String getProtocolName(String protocol) {
        switch (protocol) {
            case "1": return "ICMP";
            case "6": return "TCP";
            case "17": return "UDP";
            case "all": return "ALL";
            default: return "Protocol-" + protocol;
        }
    }

    /**
     * 批量开启icmp协议
     */
    @Override
    @Transactional
    public ApiResponse batchAllSecurityRule(String protocol) {
        List<Tenant> all = tenantRepository.findAll();
        for (Tenant tenant : all) {
            checkAndEnableRule(tenant);
        }
        return ApiResponse.success();
    }

    @Override
    public ApiResponse checkAndEnableRule(Tenant tenant) {
        try {
            // 获取当前租户的入站规则
            List<SecurityRuleDTO> ingressRules = getSecurityRules(String.valueOf(tenant.getId()), "ingress");
            // 获取当前租户的出站规则
            List<SecurityRuleDTO> egressRules = getSecurityRules(String.valueOf(tenant.getId()), "egress");

            // 检查是否已存在入站的全协议规则
            boolean hasIngressAllProtocol = ingressRules.stream()
                    .anyMatch(rule -> "all".equals(rule.getProtocol()) && "0.0.0.0/0".equals(rule.getSource()));

            // 检查IPv6入站规则
            boolean hasIngressIPv6Protocol = ingressRules.stream()
                    .anyMatch(rule -> "all".equals(rule.getProtocol()) && "::/0".equals(rule.getSource()));

            // 检查是否已存在出站的全协议规则
            boolean hasEgressAllProtocol = egressRules.stream()
                    .anyMatch(rule -> "all".equals(rule.getProtocol()) && "0.0.0.0/0".equals(rule.getSource()));

            // 检查IPv6出站规则
            boolean hasEgressIPv6Protocol = egressRules.stream()
                    .anyMatch(rule -> "all".equals(rule.getProtocol()) && "::/0".equals(rule.getSource()));

            // 修改ICMP规则检查 - 检查是否存在任何ICMP协议的规则，不再检查具体类型
            boolean hasIngressIcmpFromInternet = ingressRules.stream()
                    .anyMatch(rule -> ("ICMP".equals(rule.getProtocol()) || "1".equals(rule.getProtocol()))
                            && "0.0.0.0/0".equals(rule.getSource()));

            boolean hasIngressIcmpFromLocal = ingressRules.stream()
                    .anyMatch(rule -> ("ICMP".equals(rule.getProtocol()) || "1".equals(rule.getProtocol()))
                            && "10.0.0.0/16".equals(rule.getSource()));

            boolean needsUpdate = false;

            // 添加入站规则（如果不存在）
            if (!hasIngressAllProtocol) {
                SecurityRuleDTO ingressRule = SecurityRuleDTO.builder()
                        .tenantId(tenant.getId())
                        .type("ingress")
                        .protocol("all")
                        .source("0.0.0.0/0")
                        .build();
                addSecurityRule(ingressRule);
                needsUpdate = true;
            }

            // 添加IPv6入站规则（如果不存在）
            if (!hasIngressIPv6Protocol) {
                SecurityRuleDTO ingressIPv6Rule = SecurityRuleDTO.builder()
                        .tenantId(tenant.getId())
                        .type("ingress")
                        .protocol("all")
                        .source("::/0")
                        .build();
                try {
                    addSecurityRule(ingressIPv6Rule);
                    needsUpdate = true;
                } catch (Exception e) {
                    log.warn("ipv6 入站规则添加失败");
                }
            }

            // 添加ICMP入站规则（只有在不存在时才添加）
            if (!hasIngressIcmpFromInternet) {
                SecurityRuleDTO icmpRuleInternet = SecurityRuleDTO.builder()
                        .tenantId(tenant.getId())
                        .type("ingress")
                        .protocol("ICMP")
                        .source("0.0.0.0/0")
                        .icmpType("8, 0") // 直接使用系统实际使用的值
                        .build();
                addSecurityRule(icmpRuleInternet);
                needsUpdate = true;
            }

            // 添加本地网络ICMP入站规则（只有在不存在时才添加）
            if (!hasIngressIcmpFromLocal) {
                SecurityRuleDTO icmpRuleLocal = SecurityRuleDTO.builder()
                        .tenantId(tenant.getId())
                        .type("ingress")
                        .protocol("ICMP")
                        .source("10.0.0.0/16")
                        .icmpType("8, 0") // 直接使用系统实际使用的值
                        .build();
                addSecurityRule(icmpRuleLocal);
                needsUpdate = true;
            }

            // 添加出站规则（如果不存在）
            if (!hasEgressAllProtocol) {
                SecurityRuleDTO egressRule = SecurityRuleDTO.builder()
                        .tenantId(tenant.getId())
                        .type("egress")
                        .protocol("all")
                        .source("0.0.0.0/0")
                        .build();
                addSecurityRule(egressRule);
                needsUpdate = true;
            }

            // 添加IPv6出站规则（如果不存在）
            if (!hasEgressIPv6Protocol) {
                SecurityRuleDTO egressIPv6Rule = SecurityRuleDTO.builder()
                        .tenantId(tenant.getId())
                        .type("egress")
                        .protocol("all")
                        .source("::/0")
                        .build();
                try {
                    addSecurityRule(egressIPv6Rule);
                    needsUpdate = true;
                } catch (Exception e) {
                    log.warn("ipv6 出站规则添加失败,原因为:{}", e.getMessage());
                }
            }

            // 只有当至少添加了一条规则时，才更新租户状态
            if (needsUpdate) {
                tenant.setEnableAllProtocol(true);
                tenantRepository.save(tenant);
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        return ApiResponse.success();
    }

    /**
     * @Description: 开启单个租户逇所有协议
     * @Param: [com.doubledimple.ociserver.domain.Tenant]
     * @return: com.doubledimple.ociserver.response.ApiResponse
     * @Author doubleDimple
     * @Date: 4/13/25 1:36 PM
     */
    @Override
    @Transactional
    public ApiResponse singleSecurityAllRule(Tenant tenant) {
        try {
            List<SecurityRuleDTO.SecurityRuleDTOBuilder> securityRuleDTOBuilders = Arrays.asList(
                    SecurityRuleDTO.builder()
                            .tenantId(tenant.getId())
                            .type("ingress")
                            .protocol("all")
                            .source("0.0.0.0/0"),
                    SecurityRuleDTO.builder()
                            .tenantId(tenant.getId())
                            .type("egress")
                            .protocol("all")
                            .source("0.0.0.0/0"));
            for (SecurityRuleDTO.SecurityRuleDTOBuilder securityRuleDTOBuilder : securityRuleDTOBuilders) {
                addSecurityRule(securityRuleDTOBuilder.build());
            }

            tenant.setEnableIcmp(true);
            tenant.setEnableAllProtocol(true);
            tenantRepository.save(tenant);
        } catch (Exception e) {
            log.error("当前租户:{}开启icmp失败", tenant.getUserName());
            return ApiResponse.error("开启icmp失败");
        }
        return ApiResponse.success();
    }

    @Override
    public ApiResponse singleIpv6Rule(Tenant tenant) {
        try {
            List<SecurityRuleDTO.SecurityRuleDTOBuilder> securityRuleDTOBuilders = Arrays.asList(
                    SecurityRuleDTO.builder()
                            .tenantId(tenant.getId())
                            .type("ingress")
                            .protocol("all")
                            .source("::/0"),
                    SecurityRuleDTO.builder()
                            .tenantId(tenant.getId())
                            .type("egress")
                            .protocol("all")
                            .source("::/0"));
            for (SecurityRuleDTO.SecurityRuleDTOBuilder securityRuleDTOBuilder : securityRuleDTOBuilders) {
                addSecurityRule(securityRuleDTOBuilder.build());
            }

            tenant.setEnableIcmp(true);
            tenant.setEnableAllProtocol(true);
            tenantRepository.save(tenant);
        } catch (Exception e) {
            log.error("当前租户:{}开启icmp失败", tenant.getUserName());
            return ApiResponse.error("开启icmp失败");
        }
        return ApiResponse.success();
    }

    private SecurityRuleDTO convertToDTO(IngressSecurityRule rule, String type) {
        SecurityRuleDTO dto = new SecurityRuleDTO();
        dto.setType(type);
        dto.setProtocol(rule.getProtocol());
        dto.setSource(rule.getSource());
        if (rule.getTcpOptions() != null) {
            PortRange portRange = rule.getTcpOptions().getDestinationPortRange();
            dto.setPorts(portRange.getMin() + "-" + portRange.getMax());
        }

        // 处理ICMP选项
        if (rule.getIcmpOptions() != null) {
            IcmpOptions icmpOptions = rule.getIcmpOptions();
            Integer icmpType = icmpOptions.getType();
            Integer icmpCode = icmpOptions.getCode();

            if (icmpType != null) {
                if (icmpCode != null) {
                    dto.setIcmpType(icmpType + ", " + icmpCode);
                } else {
                    dto.setIcmpType(String.valueOf(icmpType));
                }
            }
        }

        return dto;
    }

    private SecurityRuleDTO convertToDTO(EgressSecurityRule rule, String type) {
        SecurityRuleDTO dto = new SecurityRuleDTO();
        dto.setType(type);
        dto.setProtocol(rule.getProtocol());
        dto.setSource(rule.getDestination());

        if (rule.getTcpOptions() != null) {
            PortRange portRange = rule.getTcpOptions().getDestinationPortRange();
            dto.setPorts(portRange.getMin() + "-" + portRange.getMax());
        }

        return dto;
    }

    private EgressSecurityRule createEgressRule(SecurityRuleDTO dto) {
        EgressSecurityRule.Builder builder = EgressSecurityRule.builder()
                .protocol(getProtocolNumber(dto.getProtocol()))
                .destination(dto.getSource());

        // 处理"所有协议"选项
        if ("all".equals(dto.getProtocol())) {
            // 设置协议为"all"表示所有协议
            builder.protocol("all");
            builder.destination(dto.getSource());

            // 对于所有协议，不需要指定端口范围
            return builder.build();
        }
        // 根据协议类型设置不同的选项
        switch (dto.getProtocol().toLowerCase()) {
            case "tcp":
                builder.tcpOptions(parseTcpUdpOptions(dto.getPorts()));
                break;
            case "udp":
                builder.udpOptions(parseUdpOptions(dto.getPorts()));
                break;
            case "icmp":
                // ICMP 协议不需要端口选项
                builder.icmpOptions(IcmpOptions.builder()
                        .type(8)
                        .code(0)
                        .build());
                break;
            // 其他协议不设置特殊选项
        }

        return builder.build();
    }

    /**
     * 入站规则
     */
    private IngressSecurityRule createIngressRule(SecurityRuleDTO dto) {
        IngressSecurityRule.Builder source = IngressSecurityRule.builder()
                .protocol(getProtocolNumber(dto.getProtocol()))
                .source(dto.getSource());

        // 处理"所有协议"选项
        if ("all".equals(dto.getProtocol())) {
            // 设置协议为"all"表示所有协议
            source.protocol("all");
            source.source(dto.getSource());

            // 对于所有协议，不需要指定端口范围
            return source.build();
        }

        // 根据协议类型设置不同的选项
        switch (dto.getProtocol().toLowerCase()) {
            case "tcp":
                source.tcpOptions(parseTcpUdpOptions(dto.getPorts()));
                break;
            case "udp":
                source.udpOptions(parseUdpOptions(dto.getPorts()));
                break;
            case "icmp":
                // ICMP 协议不需要端口选项
                source.icmpOptions(IcmpOptions.builder()
                        .type(8)  // Echo Request, 用于 ping
                        .code(0)
                        .build());
                break;
            // 其他协议不设置特殊选项
        }

        return source.build();
    }

    // 转换协议名称为OCI需要的协议号
    private String getProtocolNumber(String protocol) {
        switch (protocol.toLowerCase()) {
            case "tcp":
                return "6";
            case "udp":
                return "17";
            case "icmp":
                return "1";
            default:
                return protocol; // 如果已经是数字，则直接返回
        }
    }

    // 解析TCP/UDP端口选项
    private TcpOptions parseTcpUdpOptions(String portsString) {
        // 如果端口为空，返回null
        if (portsString == null || portsString.trim().isEmpty()) {
            return null;
        }

        try {
            // 处理逗号分隔的多个端口或端口范围
            if (portsString.contains(",")) {
                // 多个端口的情况，只处理第一个
                // 注意：OCI API 不支持直接设置多个不连续的端口，这里简化处理
                portsString = portsString.split(",")[0].trim();
            }

            // 处理端口范围
            String[] ports = portsString.split("-");
            int minPort = Integer.parseInt(ports[0].trim());
            int maxPort = ports.length > 1 ? Integer.parseInt(ports[1].trim()) : minPort;

            return TcpOptions.builder()
                    .destinationPortRange(PortRange.builder()
                            .min(minPort)
                            .max(maxPort)
                            .build())
                    .build();
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Invalid port format: " + portsString, e);
        }
    }

    // 类似的方法用于UDP
    private UdpOptions parseUdpOptions(String portsString) {
        TcpOptions tcpOptions = parseTcpUdpOptions(portsString);
        if (tcpOptions == null) {
            return null;
        }

        return UdpOptions.builder()
                .destinationPortRange(tcpOptions.getDestinationPortRange())
                .build();
    }
}