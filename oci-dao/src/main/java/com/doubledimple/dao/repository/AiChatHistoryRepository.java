package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.AiChatHistory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * AI聊天历史记录仓库
 *
 * @author doubleDimple
 */
@Repository
public interface AiChatHistoryRepository extends JpaRepository<AiChatHistory, Long> {

    /**
     * 查询用户最近N条聊天记录（按时间升序，用于构建上下文）
     */
    @Query("SELECT h FROM AiChatHistory h WHERE h.userId = :userId ORDER BY h.createdAt DESC")
    List<AiChatHistory> findRecentByUserId(@Param("userId") String userId);

    /**
     * 查询用户的聊天记录数量
     */
    long countByUserId(String userId);

    /**
     * 删除指定时间之前的历史记录
     */
    @Modifying
    @Transactional
    @Query("DELETE FROM AiChatHistory h WHERE h.createdAt < :expireTime")
    int deleteByCreatedAtBefore(@Param("expireTime") LocalDateTime expireTime);

    /**
     * 删除用户最旧的记录，只保留最近maxCount条
     */
    @Modifying
    @Transactional
    @Query("DELETE FROM AiChatHistory h WHERE h.userId = :userId AND h.id NOT IN " +
            "(SELECT h2.id FROM AiChatHistory h2 WHERE h2.userId = :userId ORDER BY h2.createdAt DESC)")
    void deleteOldestByUserId(@Param("userId") String userId);
}
