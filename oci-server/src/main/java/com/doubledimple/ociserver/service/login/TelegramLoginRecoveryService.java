package com.doubledimple.ociserver.service.login;

import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.dao.repository.TenantRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;

/** Telegram-only recovery; transport identity is checked again inside the persistent global-state lock. */
@Service
@Slf4j
public class TelegramLoginRecoveryService {
    @Resource private GlobalLoginGuard globalLoginGuard;
    @Resource private LoginUserRepository loginUserRepository;
    @Resource private TenantRepository tenantRepository;

    public enum RecoveryResult { SUCCESS, REJECTED, RATE_LIMITED, UNAVAILABLE }

    public RecoveryResult recover(long chatId, long fromId, String currentBotToken,
                                  String username, String recoveryCode, String tenantName) {
        try {
            String user = username == null ? "" : username.trim();
            String tenant = tenantName == null ? "" : tenantName.trim();
            return globalLoginGuard.recover(chatId, fromId, currentBotToken, recoveryCode,
                    () -> !user.isEmpty() && user.length() <= 256 && !tenant.isEmpty() && tenant.length() <= 256
                            && loginUserRepository.existsByUsername(user) && tenantRepository.countByRecoveryName(tenant) > 0);
        } catch (RuntimeException failure) {
            log.warn("Telegram 登录恢复未完成，异常类型：{}", failure.getClass().getSimpleName());
            return RecoveryResult.UNAVAILABLE;
        }
    }
}
