package com.doubledimple.ociai.utils;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.param.AiChatResp;
import com.doubledimple.ocicommon.param.ChatMessage;
import com.doubledimple.ocicommon.param.OpenAIChatRequest;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.generativeai.GenerativeAiClient;
import com.oracle.bmc.generativeai.model.Model;
import com.oracle.bmc.generativeai.model.ModelCapability;
import com.oracle.bmc.generativeai.requests.ListModelsRequest;
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

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static com.doubledimple.ociai.utils.OciUtils.getProvider;

/**
 * Oracle Cloud AI 对话工具类
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Slf4j
@Component
public class OciAiChatUtils {

    private static final String DEFAULT_PROMPT_WORD = "你是一个智能助手。请基于对话历史回答用户的最新问题，保持上下文连贯，但不要重复回答之前已经回答过的问题。";
    private static final String DEFAULT_PROMPT_WORD_2 = "你是一个有记忆的AI助手。基于之前的对话历史来回答当前问题，但只需要回答当前问题，不要重复之前的回答。\n\n";

    // 静态实例，用于静态方法调用
    private static OciAiClientManager clientManager;

    @Autowired
    public void setClientManager(OciAiClientManager manager) {
        OciAiChatUtils.clientManager = manager;
    }


    /**
     * AI对话接口 - 可指定模型
     *
     * @param tenant 租户信息
     * @param message 用户消息
     * @param modelId 模型ID (如: "cohere.command-r-plus", "meta.llama-3-70b-instruct")
     * @return AI回复
     */
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
                    .maxTokens(4096)
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

    /**
     * 多轮对话接口
     *
     * @param tenant 租户信息
     * @param messages 对话历史消息列表
     * @param modelId 模型ID
     * @return AI回复
     */
    public String chatWithHistory(Tenant tenant, List<Map<String, String>> messages, String modelId,String promptWord) {
        try {
            OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
            GenerativeAiInferenceClient aiClient = context.getClient();
            String compartmentId = context.getCompartmentId();
            if (modelId.startsWith("cohere.")) {
                return chatWithHistoryCohere(aiClient, compartmentId, messages, modelId,promptWord);
            } else {
                return chatWithHistoryGeneric(aiClient, compartmentId, messages, modelId,promptWord);
            }

        } catch (Exception e) {
            log.error("多轮对话失败: {}", e.getMessage(), e);
            return "抱歉，多轮对话服务暂时不可用：" + e.getMessage();
        }
    }

    private String chatWithHistoryCohere(GenerativeAiInferenceClient aiClient, String compartmentId,
                                         List<Map<String, String>> messages, String modelId,String promptWord) {
        List<CohereMessage> chatHistory = new ArrayList<>();
        String lastUserMessage = "";
        if (StringUtils.isBlank(promptWord)){
            promptWord = DEFAULT_PROMPT_WORD;
        }
        // 添加系统消息来控制行为
        CohereSystemMessage systemMessage = CohereSystemMessage.builder()
                .message(promptWord)
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
                        .maxTokens(4096)
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

    /**
     * 使用 Generic 格式的多轮对话
     */
    private String chatWithHistoryGeneric(GenerativeAiInferenceClient aiClient, String compartmentId,
                                          List<Map<String, String>> messages, String modelId,String promptWord) {

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
        String finalPrompt = buildContextAwarePrompt(currentQuestion, contextMessages,promptWord);

        // 创建单个用户消息请求
        List<ChatContent> contentList = new ArrayList<>();
        TextContent textContent = TextContent.builder().text(finalPrompt).build();
        contentList.add(textContent);

        UserMessage userMessage = UserMessage.builder().content(contentList).build();
        List<com.oracle.bmc.generativeaiinference.model.Message> chatHistory = new ArrayList<>();
        chatHistory.add(userMessage);

        GenericChatRequest genericChatRequest = GenericChatRequest.builder()
                .messages(chatHistory)
                .maxTokens(4096)
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

    /**
     * 构建带上下文的提示词
     */
    public String buildContextAwarePrompt(String currentQuestion, List<Map<String, String>> contextMessages,String promptWord) {
        if (contextMessages.isEmpty()) {
            return currentQuestion;
        }
        if (StringUtils.isBlank(promptWord)){
            promptWord = DEFAULT_PROMPT_WORD_2;
        }
        StringBuilder prompt = new StringBuilder();

        // 添加系统指令
        prompt.append(promptWord);

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

    /**
     * 从ChatResponse中提取文本回复
     * 根据不同的模型类型处理响应结构
     */
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

    /**
     * 检查AI服务是否可用
     *
     * @param tenant 租户信息
     * @return 服务状态
     */
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

    /**
     * 预热客户端连接
     * 在应用启动或用户登录时调用，提前创建客户端
     */
    public void warmupClient(Tenant tenant) {
        try {
            clientManager.getClient(tenant);
            log.info("加载AI客户端成功 - 租户: {}", tenant.getTenantId());
        } catch (Exception e) {
            log.error("加载AI客户端失败 - 租户: {}", tenant.getTenantId(), e);
        }
    }

    /**
     * 清理特定租户的客户端
     * 在用户登出或租户信息变更时调用
     */
    public void cleanupClient(Tenant tenant) {
        clientManager.removeClient(tenant);
    }

    //获取所有可用的模型
    public List<com.oracle.bmc.generativeai.model.ModelSummary> getAllAvailableModels(Tenant tenant) {
        SimpleAuthenticationDetailsProvider provider = getProvider(tenant);
        GenerativeAiClient client = GenerativeAiClient.builder()
                .build(provider);

        ListModelsRequest request = com.oracle.bmc.generativeai.requests.ListModelsRequest.builder()
                .compartmentId(provider.getTenantId())
                .lifecycleState(Model.LifecycleState.Active)
                .build();

        java.util.Date now = new java.util.Date();

        return client.listModels(request).getModelCollection().getItems().stream()
                .filter(model -> {
                    List<ModelCapability> capabilities = model.getCapabilities();
                    if (capabilities == null) return false;
                    boolean canChat = capabilities.contains(ModelCapability.Chat);
                    boolean canGenImage = capabilities.contains(ModelCapability.TextToImage);

                    boolean notRetired = model.getTimeOnDemandRetired() == null ||
                            model.getTimeOnDemandRetired().after(now);

                    return (canChat || canGenImage) && notRetired;
                })
                .collect(Collectors.toList());
    }

    /**
     * 流式对话 - 解析 OCI 事件流并回调
     */
    public void chatWithStream(Tenant tenant, String message, String modelId, java.util.function.Consumer<String> chunkConsumer) {
        try {
            OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
            GenerativeAiInferenceClient aiClient = context.getClient();

            GenericChatRequest genericChatRequest = GenericChatRequest.builder()
                    .messages(Arrays.asList(UserMessage.builder()
                            .content(Arrays.asList(TextContent.builder().text(message).build()))
                            .build()))
                    .maxTokens(4096)
                    .isStream(true)
                    .build();

            ChatDetails chatDetails = ChatDetails.builder()
                    .servingMode(OnDemandServingMode.builder().modelId(modelId).build())
                    .chatRequest(genericChatRequest)
                    .compartmentId(context.getCompartmentId())
                    .build();

            ChatRequest request = ChatRequest.builder().chatDetails(chatDetails).build();
            ChatResponse response = aiClient.chat(request);

            // 从源码返回的 entity 中获取 eventStream
            try (java.io.InputStream is = response.getEventStream();
                 java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(is, java.nio.charset.StandardCharsets.UTF_8))) {

                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.startsWith("data:")) {
                        String data = line.substring(5).trim();
                        if ("[DONE]".equals(data)) break;

                        // 使用 Fastjson 提取文本
                        String textPart = parseWithFastjson(data);
                        if (StringUtils.isNotEmpty(textPart)) {
                            chunkConsumer.accept(textPart);
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.error("OCI AI 流式处理异常", e);
            chunkConsumer.accept(" [AI服务异常: " + e.getMessage() + "]");
        }
    }

    public void chatWithStreamSse(Tenant tenant, String message, String modelId, java.util.function.Consumer<String> chunkConsumer) {
        try {
            OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
            GenerativeAiInferenceClient aiClient = context.getClient();

            GenericChatRequest genericChatRequest = GenericChatRequest.builder()
                    .messages(Arrays.asList(UserMessage.builder()
                            .content(Arrays.asList(TextContent.builder().text(message).build()))
                            .build()))
                    .maxTokens(4096)
                    .isStream(true)
                    .build();

            ChatDetails chatDetails = ChatDetails.builder()
                    .servingMode(OnDemandServingMode.builder().modelId(modelId).build())
                    .chatRequest(genericChatRequest)
                    .compartmentId(context.getCompartmentId())
                    .build();

            ChatRequest request = ChatRequest.builder().chatDetails(chatDetails).build();
            ChatResponse response = aiClient.chat(request);

            try (java.io.InputStream is = response.getEventStream();
                 java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(is, java.nio.charset.StandardCharsets.UTF_8))) {

                String line;
                while ((line = reader.readLine()) != null) {
                    if (StringUtils.isBlank(line) || line.startsWith(":")) {
                        continue;
                    }

                    if (line.startsWith("data:")) {
                        String data = line.substring(5);
                        if (data.trim().equals("[DONE]")) {
                            break;
                        }
                        String textPart = parseWithFastjson(data.trim());
                        if (StringUtils.isNotEmpty(textPart)) {
                            chunkConsumer.accept(textPart);
                        }
                    } else {
                        String textPart = parseWithFastjson(line.trim());
                        if (StringUtils.isNotEmpty(textPart)) {
                            chunkConsumer.accept(textPart);
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.error("OCI AI 流式处理异常", e);
            chunkConsumer.accept(" [AI服务异常: " + e.getMessage() + "]");
        }
    }

    public void chatWithHistoryStream(Tenant tenant, List<Map<String, String>> history, String modelId, java.util.function.Consumer<String> chunkConsumer,String promptWord) {
        try {
            OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
            GenerativeAiInferenceClient aiClient = context.getClient();
            String currentQuestion = "";
            List<Map<String, String>> contextMessages = new ArrayList<>();
            for (int i = history.size() - 1; i >= 0; i--) {
                Map<String, String> msg = history.get(i);
                if ("user".equals(msg.get("role"))) {
                    currentQuestion = msg.get("content");
                    if (i > 0) contextMessages = history.subList(0, i);
                    break;
                }
            }

            String finalPrompt = buildContextAwarePrompt(currentQuestion, contextMessages,promptWord);
            GenericChatRequest genericChatRequest = GenericChatRequest.builder()
                    .messages(Arrays.asList(UserMessage.builder()
                            .content(Arrays.asList(TextContent.builder().text(finalPrompt).build()))
                            .build()))
                    .maxTokens(4096)
                    .isStream(true)
                    .build();

            ChatDetails chatDetails = ChatDetails.builder()
                    .servingMode(OnDemandServingMode.builder().modelId(modelId).build())
                    .chatRequest(genericChatRequest)
                    .compartmentId(context.getCompartmentId())
                    .build();

            ChatRequest request = ChatRequest.builder().chatDetails(chatDetails).build();
            ChatResponse response = aiClient.chat(request);

            // 4. 解析流
            try (java.io.InputStream is = response.getEventStream();
                 java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(is, java.nio.charset.StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.startsWith("data:")) {
                        String data = line.substring(5).trim();
                        if ("[DONE]".equals(data)) break;
                        String textPart = parseWithFastjson(data);
                        if (StringUtils.isNotEmpty(textPart)) {
                            chunkConsumer.accept(textPart);
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.error("OCI AI 流式历史对话异常", e);
            chunkConsumer.accept(" [AI服务异常: " + e.getMessage() + "]");
        }
    }

    private String parseWithFastjson(String json) {
        try {
            JSONObject root = JSON.parseObject(json);
            return root.getJSONObject("message")
                    .getJSONArray("content")
                    .getJSONObject(0)
                    .getString("text");
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * 支持 Function Calling 的完整对话请求
     * 兼容 OCI 上的 Cohere 和 Llama 模型，通过 System Prompt 注入实现 OpenAI 协议对齐
     */
    /**
     * 支持 Function Calling 的完整对话请求 (已修复死循环Bug)
     */
    public AiChatResp chatWithFunctionCalling(Tenant tenant, OpenAIChatRequest request, String modelId) {
        OciAiClientManager.ClientContext context = clientManager.getClientContext(tenant);
        GenerativeAiInferenceClient aiClient = context.getClient();
        String compartmentId = context.getCompartmentId();

        AiChatResp resp = new AiChatResp();

        boolean isSecondRound = false; // 标记当前是否为带有工具结果的第二轮请求
        List<Map<String, String>> history = new java.util.ArrayList<>();

        for (ChatMessage m : request.getMessages()) {
            Map<String, String> map = new java.util.HashMap<>();
            String role = m.getRole();
            String content = m.getContent();

            if ("tool".equals(role) || "function".equals(role)) {
                // 拦截到了 Spring AI 返回的工具执行结果！
                isSecondRound = true;
                // 把它伪装成 user 消息，强行喂给底层 OCI 历史解析器
                map.put("role", "user");
                map.put("content", "【系统内部工具已执行完毕，返回了以下真实数据】：\n" + content + "\n\n请严格基于上述数据，用自然语言回答我一开始的问题。");
            } else if ("assistant".equals(role) && StringUtils.isBlank(content)) {
                // 填补上一轮触发工具时的空消息，防止底层解析器报空指针
                map.put("role", "assistant");
                map.put("content", "[我调用了系统工具去查询数据]");
            } else {
                // 正常的用户历史消息
                map.put("role", role);
                map.put("content", content);
            }
            history.add(map);
        }

        boolean hasTools = request.getTools() != null && !request.getTools().isEmpty();

        // ====================================================================
        // 2. 动态构建 System Prompt (按轮次下达不同指令)
        // ====================================================================
        String systemPrompt = DEFAULT_PROMPT_WORD_2;
        if (hasTools && !isSecondRound) {
            // 第一轮：强迫大模型输出 JSON 工具指令
            systemPrompt += "\n\n【最高指令：你拥有以下内部工具(Functions)的调用权限】\n";
            systemPrompt += JSON.toJSONString(request.getTools()) + "\n\n";
            systemPrompt += "【工具调用规则】\n";
            systemPrompt += "1. 如果你需要调用工具，绝对不要输出任何其他解释性自然语言！\n";
            systemPrompt += "2. 必须严格、且仅仅输出以下格式的 JSON 字符串（不要加 markdown 代码块标签）：\n";
            systemPrompt += "{\"tool_calls\": [{\"id\": \"call_" + System.currentTimeMillis() + "\", \"type\": \"function\", \"function\": {\"name\": \"你要调用的工具名称\", \"arguments\": \"{参数对象的JSON字符串}\"}}]}\n";
        } else if (isSecondRound) {
            // 第二轮：警告大模型闭嘴，拿到数据了直接回答，严禁再调工具！
            systemPrompt += "\n\n【最高指令：工具查询已完成！】\n";
            systemPrompt += "请直接用自然语言回答用户的原始问题，展示查到的数据。绝对不要再次输出任何 JSON 或工具调用指令！\n";
        }

        String aiReplyString = "";

        // ====================================================================
        // 3. 调用底层 OCI SDK
        // ====================================================================
        try {
            if (modelId.startsWith("cohere.")) {
                aiReplyString = chatWithHistoryCohere(aiClient, compartmentId, history, modelId, systemPrompt);
            } else {
                aiReplyString = chatWithHistoryGeneric(aiClient, compartmentId, history, modelId, systemPrompt);
            }
        } catch (Exception e) {
            log.error("OCI API 调用失败: {}", e.getMessage(), e);
            resp.setAiReply("底层 AI 服务调用失败：" + e.getMessage());
            return resp;
        }

        log.debug("大模型原始返回内容: \n{}", aiReplyString);

        // ====================================================================
        // 4. 解析结果 (如果是第二轮，直接跳过拦截，强制当做普通文本)
        // ====================================================================
        if (hasTools && !isSecondRound && isToolCallJson(aiReplyString)) {
            try {
                String cleanJson = aiReplyString.replaceAll("```json", "").replaceAll("```", "").trim();
                JSONObject jsonObj = JSON.parseObject(cleanJson);
                if (jsonObj.containsKey("tool_calls")) {
                    List<ChatMessage.ToolCall> toolCalls = jsonObj.getJSONArray("tool_calls").toJavaList(ChatMessage.ToolCall.class);
                    resp.setToolCalls(toolCalls);
                    resp.setAiReply(null);
                    log.info("🎯 成功触发工具调用: {}", JSON.toJSONString(toolCalls));
                    return resp; // 返回给 Spring AI 去执行 Java 方法
                }
            } catch (Exception e) {
                log.error("解析工具调用 JSON 失败，回退到普通文本回复", e);
            }
        }
        resp.setAiReply(aiReplyString);
        return resp;
    }

    /**
     * 辅助方法：快速判断一段文本是不是大模型输出的工具调用 JSON
     */
    private boolean isToolCallJson(String text) {
        if (StringUtils.isBlank(text)) return false;
        String trimmed = text.trim();
        // 应对模型可能多此一举加上 ```json 的情况
        if (trimmed.startsWith("```json")) {
            trimmed = trimmed.substring(7).trim();
        }
        return trimmed.startsWith("{") && trimmed.contains("\"tool_calls\"");
    }
}
