package com.doubledimple.dao.entity;

import lombok.Data;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.Lob;
import javax.persistence.Table;
import java.time.LocalDateTime;

/**
 * AI聊天历史记录实体
 * 替代内存中的ConcurrentHashMap存储，降低内存占用
 *
 * @author doubleDimple
 */
@Data
@Entity
@Table(name = "ai_chat_history", indexes = {
        @Index(name = "idx_user_id", columnList = "user_id"),
        @Index(name = "idx_user_created", columnList = "user_id, created_at")
})
public class AiChatHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 用户ID
     */
    @Column(name = "user_id", nullable = false, length = 64)
    private String userId;

    /**
     * 角色：user 或 assistant
     */
    @Column(name = "role", nullable = false, length = 16)
    private String role;

    /**
     * 消息内容
     */
    @Lob
    @Column(name = "content", nullable = false)
    private String content;

    /**
     * 使用的模型ID
     */
    @Column(name = "model_id", length = 128)
    private String modelId;

    /**
     * 创建时间
     */
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    public AiChatHistory() {
    }

    public AiChatHistory(String userId, String role, String content, String modelId) {
        this.userId = userId;
        this.role = role;
        this.content = content;
        this.modelId = modelId;
        this.createdAt = LocalDateTime.now();
    }
}
