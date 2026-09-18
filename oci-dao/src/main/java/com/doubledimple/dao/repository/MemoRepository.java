package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.Memo;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import javax.persistence.LockModeType;

import java.util.List;
import java.util.Optional;

public interface MemoRepository extends JpaRepository<Memo, Long> {
    // 按创建时间倒序查找所有备忘录
    List<Memo> findAllByOrderByCreateTimeDesc();

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from Memo m where m.id = :id")
    Optional<Memo> lockById(@Param("id") Long id);
}
