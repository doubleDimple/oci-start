package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.TelegramUser;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface TelegramUserRepository extends JpaRepository<TelegramUser, Long> {

    Optional<TelegramUser> findByUserId(Long userId);

    boolean existsByUserIdAndIsAuthorized(Long userId, Boolean isAuthorized);
}
