package com.doubledimple.dao.entity;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.Data;
import lombok.ToString;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.PrePersist;
import javax.persistence.PreUpdate;
import javax.persistence.Table;
import javax.persistence.Transient;
import javax.persistence.Version;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@Entity
@Table(name = "chat_AI_CONFIG")
@ToString
@Data
public class ChatAiConfig {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Version
    @Column(name = "version")
    private Long version;

    @Column(name = "tenantId")
    private String tenantId;

    @Column(name = "modelId",length = 500)
    private String modelId;

    /**
    * 对外展示的ai模型id
    */
    @Column(name = "show_modelId",length = 500)
    private String showModelId;

    @Column(name = "cloud_type")
    private Integer cloudType = 1;

    @Column(name = "model_name")
    private String modelName;

    @Column(name = "provider")
    private String provider;

    @Column(name = "api_key")
    private String apiKey;

    @Column(name = "base_url")
    private String baseUrl;

    @Column(name = "enabled")
    private Boolean enabled = true;

    @Column(name = "system_prompt", columnDefinition = "TEXT")
    private String systemPrompt = "你是一个友好的AI助手，请用简洁明了的方式回答问题。";

    @Column(name = "max_tokens")
    private Integer maxTokens = 4096;

    @Column(name = "temperature")
    private String temperature;

    @Column(name = "max_history_messages", columnDefinition = "INTEGER DEFAULT 10")
    private Integer maxHistoryMessages = 10;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    @Transient
    public String getFormattedCreatedAt() {
        if (createdAt == null) return "";
        return createdAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }

    @Transient
    public String getFormattedUpdatedAt() {
        if (updatedAt == null) return "";
        return updatedAt.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }
}
