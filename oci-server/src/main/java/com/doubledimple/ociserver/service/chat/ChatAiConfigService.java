package com.doubledimple.ociserver.service.chat;

import com.doubledimple.dao.entity.ChatAiConfig;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.ChatAiConfigRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ocicommon.param.ChatAiConfigDto;
import org.springframework.beans.BeanUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

/*@Service
public class ChatAiConfigService {

    @Resource
    private ChatAiConfigRepository chatAiConfigRepository;

    @Resource
    private TenantRepository tenantRepository;

    // 添加新方法：根据cloudType获取所有配置（包括已选择的模型列表）
    public List<ChatAiConfigDto> getAllConfigsByCloudType(Integer cloudType) {
        Optional<List<ChatAiConfig>> configs = chatAiConfigRepository.findByCloudType(cloudType);
        return configs.map(this::convertToDto).orElse(new ArrayList<>());
    }

    // 添加根据ID删除配置的方法
    @Transactional
    public boolean deleteById(Long id) {
        if (chatAiConfigRepository.existsById(id)) {
            chatAiConfigRepository.deleteById(id);
            return true;
        }
        return false;
    }

    *//**
     * 根据云厂商类型获取配置
     *//*
    public Optional<List<ChatAiConfigDto>> getConfigByCloudType(Integer cloudType) {
        Optional<List<ChatAiConfig>> byCloudType = chatAiConfigRepository.findByCloudType(cloudType);
        return byCloudType.map(this::convertToDto);
    }

    *//**
     * 保存或更新配置
     *//*
    @Transactional
    public ChatAiConfigDto saveOrUpdateConfig(ChatAiConfigDto dto) {
        ChatAiConfig config;

        if (dto.getId() != null) {
            // 更新现有配置
            Optional<ChatAiConfig> existingConfig = chatAiConfigRepository.findById(dto.getId());
            if (existingConfig.isPresent()) {
                config = existingConfig.get();
                dto.setTenantId(config.getTenantId());
                dto.setModelId(config.getModelId());
                dto.setModelName(config.getModelName());
                dto.setProvider(config.getProvider());
                updateConfigFromDto(config, dto,null);
            } else {
                throw new RuntimeException("配置不存在，ID: " + dto.getId());
            }
        } else {
            // 创建新配置
            config = new ChatAiConfig();
            Long maxId = chatAiConfigRepository.findMaxId().orElse(1L);
            updateConfigFromDto(config, dto,maxId);
        }

        config = chatAiConfigRepository.save(config);
        return convertToDto(config);
    }

    *//**
     * 启用/禁用配置
     *//*
    @Transactional
    public boolean updateEnabled(Integer cloudType, Boolean enabled) {
        int updatedRows = chatAiConfigRepository.updateEnabledByCloudType(cloudType, enabled);
        return updatedRows > 0;
    }

    *//**
     * 检查配置是否存在
     *//*
    public boolean existsByCloudType(Integer cloudType) {
        return chatAiConfigRepository.existsByCloudType(cloudType);
    }


    *//**
     * 转换为DTO
     *//*
    private List<ChatAiConfigDto> convertToDto(List<ChatAiConfig> configs) {
        return configs.stream()
                .map(config -> {
                    ChatAiConfigDto chatAiConfigDto = new ChatAiConfigDto();
                    BeanUtils.copyProperties(config, chatAiConfigDto);
                    String tenantId = config.getTenantId();
                    if (tenantId == null) tenantId = "-1";
                    Optional<Tenant> byId = tenantRepository.findById(Long.valueOf(tenantId));
                    if (byId.isPresent()){
                        Tenant tenant = byId.get();
                        chatAiConfigDto.setRegion(RegionEnum.getNameSimple(tenant.getRegion()));
                        chatAiConfigDto.setUserName(tenant.getUserName());
                    }else{
                        chatAiConfigDto.setRegion("未知");
                        chatAiConfigDto.setUserName("未知");
                    }
                    return chatAiConfigDto;
                })
                .collect(Collectors.toList());
    }

    private ChatAiConfigDto convertToDto(ChatAiConfig config) {
        ChatAiConfigDto dto = new ChatAiConfigDto();
        BeanUtils.copyProperties(config, dto);
        return dto;
    }

    *//**
     * 从DTO更新实体
     *//*
    private void updateConfigFromDto(ChatAiConfig config, ChatAiConfigDto dto,Long maxId) {
        config.setTenantId(dto.getTenantId());
        config.setModelId(dto.getModelId());
        config.setCloudType(dto.getCloudType());
        config.setModelName(dto.getModelName());
        config.setProvider(dto.getProvider());
        config.setApiKey(dto.getApiKey());
        config.setBaseUrl(dto.getBaseUrl());
        config.setEnabled(dto.getEnabled());
        config.setSystemPrompt(dto.getSystemPrompt());
        config.setMaxTokens(dto.getMaxTokens());
        if (maxId != null){
            config.setShowModelId("oci-"+dto.getModelName()+"-"+maxId);
        }
        //config.setTemperature(dto.getTemperature());
        config.setMaxHistoryMessages(dto.getMaxHistoryMessages());
    }

    @Transactional
    public int batchUpdateConfigStatus(Boolean enabled) {
        return chatAiConfigRepository.updateEnabledByCloudType(1, enabled);
    }
}*/
