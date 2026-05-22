package com.doubledimple.ociai.chat;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ocicommon.param.OpenAIChatRequest;
import com.doubledimple.ocicommon.param.OpenAIChatResponse;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.servlet.http.HttpServletResponse;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.function.Consumer;

public interface ChatAiService {

    CompletableFuture<ApiResponse> chat(String userId, String message,String showModelId);

    CompletableFuture<?> chatCompletions(OpenAIChatRequest request, String userId, HttpServletResponse httpResponse);

    void handleStreamResponseSync(OpenAIChatRequest request, String userId, HttpServletResponse httpResponse);

    Map<String, Object> enableModels();

    void analyzeAllTenantsStream(SseEmitter emitter, List<Tenant> content );


    /**
    * @Description:
     * 专为 OpenAI 标准客户端（如 OpenClaw）设计的流式桥接函数
     * 逻辑：OCI Stream -> 包装成 OpenAI Chunk -> 客户端 Response
    * @Param: [com.doubledimple.ocicommon.param.OpenAIChatRequest, javax.servlet.http.HttpServletResponse]
    * @return: void
    * @Author: renyx
    * @Date: 3/4/26 11:28 AM
    */
    void handleOpenAiStreamBridge(OpenAIChatRequest request,String userId, HttpServletResponse response);

    void handleOpenAiStreamBridgeSse(OpenAIChatRequest request, String userId, SseEmitter emitter);

    /**
     * 流式AI对话 - 通过回调逐块返回AI回复
     * 专为Telegram等需要逐步更新消息的场景设计
     *
     * @param userId 用户ID
     * @param message 用户消息
     * @param showModelId 指定模型ID（可为null）
     * @param chunkConsumer 接收每个文本块的回调
     */
    void chatStream(String userId, String message, String showModelId, Consumer<String> chunkConsumer);
}
