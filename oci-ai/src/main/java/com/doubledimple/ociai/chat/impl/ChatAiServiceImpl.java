package com.doubledimple.ociai.chat.impl;

import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.AiChatHistory;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.AiChatHistoryRepository;
import com.doubledimple.dao.repository.OracleInstanceDetailRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociai.chat.ChatAiConfigService;
import com.doubledimple.ociai.chat.ChatAiService;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.doubledimple.ocicommon.enums.ModelSelectionStrategy;
import com.doubledimple.ocicommon.param.AiChatResp;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.ChatAiConfigDto;
import com.doubledimple.ocicommon.param.ChatMessage;
import com.doubledimple.ocicommon.param.Choice;
import com.doubledimple.ocicommon.param.OpenAIChatRequest;
import com.doubledimple.ocicommon.param.OpenAIChatResponse;
import com.doubledimple.ocicommon.param.Usage;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.context.i18n.LocaleContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.util.CollectionUtils;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import java.util.stream.Collectors;

import static com.doubledimple.ociai.constant.AiPromptConstants.buildAssetAuditPrompt;

/**
 * @version 1.0.0
 * @ClassName ChatAiServiceImpl
 * @Description AI聊天
 * @Author doubleDimple
 * @Date 2025-09-11 16:48
 */
@Slf4j
@Service
public class ChatAiServiceImpl implements ChatAiService {

    @Resource
    ThreadPoolExecutor aiChatExecutor;

    @Resource
    ChatAiConfigService configService;

    @Resource
    OciAiChatUtils aiUtils;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    private ChatAiConfigService chatAiConfigService;

    @Resource
    private ObjectMapper objectMapper;

    @Resource
    OracleInstanceDetailRepository oracleInstanceDetailRepository;

    @Resource
    AiChatHistoryRepository aiChatHistoryRepository;

    private final Map<String, AtomicInteger> modelUsageCounter = new ConcurrentHashMap<>(); // 模型使用计数器
    private final Map<String, Long> modelLastUsedTime = new ConcurrentHashMap<>(); // 模型最后使用时间

    // 当前使用的策略
    private ModelSelectionStrategy currentStrategy = ModelSelectionStrategy.LOAD_BALANCE;

    private final AtomicInteger roundRobinCounter = new AtomicInteger(0);


    @Override
    public CompletableFuture<ApiResponse> chat(String userId, String userMessage,String showModelId) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                // 获取所有可用的AI配置
                Optional<List<ChatAiConfigDto>> configOpt = configService.getConfigByCloudType(1);

                if (!configOpt.isPresent() || configOpt.get().isEmpty()) {
                    return ApiResponse.error("AI服务暂时不可用，请稍后重试");
                }

                // 过滤出启用的配置
                List<ChatAiConfigDto> enabledConfigs = configOpt.get().stream()
                        .filter(ChatAiConfigDto::getEnabled)
                        .collect(Collectors.toList());

                //截取modelName
                if (StringUtils.isNotBlank(showModelId)){
                    String modelName = showModelId.substring(4, showModelId.lastIndexOf("-"));
                    List<ChatAiConfigDto> collect = enabledConfigs.stream().filter(config -> config.getModelName().equals(modelName)).collect(Collectors.toList());
                    if (!CollectionUtils.isEmpty( collect)){
                        enabledConfigs = collect;
                    }
                }

                if (enabledConfigs.isEmpty()) {
                    return ApiResponse.error("AI服务暂时不可用，请稍后重试");
                }

                // 智能选择模型
                ChatAiConfigDto selectedConfig = selectOptimalModel(enabledConfigs, userId);
                if (selectedConfig == null) {
                    return ApiResponse.error("AI服务暂时不可用，请稍后重试");
                }

                // 记录模型使用
                recordModelUsage(selectedConfig.getModelId());

                // 添加用户消息到历史记录
                addUserAiMessage(userId, userMessage, selectedConfig.getModelId());

                // 获取租户信息
                Tenant tenant = tenantRepository.findById(Long.valueOf(selectedConfig.getTenantId())).orElse(null);
                if (tenant == null) {
                    return ApiResponse.error("配置错误，请联系管理员");
                }

                // 获取用户的AI对话历史（支持跨模型的连续对话）
                List<Map<String, String>> historyContext = getUserAiHistoryContext(userId);

                String aiResponse;
                long startTime = System.currentTimeMillis();

                try {
                    if (historyContext.size() <= 1) {
                        // 首次对话或只有一条消息
                        aiResponse = aiUtils.chat(tenant, userMessage, selectedConfig.getModelId());
                    } else {
                        // 有历史上下文的对话
                        aiResponse = aiUtils.chatWithHistory(tenant, historyContext, selectedConfig.getModelId(),null);
                    }
                } catch (Exception e) {
                    log.warn("模型 {} 调用失败，尝试备用模型: {}", selectedConfig.getModelId(), e.getMessage());

                    // 尝试使用备用模型
                    ChatAiConfigDto backupConfig = selectBackupModel(enabledConfigs, selectedConfig.getModelId());
                    if (backupConfig != null) {
                        try {
                            tenant = tenantRepository.findById(Long.valueOf(backupConfig.getTenantId())).orElse( null);
                            if (tenant == null) {
                                return ApiResponse.error("备用模型配置错误，请联系管理员");
                            }

                            if (historyContext.size() <= 1) {
                                aiResponse = aiUtils.chat(tenant, userMessage, backupConfig.getModelId());
                            } else {
                                aiResponse = aiUtils.chatWithHistory(tenant, historyContext, backupConfig.getModelId(),null);
                            }
                            selectedConfig = backupConfig;
                            recordModelUsage(backupConfig.getModelId());
                        } catch (Exception backupException) {
                            log.error("备用模型调用也失败: {}", backupException.getMessage(), backupException);
                            return ApiResponse.error("AI服务暂时不可用: " + backupException.getMessage());
                        }
                    } else {
                        log.error("没有可用的备用模型: {}", e.getMessage(), e);
                        return ApiResponse.error("AI服务暂时不可用: " + e.getMessage());
                    }
                }

                long responseTime = System.currentTimeMillis() - startTime;

