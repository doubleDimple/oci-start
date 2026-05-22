package com.doubledimple.ociserver.pojo.domain.dto;

import lombok.Data;

/**
 * 内存任务模型
 */
@Data
public class MemoryTask {
    private String taskId;              // 任务ID（BootId）
    private int interval;               // 间隔时间（秒）
    private long nextExecuteAt;         // 下次执行时间（毫秒时间戳）
    private Integer status;             // 任务状态：PENDING, COMPLETED
    private User user;                  // 用户信息
    private int executeCount = 0;       // 执行计数
    private long createTime;            // 创建时间
    private long lastExecuteTime;       // 最后执行时间

    public MemoryTask() {
        this.createTime = System.currentTimeMillis();
    }
}
