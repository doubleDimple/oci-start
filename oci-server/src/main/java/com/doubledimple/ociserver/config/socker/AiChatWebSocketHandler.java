package com.doubledimple.ociserver.config.socker;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import javax.annotation.PreDestroy;
import javax.annotation.Resource;
import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.*;

/**
 * AI对话WebSocket处理器
 * 处理与前端的实时AI对话交互
 *
 * @author doubleDimple
 * @date 2025-08-31
 */
@Slf4j
@Component("aiChatWebSocketHandler")
@Qualifier("aiChatWebSocketHandler")
public class AiChatWebSocketHandler extends TextWebSocketHandler {

    @Resource
    TenantRepository tenantRepository;

    @Resource
    ThreadPoolExecutor taskExecutor;

    @Resource
    OciAiChatUtils ociAiChatUtils;

    @Resource
    private ScheduledThreadPoolExecutor delayedTaskExecutor;

    // 存储所有活动的WebSocket会话
    private final Map<String, WebSocketSession> sessions = new ConcurrentHashMap<>();

    // 存储每个会话的对话历史
    private final Map<String, List<Map<String, String>>> conversationHistory = new ConcurrentHashMap<>();

    // 存储每个会话的租户信息
    private final Map<String, Tenant> sessionTenants = new ConcurrentHashMap<>();

    // JSON处理器
    private final ObjectMapper objectMapper = new ObjectMapper();

    // 最大历史消息数量
    private static final int MAX_HISTORY_SIZE = 50;

    // 心跳检测间隔
    private static final long HEARTBEAT_INTERVAL = 30; // 30秒

    // 存储心跳任务
    private final Map<String, ScheduledFuture<?>> heartbeatTasks = new ConcurrentHashMap<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        String sessionId = session.getId();
        sessions.put(sessionId, session);
        conversationHistory.put(sessionId, new ArrayList<>());

        log.info("WebSocket连接建立: sessionId={}, remoteAddress={}",
                sessionId, session.getRemoteAddress());

        // 发送欢迎消息
        sendMessage(session, createMessage("system", "连接成功！AI助手已准备就绪。", "success"));

        // 启动心跳检测
        startHeartbeat(session);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        String sessionId = session.getId();
        String payload = message.getPayload();

        log.debug("收到消息: sessionId={}, message={}", sessionId, payload);