                // 添加AI回复到历史记录
                addAssistantAiMessage(userId, aiResponse, selectedConfig.getModelId());

                String modelInfo = selectedConfig.getModelName() != null ?
                        selectedConfig.getModelName() : selectedConfig.getModelId();

                log.debug("AI对话完成 - 用户: {}, 模型: {}, 响应时间: {}ms, 上下文消息数: {}",
                        userId, modelInfo, responseTime, historyContext.size());
                if (StringUtils.isBlank(aiResponse)){
                    aiResponse = "抱歉，我无法回答你的问题。";
                }
                return ApiResponse.success(AiChatResp.builder().aiReply(aiResponse).build());

            } catch (Exception e) {
                log.error("AI对话处理失败: {}", e.getMessage(), e);
                return ApiResponse.error("抱歉，AI服务暂时不可用: " + e.getMessage());
            }
        }, aiChatExecutor);
    }

    /**
    * @Description: chatCompletions
    * @Param: [com.doubledimple.ociserver.openApi.request.OpenAIChatRequest, java.lang.String]
    * @return: java.util.concurrent.CompletableFuture<com.doubledimple.ociserver.openApi.response.OpenAIChatResponse>
    * @Author: doubleDimple
    * @Date: 9/13/25 8:59 AM
    */
    @Override
    public CompletableFuture<?> chatCompletions(OpenAIChatRequest request, String userId, HttpServletResponse httpResponse) {
        return handleNormalResponse(request, userId);
    }

    /**
    * @Description: handleStreamResponseSync
    * @Param: [com.doubledimple.ociserver.openApi.request.OpenAIChatRequest, java.lang.String, javax.servlet.http.HttpServletResponse]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/13/25 11:00 AM
    */
    @Override
    public void handleStreamResponseSync(OpenAIChatRequest request, String userId, HttpServletResponse response) {
        // 设置SSE响应头
        response.setContentType("text/event-stream");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Cache-Control", "no-cache");
        response.setHeader("Connection", "keep-alive");
        response.setHeader("Access-Control-Allow-Origin", "*");
        PrintWriter writer = null;
        try {
            writer = response.getWriter();
            // 获取用户消息
            String userMessage = request.getMessages().stream()
                    .filter(msg -> "user".equals(msg.getRole()))
                    .reduce((first, second) -> second)
                    .map(msg -> msg.getContent())
                    .orElse("");

            String showModelId = request.getModel();

            if (StringUtils.isBlank(userMessage)) {
                sendStreamError(writer, "用户消息不能为空");
                return;
            }

            // 同步调用聊天服务
            ApiResponse result = chat(userId, userMessage,showModelId).get(); // 同步等待结果

            String aiReply = "抱歉，我无法回答您的问题。";
            if (result.isSuccess() && result.getData() instanceof AiChatResp) {
                AiChatResp chatResp = (AiChatResp) result.getData();
                if (StringUtils.isNotBlank(chatResp.getAiReply())) {
                    aiReply = chatResp.getAiReply();
                }
            }

            // 发送流式响应
            sendStreamMessage(writer, request, aiReply);
            sendStreamEnd(writer, request);

        } catch (Exception e) {
            log.error("流式响应处理失败", e);
            if (writer != null){
                sendStreamError(writer, "服务器内部错误");
            }
        }
    }

    /**
    * @Description: 获取配置的可用模型
    * @Param: []
    * @return: java.util.Map<java.lang.String,java.lang.Object>
    * @Author: doubleDimple
    * @Date: 9/13/25 3:42 PM
    */
    @Override
    public Map<String, Object> enableModels() {
        Map<String, Object> response = new HashMap<>();
        response.put("object", "list");

        List<ChatAiConfigDto> configs = chatAiConfigService.getAllConfigsByCloudType(1);

        List<Map<String, Object>> modelList = new ArrayList<>();

        if (configs != null && !configs.isEmpty()) {
            for (ChatAiConfigDto config : configs) {
                // 只返回启用的模型
                if (config.getEnabled() != null && config.getEnabled()) {
                    Map<String, Object> model = new HashMap<>();
                    model.put("id", config.getShowModelId());
                    model.put("object", "model");
                    model.put("created", System.currentTimeMillis() / 1000);
                    model.put("owned_by", StringUtils.isNotBlank(config.getProvider()) ? config.getProvider() : "oci-start");
                    if (StringUtils.isNotBlank(config.getModelName())) {
                        model.put("description", config.getModelName());
                    }

                    modelList.add(model);
                }
            }
        }
        response.put("data", modelList);

        log.info("返回的可用模型是:{}", JSON.toJSONString(response));
        return response;
    }

    @Override
    public void analyzeAllTenantsStream(SseEmitter emitter, List<Tenant> allTenants) {
        Locale currentLocale = LocaleContextHolder.getLocale();
        String language = currentLocale.getLanguage();
        String targetLang = "Simplified Chinese";
        if ("en".equalsIgnoreCase(language)) {
            targetLang = "English";
        } else if ("zh".equalsIgnoreCase(language)) {
            // 如果是 zh，再细分简繁
            if (currentLocale.toString().contains("TW") || currentLocale.toString().contains("HK")) {
                targetLang = "繁体中文";
            }
        }
        String finalTargetLang = targetLang;
        CompletableFuture.runAsync(() -> {
            try {

                Optional<List<ChatAiConfigDto>> configOpt = configService.getConfigByCloudType(1);
                if (!configOpt.isPresent() || configOpt.get().isEmpty()) {
                    emitter.send(SseEmitter.event().data("data:AI配置缺失\n\n"));
                    emitter.complete();
                    return;
                }
                ChatAiConfigDto selectedConfig = configOpt.get().stream()
                        .filter(ChatAiConfigDto::getEnabled).findFirst().orElse(configOpt.get().get(0));
                Tenant aiTenant = tenantRepository.findById(Long.valueOf(selectedConfig.getTenantId())).orElse(null);

                List<Tenant> sortedTenants = new ArrayList<>(allTenants);
                sortedTenants.sort((a, b) -> {
                    boolean aUp = a.getAccountTypeName() != null && a.getAccountTypeName().contains("升级");
                    boolean bUp = b.getAccountTypeName() != null && b.getAccountTypeName().contains("升级");
                    if (aUp != bUp) return Boolean.compare(bUp, aUp);
                    int dA = 0; try { dA = Integer.parseInt(a.getActiveDays()); } catch (Exception ignored) {}
                    int dB = 0; try { dB = Integer.parseInt(b.getActiveDays()); } catch (Exception ignored) {}
                    return Integer.compare(dB, dA);
                });

                int rank = 1;
                for (Tenant t : sortedTenants) {
                    String defName = StringUtils.isNotBlank(t.getDefName()) ? t.getDefName() : "未命名租户";
                    emitter.send(SseEmitter.event().data(String.format(">>> loading %d/%d : [%s]...\n", rank, sortedTenants.size(), defName)));
                    List<InstanceDetails> instances = oracleInstanceDetailRepository.findByTenantId(t.getId());
                    long armCount = 0; int totalOcpus = 0; int totalMemory = 0; int onlineCount = 0; int offlineCount = 0;
                    if (instances != null) {
                        for (InstanceDetails ins : instances) {
                            boolean isArm = "ARM".equalsIgnoreCase(ins.getArchitecture()) || (ins.getProcessorDescription() != null && ins.getProcessorDescription().contains("Ampere"));
                            if (isArm) armCount++;
                            totalOcpus += (ins.getOcpus() != null ? ins.getOcpus() : 0);
                            totalMemory += (ins.getMemoryInGBs() != null ? ins.getMemoryInGBs() : 0);
                            if (ins.getOnLineEnable() != null && ins.getOnLineEnable() == 1) onlineCount++;
                            else offlineCount++;
                        }
                    }
                    String type = t.getAccountTypeName() != null ? t.getAccountTypeName() : "普通免费";
                    int currentRegions = (t.getChildren() != null ? t.getChildren().size() : 0) + 1;
                    String activeDays = StringUtils.isNotBlank(t.getActiveDays()) ? t.getActiveDays() : "0";
                    boolean isPayg = type.contains("升级") || type.contains("PAYG");
                    int daysInt = 0; try { daysInt = Integer.parseInt(activeDays); } catch (Exception ignored) {}
                    String singlePrompt = String.format(buildAssetAuditPrompt(), finalTargetLang, defName, type, activeDays, currentRegions, (instances != null ? instances.size() : 0), armCount, totalOcpus, totalMemory, onlineCount, offlineCount);
                    String review = aiUtils.chat(aiTenant, singlePrompt, selectedConfig.getModelId());
                    review = cleanAiReview(review);
                    if (!review.contains("¥")) {
                        int price = calculatePriceManual(isPayg, currentRegions, daysInt, (int)armCount, offlineCount);
                        review += String.format(" [估价：¥%d-%d]", (int)(price * 0.95), (int)(price * 1.05));
                    }
                    String riskTag = isPayg ? " [高权资产] " : (daysInt > 180 ? " [老牌稳健] " : (daysInt <= 30 ? " [高危风险] " : " [风控观察] "));
                    StringBuilder tags = new StringBuilder();
                    if (armCount > 0) tags.append("ARM×").append(armCount).append(" ");
                    if (isPayg) {
                        if (currentRegions > 3) tags.append("超配").append(currentRegions).append("区 ");
                        else tags.append("标准3区 ");
                    } else if (currentRegions > 1) {
                        tags.append("多区稀有号 ");
                    }
                    if (offlineCount > 0) tags.append("离线 ");
                    String line = String.format("%d. %s%s%s_%s | %dC/%dG | 点评: %s\n",
                            rank++, riskTag, tags.toString(), t.getUserName(), defName,
                            totalOcpus, totalMemory, review);

                    emitter.send(SseEmitter.event().data(line));
                    Thread.sleep(200);
                }
                emitter.send(SseEmitter.event().data("✔ 资产评估报告生成完毕。\n"));
                emitter.complete();
            } catch (Exception e) {
                log.error("审计异常", e);
                emitter.complete();
            }
        });
    }

    @Override
    public void chatStream(String userId, String userMessage, String showModelId, Consumer<String> chunkConsumer) {
        try {
            Optional<List<ChatAiConfigDto>> configOpt = configService.getConfigByCloudType(1);
            if (!configOpt.isPresent() || configOpt.get().isEmpty()) {
                chunkConsumer.accept("AI服务暂时不可用，请稍后重试");
                return;
            }

            List<ChatAiConfigDto> enabledConfigs = configOpt.get().stream()
                    .filter(ChatAiConfigDto::getEnabled)
                    .collect(Collectors.toList());

            if (StringUtils.isNotBlank(showModelId)) {
                String modelName = showModelId.substring(4, showModelId.lastIndexOf("-"));
                List<ChatAiConfigDto> collect = enabledConfigs.stream()
                        .filter(config -> config.getModelName().equals(modelName))
                        .collect(Collectors.toList());
                if (!CollectionUtils.isEmpty(collect)) {
                    enabledConfigs = collect;
                }
            }

            if (enabledConfigs.isEmpty()) {
                chunkConsumer.accept("AI服务暂时不可用，请稍后重试");
                return;
            }

            ChatAiConfigDto selectedConfig = selectOptimalModel(enabledConfigs, userId);
            if (selectedConfig == null) {
                chunkConsumer.accept("AI服务暂时不可用，请稍后重试");
                return;
            }

            recordModelUsage(selectedConfig.getModelId());
            addUserAiMessage(userId, userMessage, selectedConfig.getModelId());

            Tenant tenant = tenantRepository.findById(Long.valueOf(selectedConfig.getTenantId())).orElse(null);
            if (tenant == null) {
                chunkConsumer.accept("配置错误，请联系管理员");
                return;
            }

            List<Map<String, String>> historyContext = getUserAiHistoryContext(userId);
            String modelId = selectedConfig.getModelId();
            StringBuilder fullReply = new StringBuilder();

            Consumer<String> wrappedConsumer = chunk -> {
                fullReply.append(chunk);
                chunkConsumer.accept(chunk);
            };

            try {
                if (historyContext.size() <= 1) {
                    aiUtils.chatWithStream(tenant, userMessage, modelId, wrappedConsumer);
                } else {
                    aiUtils.chatWithHistoryStream(tenant, historyContext, modelId, wrappedConsumer, null);
                }
            } catch (Exception e) {
                log.warn("流式模型 {} 调用失败，尝试备用模型: {}", modelId, e.getMessage());

                ChatAiConfigDto backupConfig = selectBackupModel(enabledConfigs, modelId);
                if (backupConfig != null) {
                    try {
                        tenant = tenantRepository.findById(Long.valueOf(backupConfig.getTenantId())).orElse(null);
                        if (tenant == null) {
                            chunkConsumer.accept("备用模型配置错误");
                            return;
                        }
                        fullReply.setLength(0);
                        if (historyContext.size() <= 1) {
                            aiUtils.chatWithStream(tenant, userMessage, backupConfig.getModelId(), wrappedConsumer);
                        } else {
                            aiUtils.chatWithHistoryStream(tenant, historyContext, backupConfig.getModelId(), wrappedConsumer, null);
                        }
                        selectedConfig = backupConfig;
                        recordModelUsage(backupConfig.getModelId());
                    } catch (Exception backupEx) {
                        log.error("备用模型流式调用也失败: {}", backupEx.getMessage(), backupEx);
                        chunkConsumer.accept(" [AI服务异常]");
                        return;
                    }
                } else {
                    chunkConsumer.accept(" [AI服务异常]");
                    return;
                }
            }

            String finalReply = fullReply.toString();
            if (StringUtils.isNotBlank(finalReply)) {
                addAssistantAiMessage(userId, finalReply, selectedConfig.getModelId());
            }

            log.debug("流式AI对话完成 - 用户: {}, 模型: {}, 回复长度: {}",
                    userId, selectedConfig.getModelId(), finalReply.length());

        } catch (Exception e) {
            log.error("流式AI对话处理失败: {}", e.getMessage(), e);
            chunkConsumer.accept("抱歉，AI服务暂时不可用");
        }
    }

    @Override
    public void handleOpenAiStreamBridge(OpenAIChatRequest request, String userId, HttpServletResponse response) {
        response.setContentType("text/event-stream");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Cache-Control", "no-cache");
        response.setHeader("Connection", "keep-alive");
        response.setHeader("X-Accel-Buffering", "no");

        try (PrintWriter writer = response.getWriter()) {
            // 1. 获取配置与模型
            Optional<List<ChatAiConfigDto>> configOpt = configService.getConfigByCloudType(1);
            if (!configOpt.isPresent() || configOpt.get().isEmpty()) {
                sendStreamError(writer, "No AI configuration found.");
                return;
            }
            ChatAiConfigDto selectedConfig = selectOptimalModel(configOpt.get(), userId);
            Tenant tenant = tenantRepository.findById(Long.valueOf(selectedConfig.getTenantId())).orElse(null);
            String modelId = (request.getModel() != null && StringUtils.isNotBlank(request.getModel())) ? request.getModel() : selectedConfig.getModelId();
            List<Map<String, String>> messages = request.getMessages().stream()
                    .map(m -> {
                        Map<String, String> map = new HashMap<>();
                        map.put("role", m.getRole());
                        map.put("content", m.getContent());
                        return map;
                    }).collect(Collectors.toList());

            if (messages.isEmpty()) return;
            String lastUserMessage = messages.get(messages.size() - 1).get("content");
            StringBuilder fullReply = new StringBuilder();
            if (messages.size() > 1) {
                aiUtils.chatWithHistoryStream(tenant, messages, modelId, chunk -> {
                    writeOpenAiChunk(writer, modelId, chunk, false);
                    fullReply.append(chunk);
                }, null);
            } else {
                aiUtils.chatWithStream(tenant, lastUserMessage, modelId, chunk -> {
                    writeOpenAiChunk(writer, modelId, chunk, false);
                    fullReply.append(chunk);
                });
            }
            writeOpenAiChunk(writer, modelId, "", true);
            String finalReply = fullReply.toString();
            CompletableFuture.runAsync(() -> {
                addUserAiMessage(userId, lastUserMessage, modelId);
                addAssistantAiMessage(userId, finalReply, modelId);
            });

        } catch (IOException e) {
            log.error("OpenAI Stream Bridge 管道中断: {}", e.getMessage());
        } catch (Exception e) {
            log.error("OpenAI Stream Bridge 业务异常", e);
        }
    }

    @Override
    public void handleOpenAiStreamBridgeSse(OpenAIChatRequest request, String userId, SseEmitter emitter) {
        // 开启异步线程，释放 Tomcat 主线程
        CompletableFuture.runAsync(() -> {
            try {
                // 1. 获取配置与模型
                Optional<List<ChatAiConfigDto>> configOpt = configService.getConfigByCloudType(1);
                if (!configOpt.isPresent() || configOpt.get().isEmpty()) {
                    sendStreamError(emitter, "No AI configuration found.");
                    return;
                }

                String model = request.getModel();
                Tenant tenant;
                String modelId;
                if (StringUtils.isNotEmpty(model)){
                    //前端传的是showModelId
                    ChatAiConfigDto configServiceModel = configService.findModel(model);
                    tenant = tenantRepository.findById(Long.valueOf(configServiceModel.getTenantId())).orElse(null);
                    modelId = configServiceModel.getModelId();
                }else{
                    ChatAiConfigDto selectedConfig = selectOptimalModel(configOpt.get(), userId);
                    tenant = tenantRepository.findById(Long.valueOf(selectedConfig.getTenantId())).orElse(null);
                    modelId = (request.getModel() != null && StringUtils.isNotBlank(request.getModel()))
                            ? request.getModel() : selectedConfig.getModelId();
                }

                List<Map<String, String>> messages = request.getMessages().stream()
                        .map(m -> {
                            Map<String, String> map = new HashMap<>();
                            map.put("role", m.getRole());
                            map.put("content", m.getContent());
                            return map;
                        }).collect(Collectors.toList());

                if (messages.isEmpty()) {
                    emitter.complete();
                    return;
                }

                String lastUserMessage = messages.get(messages.size() - 1).get("content");
                StringBuilder fullReply = new StringBuilder();

                // 2. 定义推流回调逻辑
                Consumer<String> chunkHandler = chunk -> {
                    try {
                        writeOpenAiChunk(emitter, model, chunk, false);
                        fullReply.append(chunk);
                    } catch (Exception e) {
                        throw new RuntimeException("流数据推送失败: 客户端已断开", e);
                    }
                };

                // 3. 调用底层大模型接口
                if (messages.size() > 1) {
                    aiUtils.chatWithHistoryStream(tenant, messages, modelId, chunkHandler, null);
                } else {
                    aiUtils.chatWithStream(tenant, lastUserMessage, modelId, chunkHandler);
                }

                writeOpenAiChunk(emitter, model, "", true);
                emitter.complete();

                // 5. 异步落库
                String finalReply = fullReply.toString();
                CompletableFuture.runAsync(() -> {
                    addUserAiMessage(userId, lastUserMessage, modelId);
                    addAssistantAiMessage(userId, finalReply, modelId);
                });

            } catch (Exception e) {
                log.error("OpenAI Stream Bridge 业务异常", e);
                // 发生异常时，安全地关闭流并传递错误
                emitter.completeWithError(e);
            }
        });
    }

    private void writeOpenAiChunk(PrintWriter writer, String model, String content, boolean isEnd) {
        try {
            Map<String, Object> chunk = new HashMap<>();
            chunk.put("id", "chatcmpl-" + System.currentTimeMillis());
            chunk.put("object", "chat.completion.chunk");
            chunk.put("created", System.currentTimeMillis() / 1000);
            chunk.put("model", model);
            List<Map<String, Object>> choices = new ArrayList<>();
            Map<String, Object> choice = new HashMap<>();
            choice.put("index", 0);

            if (isEnd) {
                choice.put("delta", new HashMap<>());
                choice.put("finish_reason", "stop");
            } else {
                Map<String, String> delta = new HashMap<>();
                delta.put("content", content);
                choice.put("delta", delta);
                choice.put("finish_reason", null);
            }
            choices.add(choice);
            chunk.put("choices", choices);

            writer.println("data: " + objectMapper.writeValueAsString(chunk));
            if (isEnd) {
                writer.println("data: [DONE]");
            }
            writer.flush();
        } catch (Exception e) {
            log.error("封装 OpenAI Chunk 失败", e);
        }
    }

    private void writeOpenAiChunk(SseEmitter emitter, String modelId, String chunk, boolean isDone) throws IOException {
        if (isDone) {
            emitter.send("[DONE]");
            return;
        }
        Map<String, Object> delta = new HashMap<>();
        delta.put("content", chunk);

        Map<String, Object> choice = new HashMap<>();
        choice.put("delta", delta);

        Map<String, Object> response = new HashMap<>();
        response.put("id", "chatcmpl-" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));
        response.put("object", "chat.completion.chunk");
        response.put("model", modelId);
        response.put("choices", Collections.singletonList(choice));
        String jsonString = objectMapper.writeValueAsString(response);
        emitter.send(jsonString);
    }

    /**
     * 清洗 AI 返回的内容，剔除指令复读
     */
    private String cleanAiReview(String review) {
        if (StringUtils.isBlank(review)) return "";
        return review.replaceAll("(?i)【输出要求】.*?[：:]", "")
                .replaceAll("(?i)犀利点评20字内", "")
                .replaceAll("(?i)（必须包含价格区间）", "")
                .replaceAll("(?i)点评[：:]", "")
                .replaceAll("(?i)规则[：:]", "")
                .replaceAll("(?i)---.*---", "")
                .replaceAll("\n", " ")
                .trim();
    }

    /**
     * 手动估价逻辑
     */
    private int calculatePriceManual(boolean isPayg, int regions, int days, int armCores, int offlineCount) {
        int base = isPayg ? 850 : (regions > 1 ? 350 : 50);
        if (days > 180) base += 200;
        base += (armCores * 50);
        if (isPayg && regions > 3) base += (regions - 3) * 100;
        if (days < 30) base *= 0.5;
        base -= (offlineCount * 50);
        return Math.max(base, 50);
    }

    private void recordModelUsage(String modelId) {
        modelUsageCounter.computeIfAbsent(modelId, k -> new AtomicInteger(0)).incrementAndGet();
        modelLastUsedTime.put(modelId, System.currentTimeMillis());
    }

    private void addUserAiMessage(String userId, String message, String modelId) {
        try {
            AiChatHistory record = new AiChatHistory(userId, "user", message, modelId);
            aiChatHistoryRepository.save(record);
            log.debug("用户 {} 消息已持久化到DB", userId);
        } catch (Exception e) {
            log.error("持久化用户消息失败: {}", e.getMessage(), e);
        }
    }

    // 选择备用模型
    private ChatAiConfigDto selectBackupModel(List<ChatAiConfigDto> configs, String excludeModelId) {
        List<ChatAiConfigDto> backupConfigs = configs.stream()
                .filter(config -> !excludeModelId.equals(config.getModelId()))
                .collect(Collectors.toList());

        if (backupConfigs.isEmpty()) {
            return null;
        }

        // 备用模型使用随机选择
        return selectByRandom(backupConfigs);
    }

    private ChatAiConfigDto selectByRandom(List<ChatAiConfigDto> configs) {
        int index = ThreadLocalRandom.current().nextInt(configs.size());
        return configs.get(index);
    }

    // 4. 智能模型选择策略
    private ChatAiConfigDto selectOptimalModel(List<ChatAiConfigDto> enabledConfigs, String userId) {
        if (enabledConfigs.isEmpty()) {
            return null;
        }

        if (enabledConfigs.size() == 1) {
            return enabledConfigs.get(0);
        }

        switch (currentStrategy) {
            case ROUND_ROBIN:
                return selectByRoundRobin(enabledConfigs, userId);
            case RANDOM:
                return selectByRandom(enabledConfigs);
            case LEAST_USED:
                return selectByLeastUsed(enabledConfigs);
            case LOAD_BALANCE:
            default:
                return selectByLoadBalance(enabledConfigs);
        }
    }

    // 轮询选择
    private ChatAiConfigDto selectByRoundRobin(List<ChatAiConfigDto> configs, String userId) {
        int index = roundRobinCounter.getAndIncrement() % configs.size();
        return configs.get(index);
    }

    // 最少使用选择
    private ChatAiConfigDto selectByLeastUsed(List<ChatAiConfigDto> configs) {
        return configs.stream()
                .min((c1, c2) -> {
                    int usage1 = modelUsageCounter.getOrDefault(c1.getModelId(), new AtomicInteger(0)).get();
                    int usage2 = modelUsageCounter.getOrDefault(c2.getModelId(), new AtomicInteger(0)).get();
                    return Integer.compare(usage1, usage2);
                })
                .orElse(configs.get(0));
    }

    // 综合负载均衡选择（考虑使用次数、最后使用时间等因素）
    private ChatAiConfigDto selectByLoadBalance(List<ChatAiConfigDto> configs) {
        long currentTime = System.currentTimeMillis();

        return configs.stream()
                .min((c1, c2) -> {
                    // 计算综合评分，评分越低越优先
                    double score1 = calculateLoadScore(c1.getModelId(), currentTime);
                    double score2 = calculateLoadScore(c2.getModelId(), currentTime);
                    return Double.compare(score1, score2);
                })
                .orElse(configs.get(0));
    }

    // 计算负载评分
    private double calculateLoadScore(String modelId, long currentTime) {
        // 使用次数权重 40%
        int usageCount = modelUsageCounter.getOrDefault(modelId, new AtomicInteger(0)).get();
        double usageScore = usageCount * 0.4;

        // 最后使用时间权重 30%（最近使用的稍微降低优先级，让模型轮换）
        long lastUsed = modelLastUsedTime.getOrDefault(modelId, 0L);
        long timeDiff = currentTime - lastUsed;
        double timeScore = Math.max(0, (60000 - timeDiff) / 60000.0) * 0.3; // 1分钟内使用过的降低优先级

        // 随机因子权重 30%（避免总是选择同一个模型）
        double randomScore = ThreadLocalRandom.current().nextDouble() * 0.3;

        return usageScore + timeScore + randomScore;
    }

    private void addAssistantAiMessage(String userId, String message, String modelId) {
        try {
            AiChatHistory record = new AiChatHistory(userId, "assistant", message, modelId);
            aiChatHistoryRepository.save(record);
        } catch (Exception e) {
            log.error("持久化AI回复消息失败: {}", e.getMessage(), e);
        }
    }

    /**
     * 获取用户AI历史上下文（支持跨模型连续对话）
     * 从数据库查询最近10条记录
     */
    private List<Map<String, String>> getUserAiHistoryContext(String userId) {
        try {
            List<AiChatHistory> recentMessages = aiChatHistoryRepository.findRecentByUserId(userId);

            if (recentMessages == null || recentMessages.isEmpty()) {
                return new ArrayList<>();
            }

            // findRecentByUserId 按 createdAt DESC 返回，取最近10条然后反转为时间升序
            int limit = Math.min(recentMessages.size(), 10);
            List<AiChatHistory> latest = recentMessages.subList(0, limit);
            Collections.reverse(latest);

            List<Map<String, String>> context = new ArrayList<>();
            for (AiChatHistory msg : latest) {
                Map<String, String> messageMap = new HashMap<>();
                messageMap.put("role", msg.getRole());
                messageMap.put("content", msg.getContent());
                context.add(messageMap);
            }

            return context;
        } catch (Exception e) {
            log.error("获取用户AI历史上下文失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }


    /**
     * 处理普通响应
     */
    /*private CompletableFuture<?> handleNormalResponse(OpenAIChatRequest request, String userId) {
        // 获取用户消息
        String userMessage = request.getMessages().stream()
                .filter(msg -> "user".equals(msg.getRole()))
                .reduce((first, second) -> second)
                .map(msg -> msg.getContent())
                .orElse("");

        if (StringUtils.isBlank(userMessage)) {
            throw new RuntimeException("用户消息不能为空");
        }

        // 调用现有聊天服务
        return chat(userId, userMessage, request.getModel()).thenApply(result -> {
            // 提取AI回复
            String aiReply = "抱歉，我无法回答您的问题。";
            if (result.isSuccess() && result.getData() instanceof AiChatResp) {
                AiChatResp chatResp = (AiChatResp) result.getData();
                if (StringUtils.isNotBlank(chatResp.getAiReply())) {
                    aiReply = chatResp.getAiReply();
                }
            }

            // 构造OpenAI格式响应
            OpenAIChatResponse response = new OpenAIChatResponse();
            response.id = "chatcmpl-" + System.currentTimeMillis();
            response.object = "chat.completion";
            response.created = System.currentTimeMillis() / 1000;
            response.model = request.getModel() != null ? request.getModel() : "oci-model";

            Choice choice = new Choice();
            choice.index = 0;
            choice.message = new ChatMessage("assistant", aiReply);
            choice.finish_reason = "stop";
            response.choices = Arrays.asList(choice);

            Usage usage = new Usage();
            usage.prompt_tokens = userMessage.length() / 4;
            usage.completion_tokens = aiReply.length() / 4;
            usage.total_tokens = usage.prompt_tokens + usage.completion_tokens;
            response.usage = usage;

            return response;
        });
    }*/

    private CompletableFuture<?> handleNormalResponse(OpenAIChatRequest request, String userId) {
        // 获取用户消息用于 Token 计算和日志验证
        String userMessageText = extractLatestUserMessage(request);

        if (StringUtils.isBlank(userMessageText)) {
            throw new RuntimeException("用户消息不能为空");
        }

        // 【极其关键的改动】：
        // 这里千万不能再调用原来的 chat(userId, userMessage, model) 了！
        // 必须调用一个能接收完整 request (包含 tools 列表) 的新方法，例如 chatWithFullRequest
        return chatWithFullRequest(userId, request).thenApply(result -> {

            // 1. 构造基础响应外壳
            OpenAIChatResponse response = new OpenAIChatResponse();
            response.id = "chatcmpl-" + System.currentTimeMillis();
            response.object = "chat.completion";
            response.created = System.currentTimeMillis() / 1000;
            response.model = request.getModel() != null ? request.getModel() : "oci-model";

            Choice choice = new Choice();
            choice.index = 0;

            ChatMessage assistantMessage = new ChatMessage();
            assistantMessage.setRole("assistant");

            // 2. 核心分流逻辑：提取并判断 AI 返回的是指令还是文本
                if (result.isSuccess() && result.getData() instanceof AiChatResp) {
                AiChatResp chatResp = (AiChatResp) result.getData();

                // 检查模型是否触发了工具调用
                if (chatResp.getToolCalls() != null && !chatResp.getToolCalls().isEmpty()) {
                    // === 场景 A：工具调用 ===
                    assistantMessage.setContent(null); // 调用工具时文本应为空
                    assistantMessage.setTool_calls(chatResp.getToolCalls());
                    choice.finish_reason = "tool_calls"; // 明确返回工具调用状态
                } else {
                    // === 场景 B：普通文本回复 ===
                    String reply = StringUtils.isNotBlank(chatResp.getAiReply())
                            ? chatResp.getAiReply()
                            : "抱歉，我无法回答您的问题。";
                    assistantMessage.setContent(reply);
                    choice.finish_reason = "stop"; // 对话正常结束
                }
            } else {
                // 异常兜底
                assistantMessage.setContent("底层 AI 服务处理失败或返回格式异常。");
                choice.finish_reason = "stop";
            }

            choice.message = assistantMessage;
            response.choices = Arrays.asList(choice);

            // 3. 粗略的 Token 统计逻辑
            Usage usage = new Usage();
            usage.prompt_tokens = userMessageText.length() / 4;
            // 因为工具调用时 content 为 null，要做判空保护，给一个估算的 token 消耗
            int completionTokens = assistantMessage.getContent() != null ? assistantMessage.getContent().length() / 4 : 15;
            usage.completion_tokens = completionTokens;
            usage.total_tokens = usage.prompt_tokens + usage.completion_tokens;
            response.usage = usage;

            return response;
        });
    }

    /**
     * 支持 Function Calling 的完整请求处理方法
     * 替代原有的 chat() 方法，负责将携带 tools 的 request 传给底层
     */
    public CompletableFuture<ApiResponse> chatWithFullRequest(String userId, OpenAIChatRequest request) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                // 1. 获取所有可用的AI配置 (完全复用你原有的多租户/负载均衡逻辑)
                Optional<List<ChatAiConfigDto>> configOpt = configService.getConfigByCloudType(1);
                if (!configOpt.isPresent() || configOpt.get().isEmpty()) {
                    return ApiResponse.error("AI服务暂时不可用，请稍后重试");
                }

                List<ChatAiConfigDto> enabledConfigs = configOpt.get().stream()
                        .filter(ChatAiConfigDto::getEnabled)
                        .collect(Collectors.toList());

                // 处理模型过滤逻辑
                String showModelId = request.getModel();
                if (StringUtils.isNotBlank(showModelId)) {
                    String modelName = showModelId.contains("-") ? showModelId.substring(4, showModelId.lastIndexOf("-")) : showModelId;
                    List<ChatAiConfigDto> collect = enabledConfigs.stream().filter(config -> config.getModelName().equals(modelName) || config.getModelId().equals(showModelId)).collect(Collectors.toList());
                    if (!CollectionUtils.isEmpty(collect)) {
                        enabledConfigs = collect;
                    }
                }

                if (enabledConfigs.isEmpty()) {
                    return ApiResponse.error("AI服务暂时不可用，请稍后重试");
                }

                // 智能选择模型
                ChatAiConfigDto selectedConfig = selectOptimalModel(enabledConfigs, userId);
                if (selectedConfig == null) {
                    return ApiResponse.error("AI服务暂时不可用，请稍后重试");
                }

                recordModelUsage(selectedConfig.getModelId());

                Tenant tenant = tenantRepository.findById(Long.valueOf(selectedConfig.getTenantId())).orElse(null);
                if (tenant == null) {
                    return ApiResponse.error("配置错误，请联系管理员");
                }

                // 提取用户当前文本用于落库保存
                String userMessage = extractLatestUserMessage(request);
                if (StringUtils.isNotBlank(userMessage)) {
                    addUserAiMessage(userId, userMessage, selectedConfig.getModelId());
                }

                long startTime = System.currentTimeMillis();

                // 【核心警告：这里需要你修改 aiUtils！】
                // 不能再调用原来返回 String 的 aiUtils.chat() 了。
                // 你需要在 OciAiChatUtils 中新建一个方法，接收整个 request，
                // 并返回一个包含 aiReply 和 toolCalls 的 AiChatResp 对象。
                AiChatResp aiChatResp;
                try {
                    // 假设你在 aiUtils 里新建了这个方法：
                    aiChatResp = aiUtils.chatWithFunctionCalling(tenant, request, selectedConfig.getModelId());
                } catch (Exception e) {
                    log.warn("模型 {} 调用失败，尝试备用模型: {}", selectedConfig.getModelId(), e.getMessage());

                    // 备用模型降级逻辑
                    ChatAiConfigDto backupConfig = selectBackupModel(enabledConfigs, selectedConfig.getModelId());
                    if (backupConfig != null) {
                        try {
                            tenant = tenantRepository.findById(Long.valueOf(backupConfig.getTenantId())).orElse(null);
                            aiChatResp = aiUtils.chatWithFunctionCalling(tenant, request, backupConfig.getModelId());
                            selectedConfig = backupConfig;
                            recordModelUsage(backupConfig.getModelId());
                        } catch (Exception backupException) {
                            log.error("备用模型调用也失败: {}", backupException.getMessage());
                            return ApiResponse.error("AI服务暂时不可用: " + backupException.getMessage());
                        }
                    } else {
                        return ApiResponse.error("AI服务暂时不可用: " + e.getMessage());
                    }
                }

                long responseTime = System.currentTimeMillis() - startTime;

                // 只有当模型返回普通文本时，才进行历史记录落库
                if (aiChatResp != null && StringUtils.isNotBlank(aiChatResp.getAiReply())) {
                    addAssistantAiMessage(userId, aiChatResp.getAiReply(), selectedConfig.getModelId());
                }

                log.debug("AI对话完成 - 用户: {}, 模型: {}, 响应时间: {}ms", userId, selectedConfig.getModelId(), responseTime);

                // 返回装载了 文本 或 工具指令 的完整对象
                return ApiResponse.success(aiChatResp);

            } catch (Exception e) {
                log.error("AI对话处理失败: {}", e.getMessage(), e);
                return ApiResponse.error("抱歉，AI服务暂时不可用: " + e.getMessage());
            }
        }, aiChatExecutor);
    }

    // 辅助方法：提取最新一条用户纯文本消息，仅用于上面粗略计算 Token
    private String extractLatestUserMessage(OpenAIChatRequest request) {
        if (request.getMessages() == null) return "";
        return request.getMessages().stream()
                .filter(msg -> "user".equals(msg.getRole()))
                .reduce((first, second) -> second)
                .map(ChatMessage::getContent)
                .orElse("");
    }

    /**
     * 处理流式响应
     */
    private CompletableFuture<Void> handleStreamResponse(OpenAIChatRequest request, String userId, HttpServletResponse response) {
        return CompletableFuture.runAsync(() -> {
            try {
                // 设置SSE响应头
                response.setContentType("text/event-stream");
                response.setCharacterEncoding("UTF-8");
                response.setHeader("Cache-Control", "no-cache");
                response.setHeader("Connection", "keep-alive");
                response.setHeader("Access-Control-Allow-Origin", "*");

                PrintWriter writer = response.getWriter();

                // 获取用户消息
                String userMessage = request.getMessages().stream()
                        .filter(msg -> "user".equals(msg.getRole()))
                        .reduce((first, second) -> second)
                        .map(ChatMessage::getContent)
                        .orElse("");

                if (StringUtils.isBlank(userMessage)) {
                    sendStreamError(writer, "用户消息不能为空");
                    return;
                }

                // 调用聊天服务
                chat(userId, userMessage,request.getModel()).whenComplete((result, throwable) -> {
                    try {
                        if (throwable != null) {
                            sendStreamError(writer, "聊天服务异常: " + throwable.getMessage());
                            return;
                        }

                        String aiReply = "抱歉，我无法回答您的问题。";
                        if (result.isSuccess() && result.getData() instanceof AiChatResp) {
                            AiChatResp chatResp = (AiChatResp) result.getData();
                            if (StringUtils.isNotBlank(chatResp.getAiReply())) {
                                aiReply = chatResp.getAiReply();
                            }
                        }

                        // 发送流式响应
                        sendStreamMessage(writer, request, aiReply);
                        sendStreamEnd(writer, request);

                    } catch (Exception e) {
                        log.error("流式响应处理异常", e);
                        sendStreamError(writer, "处理响应时发生异常");
                    }
                });

            } catch (Exception e) {
                log.error("流式响应初始化失败", e);
            }
        });
    }

    /**
     * 发送流式消息
     */
    private void sendStreamMessage(PrintWriter writer, OpenAIChatRequest request, String content) {
        try {
            String chatId = "chatcmpl-" + System.currentTimeMillis();
            long created = System.currentTimeMillis() / 1000;

            // 发送消息内容
            Map<String, Object> chunk = new HashMap<>();
            chunk.put("id", chatId);
            chunk.put("object", "chat.completion.chunk");
            chunk.put("created", created);
            chunk.put("model", request.getModel() != null ? request.getModel() : "oci-model");

            Map<String, Object> choice = new HashMap<>();
            choice.put("index", 0);

            Map<String, Object> delta = new HashMap<>();
            delta.put("role", "assistant");
            delta.put("content", content);

            choice.put("delta", delta);
            choice.put("finish_reason", null);

            chunk.put("choices", Arrays.asList(choice));

            String jsonData = objectMapper.writeValueAsString(chunk);
            writer.println("data: " + jsonData);
            writer.flush();

        } catch (Exception e) {
            log.error("发送流式消息失败", e);
        }
    }

    /**
     * 发送流式结束标记
     */
    private void sendStreamEnd(PrintWriter writer, OpenAIChatRequest request) {
        try {
            // 发送结束标记
            Map<String, Object> endChunk = new HashMap<>();
            endChunk.put("id", "chatcmpl-" + System.currentTimeMillis());
            endChunk.put("object", "chat.completion.chunk");
            endChunk.put("created", System.currentTimeMillis() / 1000);
            endChunk.put("model", request.getModel() != null ? request.getModel() : "oci-model");

            Map<String, Object> endChoice = new HashMap<>();
            endChoice.put("index", 0);
            endChoice.put("delta", new HashMap<>());
            endChoice.put("finish_reason", "stop");

            endChunk.put("choices", Arrays.asList(endChoice));

            String endJsonData = objectMapper.writeValueAsString(endChunk);
            writer.println("data: " + endJsonData);
            writer.println("data: [DONE]");
            writer.flush();
            writer.close();

        } catch (Exception e) {
            log.error("发送流式结束标记失败", e);
        }
    }

    private void sendStreamError(SseEmitter emitter, String errorMessage) {
        try {
            Map<String, Object> errorDetails = new HashMap<>();
            errorDetails.put("message", errorMessage);
            errorDetails.put("type", "server_error");

            Map<String, Object> errorBody = new HashMap<>();
            errorBody.put("error", errorDetails);

            emitter.send(objectMapper.writeValueAsString(errorBody));
            emitter.complete();
        } catch (Exception e) {
            log.error("发送错误信息失败", e);
            emitter.completeWithError(e);
        }
    }

    /**
     * 发送流式错误
     */
    private void sendStreamError(PrintWriter writer, String errorMessage) {
        try {
            Map<String, Object> errorChunk = new HashMap<>();
            Map<String, Object> errorMap = new HashMap<>();
            errorMap.put("message", errorMessage);
            errorMap.put("type", "api_error");
            errorMap.put("code", "internal_error");

            errorChunk.put("id", "chatcmpl-" + System.currentTimeMillis());
            errorChunk.put("object", "chat.completion.chunk");
            errorChunk.put("created", System.currentTimeMillis() / 1000);
            errorChunk.put("error", errorMap);

            String errorJsonData = objectMapper.writeValueAsString(errorChunk);
            writer.println("data: " + errorJsonData);
            writer.println("data: [DONE]");
            writer.flush();
            writer.close();

        } catch (Exception e) {
            log.error("发送流式错误失败", e);
        }
    }
}
