package com.doubledimple.ociserver.utils.oracle.ai;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.generativeai.GenerativeAiClient;
import com.oracle.bmc.generativeai.model.Model;
import com.oracle.bmc.generativeai.model.ModelCapability;
import com.oracle.bmc.generativeaiinference.GenerativeAiInferenceClient;
import com.oracle.bmc.generativeaiinference.model.BaseChatResponse;
import com.oracle.bmc.generativeaiinference.model.ChatChoice;
import com.oracle.bmc.generativeaiinference.model.ChatContent;
import com.oracle.bmc.generativeaiinference.model.ChatDetails;
import com.oracle.bmc.generativeaiinference.model.CohereChatBotMessage;
import com.oracle.bmc.generativeaiinference.model.CohereChatRequest;
import com.oracle.bmc.generativeaiinference.model.CohereChatResponse;
import com.oracle.bmc.generativeaiinference.model.CohereMessage;
import com.oracle.bmc.generativeaiinference.model.CohereSystemMessage;
import com.oracle.bmc.generativeaiinference.model.CohereUserMessage;
import com.oracle.bmc.generativeaiinference.model.GenericChatRequest;
import com.oracle.bmc.generativeaiinference.model.GenericChatResponse;
import com.oracle.bmc.generativeaiinference.model.OnDemandServingMode;
import com.oracle.bmc.generativeaiinference.model.TextContent;
import com.oracle.bmc.generativeaiinference.model.UserMessage;
import com.oracle.bmc.generativeaiinference.requests.ChatRequest;
import com.oracle.bmc.generativeaiinference.responses.ChatResponse;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.doubledimple.ociserver.utils.oracle.OciUtils.getProvider;

