package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.Message;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface MessageRepository extends JpaRepository<Message, Long>, JpaSpecificationExecutor<Message> {



    /**
     * 全部设置为已读
     */
    @Modifying
    @Query(
            "update Message m " +
                    "   set m.readStatus = 1, " +
                    "       m.updateTime = CURRENT_TIMESTAMP"
    )
    int markAllAsRead();


    //查询消息详情
    public Message findMessageByBusinessId(String businessId);

    //查询未读消息数量
    public Long countByReadStatus(Integer readStatus);
}
