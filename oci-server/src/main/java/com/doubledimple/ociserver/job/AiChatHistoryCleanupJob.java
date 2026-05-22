package com.doubledimple.ociserver.job;

import com.doubledimple.dao.repository.AiChatHistoryRepository;
import lombok.extern.slf4j.Slf4j;
import org.quartz.DisallowConcurrentExecution;
import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

/**
 * AI聊天历史记录清理 Quartz Job
 * 定时清理过期的聊天历史，防止数据库膨胀
 *
 * @author doubleDimple
 */
@Slf4j
@Component
@DisallowConcurrentExecution
public class AiChatHistoryCleanupJob implements Job {

    private static final int EXPIRE_DAYS = 7;

    private final AiChatHistoryRepository aiChatHistoryRepository;

    @Autowired
    public AiChatHistoryCleanupJob(AiChatHistoryRepository aiChatHistoryRepository) {
        this.aiChatHistoryRepository = aiChatHistoryRepository;
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        try {
            LocalDateTime expireTime = LocalDateTime.now().minusDays(EXPIRE_DAYS);
            int deleted = aiChatHistoryRepository.deleteByCreatedAtBefore(expireTime);
            if (deleted > 0) {
                log.info("AI聊天历史清理完成，删除{}条{}天前的记录", deleted, EXPIRE_DAYS);
            }
        } catch (Exception e) {
            log.error("AI聊天历史清理任务执行失败: {}", e.getMessage(), e);
        }
    }
}
