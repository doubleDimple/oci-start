package com.doubledimple.ocicommon.param;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName Response
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-12 11:26
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class AiChatResp {

    /**
    * chat ai reply
    */
    private String aiReply;

    /**
     * 【新增】：接收底层模型返回的工具调用指令列表
     */
    private List<ChatMessage.ToolCall> toolCalls;
}
