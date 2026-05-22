package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

import java.util.Optional;

public interface LoginUserRepository extends JpaRepository<LoginUser, Long> , JpaSpecificationExecutor<LoginUser> {

    Optional<LoginUser> findByUsername(String username);

    Optional<LoginUser> findByExternalIdAndLoginType(String externalId, LoginTypeEnum loginType);

    boolean existsByUsername(String username);

    // 添加按登录类型统计的方法
    long countByLoginType(LoginTypeEnum loginType);
}
