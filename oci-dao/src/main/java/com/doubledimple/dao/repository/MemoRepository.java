package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.Memo;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface MemoRepository extends JpaRepository<Memo, Long> {
    // 按创建时间倒序查找所有备忘录
    List<Memo> findAllByOrderByCreateTimeDesc();
}
