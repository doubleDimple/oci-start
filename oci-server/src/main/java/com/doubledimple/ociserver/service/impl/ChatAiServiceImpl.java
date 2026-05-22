package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.doubledimple.ocicommon.enums.ModelSelectionStrategy;
import com.doubledimple.ocicommon.param.AiChatMessage;
import com.doubledimple.ocicommon.param.AiChatResp;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.ChatAiConfigDto;
import com.doubledimple.ocicommon.param.ChatMessage;
import com.doubledimple.ocicommon.param.Choice;
import com.doubledimple.ocicommon.param.OpenAIChatRequest;
import com.doubledimple.ocicommon.param.OpenAIChatResponse;
import com.doubledimple.ocicommon.param.Usage;
import com.doubledimple.ociserver.service.TenantService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.util.CollectionUtils;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import javax.servlet.http.HttpServletResponse;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName ChatAiServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-11 16:48
 */
/*@Slf4j
@Service
public class ChatAiServiceImpl implements ChatAiService {

    @Resource
    ThreadPoolExecutor aiChatExecutor;

    @Resource
    ChatAiConfigService configService;

    @Resource
    OciAiChatUtils aiUtils;

    @Resource
    TenantService tenantService;

    @Resource
    private ChatAiConfigService chatAiConfigService;

    @Resource
    private ObjectMapper objectMapper;

    // 配置常量
    private static final int MAX_MESSAGES = 5; // 最多保存5条消息
    private static final int CLEANUP_INTERVAL_MINUTES = 30; // 30分钟清理一次

    // 用户消息缓存 - 存储每个用户最近5条非命令消息
    private final Map<String, LinkedList<String>> userMessageCache = new ConcurrentHashMap<>();
    // 定时清理任务
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);
    private final Map<String, LinkedList<AiChatMessage>> userAiMessageCache = new ConcurrentHashMap<>();
    private final Map<String, ReentrantReadWriteLock> userCacheLocks = new ConcurrentHashMap<>();
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
                Tenant tenant = tenantService.getById(Long.valueOf(selectedConfig.getTenantId()));
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
                        aiResponse = aiUtils.chatWithHistory(tenant, historyContext, selectedConfig.getModelId());
                    }
                } catch (Exception e) {
                    log.warn("模型 {} 调用失败，尝试备用模型: {}", selectedConfig.getModelId(), e.getMessage());

                    // 尝试使用备用模型
                    ChatAiConfigDto backupConfig = selectBackupModel(enabledConfigs, selectedConfig.getModelId());
                    if (backupConfig != null) {
                        try {
                            tenant = tenantService.getById(Long.valueOf(backupConfig.getTenantId()));
                            if (tenant == null) {
                                return ApiResponse.error("备用模型配置错误，请联系管理员");
                            }

                            if (historyContext.size() <= 1) {
                                aiResponse = aiUtils.chat(tenant, userMessage, backupConfig.getModelId());
                            } else {
                                aiResponse = aiUtils.chatWithHistory(tenant, historyContext, backupConfig.getModelId());
                            }
                            selectedConfig = backupConfig; // 更新使用的配置
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

                // 返回成功结果，将AI回复作为data
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

    *//**
    * @Description: chatCompletions
    * @Param: [com.doubledimple.ociserver.openApi.request.OpenAIChatRequest, java.lang.String]
    * @return: java.util.concurrent.CompletableFuture<com.doubledimple.ociserver.openApi.response.OpenAIChatResponse>
    * @Author: doubleDimple
    * @Date: 9/13/25 8:59 AM
    *//*
    @Override
    public CompletableFuture<?> chatCompletions(OpenAIChatRequest request, String userId, HttpServletResponse httpResponse) {
        // 检查是否为流式请求
        boolean isStream = Boolean.TRUE.equals(request.getStream());

        if (isStream) {
            return handleStreamResponse(request, userId, httpResponse);
        } else {
            return handleNormalResponse(request, userId);
        }
    }

    *//**
    * @Description: handleStreamResponseSync
    * @Param: [com.doubledimple.ociserver.openApi.request.OpenAIChatRequest, java.lang.String, javax.servlet.http.HttpServletResponse]
    * @return: void
    * @Author: doubleDimple
    * @Date: 9/13/25 11:00 AM
    *//*
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

    *//**
    * @Description: 获取配置的可用模型
    * @Param: []
    * @return: java.util.Map<java.lang.String,java.lang.Object>
    * @Author: doubleDimple
    * @Date: 9/13/25 3:42 PM
    *//*
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

                    // 可选：添加模型名称作为描述
                    if (StringUtils.isNotBlank(config.getModelName())) {
                        model.put("description", config.getModelName());
                    }

                    modelList.add(model);
                }
            }
        }
        response.put("data", modelList);

        log.info("返回{}个可用模型给new-api", modelList.size());
        return response;
    }

    private void recordModelUsage(String modelId) {
        modelUsageCounter.computeIfAbsent(modelId, k -> new AtomicInteger(0)).incrementAndGet();
        modelLastUsedTime.put(modelId, System.currentTimeMillis());
    }

    private void addUserAiMessage(String userId, String message, String modelId) {
        ReentrantReadWriteLock lock = getUserCacheLock(userId);
        lock.writeLock().lock();
        try {
            userAiMessageCache.computeIfAbsent(userId, k -> new LinkedList<>());
            LinkedList<AiChatMessage> messages = userAiMessageCache.get(userId);

            messages.add(new AiChatMessage("user", message, modelId));

            // 保持最多20条消息（用户+助手消息）
            while (messages.size() > 20) {
                messages.removeFirst();
            }

            log.debug("用户 {} 添加消息到AI缓存，当前缓存数量: {}", userId, messages.size());
        } finally {
            lock.writeLock().unlock();
        }
    }

    // ================================
    // 5. 历史记录管理方法
    // ================================
    private ReentrantReadWriteLock getUserCacheLock(String userId) {
        return userCacheLocks.computeIfAbsent(userId, k -> new ReentrantReadWriteLock());
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
        ReentrantReadWriteLock lock = getUserCacheLock(userId);
        lock.writeLock().lock();
        try {
            userAiMessageCache.computeIfAbsent(userId, k -> new LinkedList<>());
            LinkedList<AiChatMessage> messages = userAiMessageCache.get(userId);

            messages.add(new AiChatMessage("assistant", message, modelId));

            // 保持最多20条消息
            while (messages.size() > 20) {
                messages.removeFirst();
            }

        } finally {
            lock.writeLock().unlock();
        }
    }

    // 获取用户AI历史上下文（支持跨模型连续对话）
    private List<Map<String, String>> getUserAiHistoryContext(String userId) {
        ReentrantReadWriteLock lock = getUserCacheLock(userId);
        lock.readLock().lock();
        try {
            LinkedList<AiChatMessage> messages = userAiMessageCache.get(userId);
            List<Map<String, String>> context = new ArrayList<>();

            if (messages != null && !messages.isEmpty()) {
                // 取最近的10条对话（支持跨模型）
                int startIndex = Math.max(0, messages.size() - 10);
                for (int i = startIndex; i < messages.size(); i++) {
                    AiChatMessage msg = messages.get(i);
                    Map<String, String> messageMap = new HashMap<>();
                    messageMap.put("role", msg.getRole());
                    messageMap.put("content", msg.getContent());
                    context.add(messageMap);
                }
            }

            return context;
        } finally {
            lock.readLock().unlock();
        }
    }

    @PostConstruct
    public void initScheduler() {
        // 原有的清理任务
        scheduler.scheduleAtFixedRate(() -> {
            int clearedUsers = userMessageCache.size();
            userMessageCache.clear();
            if (clearedUsers > 0) {
                log.info("定时清理用户消息缓存，清理{}个用户的缓存", clearedUsers);
            }
        }, CLEANUP_INTERVAL_MINUTES, CLEANUP_INTERVAL_MINUTES, TimeUnit.MINUTES);

        // 新增AI消息缓存清理任务
        scheduler.scheduleAtFixedRate(() -> {
            long currentTime = System.currentTimeMillis();
            long expireTime = currentTime - TimeUnit.HOURS.toMillis(2); // 2小时过期

            userAiMessageCache.entrySet().removeIf(entry -> {
                LinkedList<AiChatMessage> messages = entry.getValue();
                if (messages.isEmpty()) {
                    return true;
                }

                // 移除过期消息
                messages.removeIf(msg -> msg.getTimestamp() < expireTime);

                // 如果消息列表为空，移除整个用户记录
                if (messages.isEmpty()) {
                    userCacheLocks.remove(entry.getKey());
                    return true;
                }
                return false;
            });

            // 清理模型使用统计（每天重置）
            long dayExpire = currentTime - TimeUnit.DAYS.toMillis(1);
            modelLastUsedTime.entrySet().removeIf(entry -> entry.getValue() < dayExpire);

            log.info("AI消息缓存清理完成，当前缓存用户数: {}, 活跃模型数: {}",
                    userAiMessageCache.size(), modelLastUsedTime.size());

        }, 60, 60, TimeUnit.MINUTES); // 每小时清理一次

        log.info("TelegramBotCus消息缓存清理任务已启动，每{}分钟清理一次", CLEANUP_INTERVAL_MINUTES);
    }

    @PreDestroy
    public void cleanup() {
        // 原有的scheduler清理
        if (!scheduler.isShutdown()) {
            scheduler.shutdown();
            try {
                if (!scheduler.awaitTermination(30, TimeUnit.SECONDS)) {
                    scheduler.shutdownNow();
                }
            } catch (InterruptedException e) {
                scheduler.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }

        // 注意：aiChatExecutor由Spring管理，不需要手动关闭
        log.info("TelegramBotCus资源清理完成");
    }

    *//**
     * 处理普通响应
     *//*
    private CompletableFuture<OpenAIChatResponse> handleNormalResponse(OpenAIChatRequest request, String userId) {
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
        return chat(userId, userMessage,request.getModel()).thenApply(result -> {
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
    }

    *//**
     * 处理流式响应
     *//*
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

    *//**
     * 发送流式消息
     *//*
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

    *//**
     * 发送流式结束标记
     *//*
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

    *//**
     * 发送流式错误
     *//*
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
}*/
