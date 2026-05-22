package com.doubledimple.ocicommon.param;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@AllArgsConstructor
@NoArgsConstructor
public  class ChatMessage {
    private String role;
    private String content;

    // 【新增核心字段】：接收模型发出的工具调用指令
    private List<ToolCall> tool_calls;

    // 手动保留一个只传 role 和 content 的构造函数，
    // 这样你之前老代码里 new ChatMessage("assistant", aiReply) 就不会报错了
    public ChatMessage(String role, String content) {
        this.role = role;
        this.content = content;
    }

    // ======== 【新增内部类：定义工具调用结构】 ========

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ToolCall {
        private String id;     // 调用的唯一ID，比如 "call_abc123"
        private String type;   // 默认通常是 "function"
        private Function function;
    }

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Function {
        private String name;       // 大模型想要调用的工具名称，比如 "queryOrder"
        private String arguments;  // ⚠️注意：大模型返回的参数是一个 JSON 格式的字符串，不是对象！
    }
}
