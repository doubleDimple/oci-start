package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.OpenBootLock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
public interface OpenBootLockRepository extends JpaRepository<OpenBootLock, String>, JpaSpecificationExecutor<OpenBootLock> {

    /**
     * 根据状态删除记录
     * 用于应用启动时 (CommandLineRunner) 清理所有 status = 'PROCESSING' 的僵尸记录
     *
     * @param status 状态值
     * @return 删除的行数
     */
    @Modifying
    @Transactional
    @Query("DELETE FROM OpenBootLock o WHERE o.status = :status")
    int deleteByStatus(String status);


    @Modifying
    @Transactional
    @Query("delete from OpenBootLock o where o.taskId = ?1")
    void deleteByLockId(String taskId);
}