/**
 * Oracle Cloud AI 对话工具类
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
/*@Slf4j
@Component
public class OciAiChatUtils {

    // 默认使用的模型ID
    private static final List<String> NOT_SUPPORT_MODELS =
            Arrays.asList("cohere.command-r-plus","cohere.embed-multilingual-v3.0","meta.llama-3-70b-instruct");

    // 静态实例，用于静态方法调用
    private static OciAiClientManager clientManager;

    @Autowired
    public void setClientManager(OciAiClientManager manager) {
        OciAiChatUtils.clientManager = manager;
    }


    *//**
     * AI对话接口 - 可指定模型
     *
     * @param tenant 租户信息
     * @param message 用户消息
     * @param modelId 模型ID (如: "cohere.command-r-plus", "meta.llama-3-70b-instruct")
     * @return AI回复
     *//*
    public String chat(Tenant tenant, String message, String modelId) {
        if (StringUtils.isBlank(modelId)){
            return "当前模型不支持";
        }
        try {
            // 从管理器获取客户端和Provider
            OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
            GenerativeAiInferenceClient aiClient = context.getClient();
            String compartmentId = context.getCompartmentId();

            // 构建用户消息
            List<ChatContent> content = new ArrayList<>();
            TextContent build = TextContent.builder().text(message).build();
            content.add( build);
            UserMessage userMessage = UserMessage.builder().content(content).build();

            // 构建对话历史列表
            List<com.oracle.bmc.generativeaiinference.model.Message> chatHistory = new ArrayList<>();
            chatHistory.add(userMessage);

            GenericChatRequest genericChatRequest = GenericChatRequest.builder()
                    .messages(chatHistory)
                    .maxTokens(1000)
                    .temperature(0.7)
                    //.frequencyPenalty(0.0)
                    //.presencePenalty(0.0)
                    .topP(0.95)
                    //.topK(0)
                    .build();

            // 构建对话请求
            ChatDetails chatDetails = ChatDetails.builder()
                    .servingMode(OnDemandServingMode.builder()
                            .modelId(modelId)
                            .build())
                    .chatRequest(genericChatRequest)
                    .compartmentId(compartmentId)
                    .build();

            ChatRequest request = ChatRequest.builder()
                    .chatDetails(chatDetails)
                    .build();

            // 发送请求并获取回复
            ChatResponse response = aiClient.chat(request);

            // 根据不同模型类型提取回复文本
            String aiReply = extractTextFromChatResponse(response);
            log.debug("AI对话完成，模型: {}, 消息长度: {} -> 回复长度: {}",
                    modelId, message.length(), aiReply.length());

            return aiReply;

        } catch (Exception e) {
            log.error("AI对话失败: {}", e.getMessage(), e);
            return "抱歉，AI服务暂时不可用：" + e.getMessage();
        }
    }

    *//**
     * 多轮对话接口
     *
     * @param tenant 租户信息
     * @param messages 对话历史消息列表
     * @param modelId 模型ID
     * @return AI回复
     *//*
    public String chatWithHistory(Tenant tenant, List<Map<String, String>> messages, String modelId) {
        try {
            // 从管理器获取客户端和Provider
            OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
            GenerativeAiInferenceClient aiClient = context.getClient();
            String compartmentId = context.getCompartmentId();

            // 根据模型类型选择不同的请求格式
            if (modelId.startsWith("cohere.")) {
                return chatWithHistoryCohere(aiClient, compartmentId, messages, modelId);
            } else {
                return chatWithHistoryGeneric(aiClient, compartmentId, messages, modelId);
            }

        } catch (Exception e) {
            log.error("多轮对话失败: {}", e.getMessage(), e);
            return "抱歉，多轮对话服务暂时不可用：" + e.getMessage();
        }
    }

    private String chatWithHistoryCohere(GenerativeAiInferenceClient aiClient, String compartmentId,
                                         List<Map<String, String>> messages, String modelId) {
        List<CohereMessage> chatHistory = new ArrayList<>();
        String lastUserMessage = "";

        // 添加系统消息来控制行为
        CohereSystemMessage systemMessage = CohereSystemMessage.builder()
                .message("你是一个智能助手。请基于对话历史回答用户的最新问题，保持上下文连贯，但不要重复回答之前已经回答过的问题。")
                .build();
        chatHistory.add(systemMessage);

        // 限制历史消息数量
        int maxHistorySize = 10; // 最多保留10条历史消息
        int startIndex = Math.max(0, messages.size() - maxHistorySize);

        for (int i = startIndex; i < messages.size(); i++) {
            Map<String, String> msg = messages.get(i);
            String role = msg.get("role");
            String content = msg.get("content");

            if ("user".equals(role)) {
                if (i == messages.size() - 1) {
                    // 最后一条用户消息单独处理
                    lastUserMessage = content;
                } else {
                    // 历史用户消息
                    CohereUserMessage userMessage = CohereUserMessage.builder()
                            .message(content)
                            .build();
                    chatHistory.add(userMessage);
                }
            } else if ("assistant".equals(role) && i < messages.size() - 1) {
                // 只添加历史的助手回复，不包括最新的
                CohereChatBotMessage assistantMessage = CohereChatBotMessage.builder()
                        .message(content)
                        .build();
                chatHistory.add(assistantMessage);
            }
        }

        // 构建对话请求
        ChatDetails chatDetails = ChatDetails.builder()
                .servingMode(OnDemandServingMode.builder()
                        .modelId(modelId)
                        .build())
                .chatRequest(CohereChatRequest.builder()
                        .chatHistory(chatHistory)
                        .message(lastUserMessage)
                        .maxTokens(1000)
                        .temperature(0.7)
                        .build())
                .compartmentId(compartmentId)
                .build();

        ChatRequest request = ChatRequest.builder()
                .chatDetails(chatDetails)
                .build();

        ChatResponse response = aiClient.chat(request);
        return extractTextFromChatResponse(response);
    }

    *//**
     * 使用 Generic 格式的多轮对话
     *//*
    private String chatWithHistoryGeneric(GenerativeAiInferenceClient aiClient, String compartmentId,
                                          List<Map<String, String>> messages, String modelId) {

        // 分离最新问题和历史上下文
        String currentQuestion = "";
        List<Map<String, String>> contextMessages = new ArrayList<>();

        // 找出最新的用户问题
        for (int i = messages.size() - 1; i >= 0; i--) {
            Map<String, String> msg = messages.get(i);
            if ("user".equals(msg.get("role"))) {
                currentQuestion = msg.get("content");
                // 获取这个问题之前的所有历史作为上下文
                if (i > 0) {
                    contextMessages = messages.subList(0, i);
                }
                break;
            }
        }

        // 构建带上下文的提示词
        String finalPrompt = buildContextAwarePrompt(currentQuestion, contextMessages);

        // 创建单个用户消息请求
        List<ChatContent> contentList = new ArrayList<>();
        TextContent textContent = TextContent.builder().text(finalPrompt).build();
        contentList.add(textContent);

        UserMessage userMessage = UserMessage.builder().content(contentList).build();
        List<com.oracle.bmc.generativeaiinference.model.Message> chatHistory = new ArrayList<>();
        chatHistory.add(userMessage);

        GenericChatRequest genericChatRequest = GenericChatRequest.builder()
                .messages(chatHistory)
                .maxTokens(1000)
                .temperature(0.7)
                .topP(0.95)
                .build();

        ChatDetails chatDetails = ChatDetails.builder()
                .servingMode(OnDemandServingMode.builder()
                        .modelId(modelId)
                        .build())
                .chatRequest(genericChatRequest)
                .compartmentId(compartmentId)
                .build();

        ChatRequest request = ChatRequest.builder()
                .chatDetails(chatDetails)
                .build();

        ChatResponse response = aiClient.chat(request);
        return extractTextFromChatResponse(response);
    }

    *//**
     * 构建带上下文的提示词
     *//*
    private String buildContextAwarePrompt(String currentQuestion, List<Map<String, String>> contextMessages) {
        if (contextMessages.isEmpty()) {
            return currentQuestion;
        }

        StringBuilder prompt = new StringBuilder();

        // 添加系统指令
        prompt.append("你是一个有记忆的AI助手。基于之前的对话历史来回答当前问题，但只需要回答当前问题，不要重复之前的回答。\n\n");

        // 添加历史上下文（限制长度避免token超限）
        prompt.append("【对话历史】\n");
        int maxContextRounds = 5; // 最多包含最近5轮对话
        int startIndex = Math.max(0, contextMessages.size() - (maxContextRounds * 2));

        for (int i = startIndex; i < contextMessages.size(); i++) {
            Map<String, String> msg = contextMessages.get(i);
            String role = msg.get("role");
            String content = msg.get("content");

            // 简化历史内容，避免过长
            String simplifiedContent = content.length() > 200 ?
                    content.substring(0, 200) + "..." : content;

            if ("user".equals(role)) {
                prompt.append("用户: ").append(simplifiedContent).append("\n");
            } else if ("assistant".equals(role)) {
                prompt.append("助手: ").append(simplifiedContent).append("\n");
            }
        }

        // 添加当前问题
        prompt.append("\n【当前问题】\n");
        prompt.append(currentQuestion);
        prompt.append("\n\n请只回答当前问题，可以参考对话历史但不要重复之前的回答。");

        return prompt.toString();
    }

    *//**
     * 从ChatResponse中提取文本回复
     * 根据不同的模型类型处理响应结构
     *//*
    private String extractTextFromChatResponse(ChatResponse chatResponse) {
        try {
            BaseChatResponse baseChatResponse = chatResponse.getChatResult().getChatResponse();

            if (baseChatResponse instanceof CohereChatResponse) {
                // Cohere模型的响应结构
                CohereChatResponse cohereChatResponse = (CohereChatResponse) baseChatResponse;
                return cohereChatResponse.getText();

            } else if (baseChatResponse instanceof GenericChatResponse) {
                // Llama等其他模型的响应结构
                GenericChatResponse genericChatResponse = (GenericChatResponse) baseChatResponse;
                List<ChatChoice> choices = genericChatResponse.getChoices();

                if (!choices.isEmpty()) {
                    ChatChoice choice = choices.get(0);
                    List<ChatContent> contents = choice.getMessage().getContent();

                    if (!contents.isEmpty()) {
                        ChatContent content = contents.get(0);
                        if (content instanceof TextContent) {
                            return ((TextContent) content).getText();
                        }
                    }
                }
            }

            log.warn("无法从ChatResponse中提取文本，响应类型: {}",
                    baseChatResponse.getClass().getSimpleName());
            return "收到了回复，但无法解析文本内容。";

        } catch (Exception e) {
            log.error("提取ChatResponse文本失败: {}", e.getMessage(), e);
            return "解析AI回复时出现错误。";
        }
    }

    *//**
     * 检查AI服务是否可用
     *
     * @param tenant 租户信息
     * @return 服务状态
     *//*
    public boolean isAiServiceAvailable(Tenant tenant,String modelId) {
        try {
            String testMessage = "Hello";
            String response = chat(tenant, testMessage,modelId);
            return response != null && !response.contains("暂时不可用");
        } catch (Exception e) {
            log.error("检查AI服务可用性失败: {}", e.getMessage());
            return false;
        }
    }

    *//**
     * 预热客户端连接
     * 在应用启动或用户登录时调用，提前创建客户端
     *//*
    public void warmupClient(Tenant tenant) {
        try {
            clientManager.getClient(tenant);
            log.info("加载AI客户端成功 - 租户: {}", tenant.getTenantId());
        } catch (Exception e) {
            log.error("加载AI客户端失败 - 租户: {}", tenant.getTenantId(), e);
        }
    }

    *//**
     * 清理特定租户的客户端
     * 在用户登出或租户信息变更时调用
     *//*
    public void cleanupClient(Tenant tenant) {
        clientManager.removeClient(tenant);
    }

    //获取所有可用的模型
    public List<com.oracle.bmc.generativeai.model.ModelSummary> getAllAvailableModels(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        GenerativeAiClient client = GenerativeAiClient.builder()
                .build(provider);

        com.oracle.bmc.generativeai.requests.ListModelsRequest request = com.oracle.bmc.generativeai.requests.ListModelsRequest.builder()
                .compartmentId(provider.getTenantId())
                .lifecycleState(Model.LifecycleState.Active)
                .build();
        return client.listModels(request).getModelCollection().getItems().stream()
                .filter(model -> !NOT_SUPPORT_MODELS.contains(model.getDisplayName()))
                .collect(Collectors.toList());
    }
}*/