        try {
            Map<String, Object> request = objectMapper.readValue(payload, Map.class);
            String type = (String) request.get("type");

            switch (type) {
                case "chat":
                    handleChatMessage(session, request);
                    break;
                case "init":
                    handleInitMessage(session, request);
                    break;
                case "clear":
                    handleClearHistory(session);
                    break;
                case "ping":
                    handlePing(session);
                    break;
                case "history":
                    handleGetHistory(session);
                    break;
                case "close_session":
                    handleCloseSession(session, request);
                    break;
                default:
                    sendMessage(session, createMessage("error", "未知的消息类型: " + type, "error"));
            }
        } catch (Exception e) {
            log.error("处理消息时出错: sessionId={}", sessionId, e);
            sendMessage(session, createMessage("error", "处理消息失败: " + e.getMessage(), "error"));
        }
    }

    /**
     * 处理聊天消息
     */
    /*private void handleChatMessage(WebSocketSession session, Map<String, Object> request) {
        String sessionId = session.getId();
        String userMessage = (String) request.get("message");
        String modelId = (String) request.get("modelId");
        Long tenantId = Long.valueOf((String) request.get("tenantId"));
        boolean useHistory = (boolean) request.getOrDefault("useHistory", true);

        if (userMessage == null || userMessage.trim().isEmpty()) {
            sendMessage(session, createMessage("error", "消息内容不能为空", "error"));
            return;
        }

        // 获取租户信息
        Tenant tenant = sessionTenants.get(sessionId);
        if (tenant == null) {
            Optional<Tenant> optional = tenantRepository.findById(tenantId);
            if (optional.isPresent()){
                tenant = optional.get();
                sessionTenants.put(sessionId, tenant);
            }else{
                sendMessage(session, createMessage("error", "请先初始化会话（缺少租户信息）", "error"));
                return;
            }
        }

        // 发送"正在输入"状态
        sendMessage(session, createMessage("typing", "AI正在思考...", "typing"));

        // 使用已有的线程池异步处理AI请求
        Tenant finalTenant = tenant;
        CompletableFuture.runAsync(() -> {
            try {
                // 添加用户消息到历史
                List<Map<String, String>> history = conversationHistory.get(sessionId);
                Map<String, String> userMsg = new HashMap<>();
                userMsg.put("role", "user");
                userMsg.put("content", userMessage);
                userMsg.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                history.add(userMsg);

                // 调用AI服务
                String aiResponse;
                if (useHistory && history.size() > 1) {
                    // 使用历史对话
                    aiResponse = ociAiChatUtils.chatWithHistory(finalTenant, history, modelId);
                } else {
                    // 单轮对话
                    aiResponse = ociAiChatUtils.chat(finalTenant, userMessage, modelId);
                }

                // 添加AI回复到历史
                Map<String, String> aiMsg = new HashMap<>();
                aiMsg.put("role", "assistant");
                aiMsg.put("content", aiResponse);
                aiMsg.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                history.add(aiMsg);

                // 限制历史记录大小
                if (history.size() > MAX_HISTORY_SIZE) {
                    history.subList(0, history.size() - MAX_HISTORY_SIZE).clear();
                }

                // 发送AI回复
                Map<String, Object> response = new HashMap<>();
                response.put("type", "chat");
                response.put("role", "assistant");
                response.put("message", aiResponse);
                response.put("model", modelId);
                response.put("timestamp", LocalDateTime.now().toString());
                sendMessage(session, response);

            } catch (Exception e) {
                log.error("AI对话处理失败: sessionId={}", sessionId, e);
                sendMessage(session, createMessage("error", "AI服务暂时不可用: " + e.getMessage(), "error"));
            }
        }, taskExecutor).exceptionally(ex -> {
            log.error("异步任务执行失败: sessionId={}", sessionId, ex);
            sendMessage(session, createMessage("error", "处理请求时发生错误", "error"));
            return null;
        });
    }*/

    /*private void handleChatMessage0(WebSocketSession session, Map<String, Object> request) {
        String sessionId = session.getId();
        String userMessage = (String) request.get("message");
        String modelId = (String) request.get("modelId");
        Object tenantIdObj = request.get("tenantId");
        Long tenantId = tenantIdObj instanceof String ? Long.valueOf((String) tenantIdObj) : ((Number) tenantIdObj).longValue();

        if (userMessage == null || userMessage.trim().isEmpty()) {
            sendMessage(session, createMessage("error", "消息内容不能为空", "error"));
            return;
        }

        // 获取租户信息
        Tenant tenant = sessionTenants.get(sessionId);
        if (tenant == null) {
            tenant = tenantRepository.findById(tenantId).orElse(null);
            if (tenant != null) {
                sessionTenants.put(sessionId, tenant);
            } else {
                sendMessage(session, createMessage("error", "请先初始化会话", "error"));
                return;
            }
        }

        // 针对账号评估逻辑自动增强 Prompt
        String finalPrompt = userMessage;
        if (userMessage.contains("评估") || userMessage.contains("价值")) {
            finalPrompt = "你是一个云账号评估专家。规则：升级号500元，普通号100元。若有ARM资源额外+300元，活跃超一年+200元。请分析此账号：" + userMessage;
        }

        // 发送"正在输入"状态
        sendMessage(session, createMessage("typing", "AI正在思考并逐字生成...", "typing"));

        Tenant finalTenant = tenant;
        String finalInput = finalPrompt;

        CompletableFuture.runAsync(() -> {
            try {
                // 用于累计完整的 AI 回复，稍后存入历史
                StringBuilder fullAiResponse = new StringBuilder();

                // 调用流式 AI 接口
                ociAiChatUtils.chatWithStream(finalTenant, finalInput, modelId, (chunk) -> {
                    fullAiResponse.append(chunk);

                    // 每解析出一个片段，立即推送到前端
                    Map<String, Object> chunkMsg = new HashMap<>();
                    chunkMsg.put("type", "chat");
                    chunkMsg.put("role", "assistant");
                    chunkMsg.put("message", chunk);  // 当前这一个片段（比如“在”）
                    chunkMsg.put("isChunk", true);   // 标识是流片段
                    chunkMsg.put("timestamp", LocalDateTime.now().toString());
                    sendMessage(session, chunkMsg);
                });

                // --- 流结束后的后续处理 ---

                // 1. 将完整的对话存入历史记录
                List<Map<String, String>> history = conversationHistory.get(sessionId);
                if (history != null) {
                    // 用户消息
                    Map<String, String> u = new HashMap<>();
                    u.put("role", "user");
                    u.put("content", userMessage);
                    u.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                    history.add(u);

                    // AI完整回复
                    Map<String, String> a = new HashMap<>();
                    a.put("role", "assistant");
                    a.put("content", fullAiResponse.toString());
                    a.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                    history.add(a);

                    if (history.size() > MAX_HISTORY_SIZE) {
                        history.subList(0, history.size() - MAX_HISTORY_SIZE).clear();
                    }
                }

                // 2. 发送生成完毕的状态
                sendMessage(session, createMessage("chat_end", "生成完毕", "success"));

            } catch (Exception e) {
                log.error("AI流式对话处理失败: sessionId={}", sessionId, e);
                sendMessage(session, createMessage("error", "AI服务异常: " + e.getMessage(), "error"));
            }
        }, taskExecutor);
    }*/

    private void handleChatMessage(WebSocketSession session, Map<String, Object> request) {
        String sessionId = session.getId();
        String userMessage = (String) request.get("message");
        String modelId = (String) request.get("modelId");
        Object tenantIdObj = request.get("tenantId");
        Long tenantId = tenantIdObj instanceof String ? Long.valueOf((String) tenantIdObj) : ((Number) tenantIdObj).longValue();
        boolean useHistory = (boolean) request.getOrDefault("useHistory", true);

        if (userMessage == null || userMessage.trim().isEmpty()) {
            sendMessage(session, createMessage("error", "消息内容不能为空", "error"));
            return;
        }
        Tenant tenant = sessionTenants.get(sessionId);
        if (tenant == null) {
            tenant = tenantRepository.findById(tenantId).orElse(null);
            if (tenant != null) {
                sessionTenants.put(sessionId, tenant);
            } else {
                sendMessage(session, createMessage("error", "请先初始化会话", "error"));
                return;
            }
        }

        sendMessage(session, createMessage("typing", "AI正在思考...", "typing"));

        Tenant finalTenant = tenant;
        CompletableFuture.runAsync(() -> {
            try {
                List<Map<String, String>> history = conversationHistory.get(sessionId);
                Map<String, String> userMsg = new HashMap<>();
                userMsg.put("role", "user");
                userMsg.put("content", userMessage);
                userMsg.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                history.add(userMsg);

                StringBuilder fullAiResponse = new StringBuilder();
                if (useHistory && history.size() > 1) {
                    ociAiChatUtils.chatWithHistoryStream(finalTenant, history, modelId, (chunk) -> {
                        pushChunkToFrontend(session, chunk, fullAiResponse);
                    },null);
                } else {
                    ociAiChatUtils.chatWithStream(finalTenant, userMessage, modelId, (chunk) -> {
                        pushChunkToFrontend(session, chunk, fullAiResponse);
                    });
                }
                Map<String, String> aiMsg = new HashMap<>();
                aiMsg.put("role", "assistant");
                aiMsg.put("content", fullAiResponse.toString());
                aiMsg.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                history.add(aiMsg);
                if (history.size() > MAX_HISTORY_SIZE) {
                    history.subList(0, history.size() - MAX_HISTORY_SIZE).clear();
                }
                sendMessage(session, createMessage("chat_end", "生成完毕", "success"));

            } catch (Exception e) {
                log.error("AI对话处理失败", e);
                sendMessage(session, createMessage("error", "处理请求时发生错误", "error"));
            }
        }, taskExecutor);
    }

    /**
     * 提取重复的推送逻辑
     */
    private void pushChunkToFrontend(WebSocketSession session, String chunk, StringBuilder accumulator) {
        accumulator.append(chunk);
        Map<String, Object> chunkMsg = new HashMap<>();
        chunkMsg.put("type", "chat");
        chunkMsg.put("role", "assistant");
        chunkMsg.put("message", chunk);
        chunkMsg.put("isChunk", true);
        chunkMsg.put("timestamp", LocalDateTime.now().toString());
        sendMessage(session, chunkMsg);
    }

    /**
     * 处理初始化消息（设置租户信息）
     */
    private void handleInitMessage(WebSocketSession session, Map<String, Object> request) {
        String sessionId = session.getId();
        Map<String, Object> tenantData = (Map<String, Object>) request.get("tenant");

        if (tenantData == null) {
            sendMessage(session, createMessage("error", "缺少租户信息", "error"));
            return;
        }

        // 使用线程池异步处理初始化
        CompletableFuture.runAsync(() -> {
            try {
                Map<String, Object> response = new HashMap<>();
                String modelId = (String) tenantData.get("modelId");
                if (StringUtils.isBlank(modelId)){
                    throw new RuntimeException("模型未选择");
                }
                Optional<Tenant> optional = tenantRepository.findById(Long.valueOf((String) tenantData.get("tenantId")));
                Tenant tenant = optional.get();
                sessionTenants.put(sessionId, tenant);
                // 预热客户端连接
                ociAiChatUtils.warmupClient(tenant);

                // 检查AI服务是否可用
                boolean isAvailable = ociAiChatUtils.isAiServiceAvailable(tenant,modelId);

                response.put("type", "init");
                response.put("status", isAvailable ? "success" : "failed");
                response.put("message", isAvailable ? "初始化成功，AI服务已就绪" : "AI服务不可用");
                sendMessage(session, response);

            } catch (Exception e) {
                log.error("初始化失败: sessionId={}", sessionId, e);
                sendMessage(session, createMessage("error", "初始化失败: " + e.getMessage(), "error"));
            }
        }, taskExecutor);
    }

    /**
     * 清除对话历史
     */
    private void handleClearHistory(WebSocketSession session) {
        String sessionId = session.getId();
        conversationHistory.put(sessionId, new ArrayList<>());
        sendMessage(session, createMessage("system", "对话历史已清除", "success"));
        log.info("清除对话历史: sessionId={}", sessionId);
    }

    /**
     * 处理ping消息（心跳）
     */
    private void handlePing(WebSocketSession session) {
        sendMessage(session, createMessage("pong", "pong", "pong"));
    }

    /**
     * 获取对话历史
     */
    private void handleGetHistory(WebSocketSession session) {
        String sessionId = session.getId();
        List<Map<String, String>> history = conversationHistory.get(sessionId);

        Map<String, Object> response = new HashMap<>();
        response.put("type", "history");
        response.put("history", history);
        response.put("count", history.size());
        sendMessage(session, response);
    }

    /**
     * 启动心跳检测
     */
    private void startHeartbeat(WebSocketSession session) {
        String sessionId = session.getId();

        // 使用延时任务线程池进行心跳检测
        ScheduledFuture<?> heartbeatTask = delayedTaskExecutor.scheduleAtFixedRate(() -> {
            try {
                if (session.isOpen()) {
                    sendMessage(session, createMessage("heartbeat", "heartbeat", "heartbeat"));
                } else {
                    // 如果会话已关闭，取消心跳任务
                    cancelHeartbeat(sessionId);
                }
            } catch (Exception e) {
                log.error("心跳发送失败: sessionId={}", sessionId, e);
                cancelHeartbeat(sessionId);
            }
        }, HEARTBEAT_INTERVAL, HEARTBEAT_INTERVAL, TimeUnit.SECONDS);

        heartbeatTasks.put(sessionId, heartbeatTask);
    }

    /**
     * 取消心跳任务
     */
    private void cancelHeartbeat(String sessionId) {
        ScheduledFuture<?> task = heartbeatTasks.remove(sessionId);
        if (task != null && !task.isCancelled()) {
            task.cancel(false);
        }
    }

    /**
     * 创建消息对象
     */
    private Map<String, Object> createMessage(String type, String message, String status) {
        Map<String, Object> msg = new HashMap<>();
        msg.put("type", type);
        msg.put("message", message);
        msg.put("status", status);
        msg.put("timestamp", LocalDateTime.now().toString());
        return msg;
    }

    /**
     * 发送消息到客户端
     */
    private void sendMessage(WebSocketSession session, Map<String, Object> message) {
        try {
            if (session.isOpen()) {
                String json = objectMapper.writeValueAsString(message);
                session.sendMessage(new TextMessage(json));
            }
        } catch (IOException e) {
            log.error("发送消息失败: sessionId={}", session.getId(), e);
        }
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
        log.error("WebSocket传输错误: sessionId={}", session.getId(), exception);
        if (session.isOpen()) {
            session.close();
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) throws Exception {
        String sessionId = session.getId();

        // 清理资源
        sessions.remove(sessionId);
        conversationHistory.remove(sessionId);
        Tenant tenant = sessionTenants.remove(sessionId);

        // 清理AI客户端
        if (tenant != null) {
            ociAiChatUtils.cleanupClient(tenant);
        }

        // 取消心跳任务
        cancelHeartbeat(sessionId);

        log.info("WebSocket连接关闭: sessionId={}, closeStatus={}", sessionId, status);
    }

    @PreDestroy
    public void destroy() {
        log.debug("开始销毁AiChatWebSocketHandler...");

        // 取消所有心跳任务
        heartbeatTasks.values().forEach(task -> {
            if (task != null && !task.isCancelled()) {
                task.cancel(false);
            }
        });
        heartbeatTasks.clear();

        // 关闭所有会话
        sessions.values().forEach(session -> {
            try {
                if (session.isOpen()) {
                    session.close();
                }
            } catch (IOException e) {
                log.error("关闭会话失败", e);
            }
        });

        // 清理所有AI客户端
        sessionTenants.values().forEach(ociAiChatUtils::cleanupClient);

        // 清理资源
        sessions.clear();
        conversationHistory.clear();
        sessionTenants.clear();

        log.debug("AiChatWebSocketHandler已销毁");
    }

    /**
     * 获取当前活动会话数
     */
    public int getActiveSessionCount() {
        return sessions.size();
    }

    /**
     * 处理关闭会话请求
     */
    private void handleCloseSession(WebSocketSession session, Map<String, Object> request) {
        String sessionId = session.getId();
        String reason = (String) request.getOrDefault("reason", "unknown");

        log.info("收到关闭会话请求: sessionId={}, reason={}", sessionId, reason);

        try {
            // 发送确认消息给客户端
            Map<String, Object> response = new HashMap<>();
            response.put("type", "close_session");
            response.put("status", "success");
            response.put("message", "会话即将关闭");
            response.put("timestamp", LocalDateTime.now().toString());
            sendMessage(session, response);

            // 延迟1秒后关闭连接，确保消息发送完成
            delayedTaskExecutor.schedule(() -> {
                try {
                    if (session.isOpen()) {
                        // 清理会话资源
                        cleanupSession(sessionId);
                        // 主动关闭WebSocket连接
                        session.close(CloseStatus.NORMAL.withReason("Session closed by user request"));
                        log.info("会话已按用户请求关闭: sessionId={}", sessionId);
                    }
                } catch (Exception e) {
                    log.error("关闭会话时发生错误: sessionId={}", sessionId, e);
                }
            }, 1, TimeUnit.SECONDS);

        } catch (Exception e) {
            log.error("处理关闭会话请求失败: sessionId={}", sessionId, e);
            sendMessage(session, createMessage("error", "关闭会话失败: " + e.getMessage(), "error"));
        }
    }

    /**
     * 清理指定会话的资源
     */
    private void cleanupSession(String sessionId) {
        try {
            // 移除会话记录
            sessions.remove(sessionId);

            // 清空对话历史
            conversationHistory.remove(sessionId);

            // 获取并清理租户客户端
            Tenant tenant = sessionTenants.remove(sessionId);
            if (tenant != null) {
                ociAiChatUtils.cleanupClient(tenant);
                log.debug("已清理租户AI客户端: tenantId={}", tenant.getId());
            }

            // 取消心跳任务
            cancelHeartbeat(sessionId);

            log.info("会话资源清理完成: sessionId={}", sessionId);

        } catch (Exception e) {
            log.error("清理会话资源时发生错误: sessionId={}", sessionId, e);
        }
    }

    /**
     * 获取线程池状态信息
     */
    public Map<String, Object> getThreadPoolStatus() {
        Map<String, Object> status = new HashMap<>();
        status.put("taskExecutor", getExecutorStatus(taskExecutor));
        status.put("delayedTaskExecutor", getScheduledExecutorStatus(delayedTaskExecutor));
        status.put("activeWebSocketSessions", getActiveSessionCount());
        return status;
    }

    private Map<String, Object> getExecutorStatus(ThreadPoolExecutor executor) {
        Map<String, Object> status = new HashMap<>();
        status.put("activeCount", executor.getActiveCount());
        status.put("completedTaskCount", executor.getCompletedTaskCount());
        status.put("taskCount", executor.getTaskCount());
        status.put("queueSize", executor.getQueue().size());
        status.put("corePoolSize", executor.getCorePoolSize());
        status.put("maximumPoolSize", executor.getMaximumPoolSize());
        return status;
    }

    private Map<String, Object> getScheduledExecutorStatus(ScheduledThreadPoolExecutor executor) {
        Map<String, Object> status = new HashMap<>();
        status.put("activeCount", executor.getActiveCount());
        status.put("completedTaskCount", executor.getCompletedTaskCount());
        status.put("taskCount", executor.getTaskCount());
        status.put("queueSize", executor.getQueue().size());
        status.put("corePoolSize", executor.getCorePoolSize());
        return status;
    }
}
