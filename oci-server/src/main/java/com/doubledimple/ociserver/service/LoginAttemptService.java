package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.entity.LoginFailureState;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.dao.repository.LoginFailureStateRepository;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.doubledimple.ociserver.service.security.LoginIpTransactions;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

/**
 * 持久化登录失败计数。两个失败类别独立累加，只有完整登录成功或人工解封才清零。
 */
@Service
public class LoginAttemptService {

    private static final int UNKNOWN_USERNAME_THRESHOLD = 2;
    private static final int WRONG_PASSWORD_THRESHOLD = 3;

    private final LoginFailureStateRepository failureRepository;
    private final BanRecordRepository banRepository;
    private final LoginIpTransactions transactions;

    public LoginAttemptService(LoginFailureStateRepository failureRepository,
                               BanRecordRepository banRepository,
                               LoginIpTransactions transactions) {
        this.failureRepository = failureRepository;
        this.banRepository = banRepository;
        this.transactions = transactions;
    }

    public void assertAllowed(String ip) {
        transactions.execute(ip, address -> {
            assertNotBanned(address);
            return null;
        });
    }

    /**
     * 返回前计数与封禁已在同一个独立事务中提交；提交失败时抛出异常，不返回成功结果。
     */
    public FailureResult recordFailure(String ip, boolean unknownUsername) {
        return transactions.execute(ip, address -> {
            int threshold = unknownUsername ? UNKNOWN_USERNAME_THRESHOLD : WRONG_PASSWORD_THRESHOLD;
            LoginFailureState state = failureRepository.findById(address).orElse(null);
            int previousCount = state == null ? 0
                    : unknownUsername ? state.getUnknownUsernameCount() : state.getWrongPasswordCount();
            if (findActiveBan(address) != null) {
                return new FailureResult(previousCount, threshold, unknownUsername, false, true);
            }
            if (state == null) {
                state = new LoginFailureState();
                state.setIpAddress(address);
            }
            int failureCount = Math.min(previousCount + 1, threshold);
            if (unknownUsername) {
                state.setUnknownUsernameCount(failureCount);
            } else {
                state.setWrongPasswordCount(failureCount);
            }
            state.setLastFailureTime(LocalDateTime.now());
            failureRepository.save(state);

            boolean newlyBanned = failureCount >= threshold;
            if (newlyBanned) {
                // 每次重新封禁保留独立记录，已解封记录不可覆盖。
                BanRecord ban = new BanRecord();
                ban.setIpAddress(address);
                ban.setStatus(1);
                ban.setSource("登录失败自动封禁");
                ban.setOperatorName("system");
                ban.setReason(unknownUsername
                        ? "用户名错误累计达到2次，自动封禁来源IP"
                        : "密码错误累计达到3次，自动封禁来源IP");
                ban.setCreateTime(LocalDateTime.now());
                ban.setUnbanTime(null);
                banRepository.save(ban);
            }
            return new FailureResult(failureCount, threshold, unknownUsername, newlyBanned, newlyBanned);
        });
    }

    /**
     * 必须在所有登录步骤（包括二次验证）完成后调用。
     * 已被并发请求封禁时拒绝登录，不能用正确密码清除封禁。
     */
    public void loginSucceeded(String ip) {
        transactions.execute(ip, address -> {
            assertNotBanned(address);
            clearFailures(address);
            return null;
        });
    }

    public void reset(String ip) {
        transactions.execute(ip, address -> {
            clearFailures(address);
            return null;
        });
    }

    private void clearFailures(String ip) {
        failureRepository.findById(ip).ifPresent(failureRepository::delete);
    }

    private BanRecord findActiveBan(String ip) {
        return banRepository.findTopByIpAddressAndStatusOrderByIdDesc(ip, 1);
    }

    private void assertNotBanned(String ip) {
        if (findActiveBan(ip) != null) {
            throw new IpBannedException("您的IP已被封禁");
        }
    }

    public static final class FailureResult {
        private final int failureCount;
        private final int threshold;
        private final boolean unknownUsername;
        private final boolean newlyBanned;
        private final boolean banned;

        private FailureResult(int failureCount, int threshold, boolean unknownUsername,
                              boolean newlyBanned, boolean banned) {
            this.failureCount = failureCount;
            this.threshold = threshold;
            this.unknownUsername = unknownUsername;
            this.newlyBanned = newlyBanned;
            this.banned = banned;
        }

        public int getFailureCount() {
            return failureCount;
        }

        public int getThreshold() {
            return threshold;
        }

        public boolean isUnknownUsername() {
            return unknownUsername;
        }

        public boolean isNewlyBanned() {
            return newlyBanned;
        }

        public boolean isBanned() {
            return banned;
        }
    }
}
