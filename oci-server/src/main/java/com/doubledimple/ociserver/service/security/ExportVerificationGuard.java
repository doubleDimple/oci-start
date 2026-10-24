package com.doubledimple.ociserver.service.security;

import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.repository.LoginUserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import javax.persistence.EntityManager;
import javax.persistence.LockModeType;
import javax.persistence.PersistenceContext;
import java.time.Clock;
import java.time.LocalDate;
import java.util.Locale;
import java.util.function.BiPredicate;
import java.util.function.Function;

/** Serializes sensitive-export checks per account and commits daily failures before rejecting a request. */
@Service
public class ExportVerificationGuard {
    private static final int DAILY_FAILURE_LIMIT = 2;
    private static final String BLOCKED = "今天登录密码或导出验证码已累计输错 2 次，当前账号当天已暂停导出，请明天再试";
    private static final String EXPIRED = "导出验证码已过期或尚未获取，请重新获取；本次不计入错误次数";

    private final LoginUserRepository users;
    private final TransactionTemplate transaction;
    private final Clock clock;
    @PersistenceContext private EntityManager entityManager;

    @Autowired
    public ExportVerificationGuard(LoginUserRepository users, PlatformTransactionManager transactionManager) {
        this(users, transactionManager, Clock.systemDefaultZone());
    }

    ExportVerificationGuard(LoginUserRepository users, PlatformTransactionManager transactionManager, Clock clock) {
        this.users = users;
        this.clock = clock;
        this.transaction = new TransactionTemplate(transactionManager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /** The callback may generate/cache a code; send notifications only after this method commits. */
    public <T> T issueCode(String username, Function<Long, T> issuer) {
        return locked(username, user -> dailyFailures(user) >= DAILY_FAILURE_LIMIT
                ? Outcome.failure(BLOCKED) : Outcome.success(issuer.apply(user.getId())));
    }

    /** Record only a known account's invalid password; reaching the limit must not change the login error. */
    public void recordPasswordFailure(String username) {
        locked(username, user -> {
            int failures = dailyFailures(user);
            user.setExportVerificationWrongCount(Math.min(DAILY_FAILURE_LIMIT, failures + 1));
            users.save(user);
            return Outcome.success(null);
        });
    }

    /** Cache lookup and one-time consumption run while holding the same database account lock as counting. */
    public void verify(String username, String enteredCode, Function<Long, String> codeReader,
                       BiPredicate<Long, String> consumeCode) {
        locked(username, user -> {
            int failures = dailyFailures(user);
            if (failures >= DAILY_FAILURE_LIMIT) return Outcome.failure(BLOCKED);
            String savedCode = codeReader.apply(user.getId());
            if (savedCode == null) return Outcome.failure(EXPIRED);
            String normalized = enteredCode == null ? "" : enteredCode.trim().toUpperCase(Locale.ROOT);
            if (!normalized.matches("[A-Z0-9]{8}") || !savedCode.equals(normalized)) {
                int updated = Math.min(DAILY_FAILURE_LIMIT, failures + 1);
                user.setExportVerificationWrongCount(updated);
                users.save(user);
                return Outcome.failure(updated >= DAILY_FAILURE_LIMIT ? BLOCKED
                        : "导出验证码错误，今天登录密码或导出验证码还可累计输错 1 次；再次输错将暂停导出至明天");
            }
            if (!consumeCode.test(user.getId(), savedCode)) return Outcome.failure(EXPIRED);
            // Successful verification does not forgive earlier failures on the same day.
            return Outcome.success(null);
        });
    }

    private int dailyFailures(LoginUser user) {
        LocalDate today = LocalDate.now(clock);
        if (!today.equals(user.getExportVerificationDate())) {
            user.setExportVerificationDate(today);
            user.setExportVerificationWrongCount(0);
            users.save(user);
            return 0;
        }
        Integer count = user.getExportVerificationWrongCount();
        return count == null ? 0 : Math.max(0, count);
    }

    private <T> T locked(String username, Function<LoginUser, Outcome<T>> operation) {
        Outcome<T> outcome = transaction.execute(status -> {
            if (username == null || username.trim().isEmpty()) {
                return Outcome.failure("登录账号不存在，请重新登录后重试");
            }
            LoginUser user = users.findByUsernameForUpdate(username).orElse(null);
            if (user == null) return Outcome.failure("登录账号不存在，请重新登录后重试");
            // Avoid stale account counters in an OpenEntityManagerInView persistence context.
            entityManager.refresh(user, LockModeType.PESSIMISTIC_WRITE);
            return operation.apply(user);
        });
        // Throwing inside the callback would roll back the increment and allow unlimited retries.
        if (outcome == null) throw new IllegalStateException("无法完成导出验证码校验，请稍后重试");
        if (outcome.error != null) throw new ExportVerificationException(outcome.error);
        return outcome.value;
    }

    public static final class ExportVerificationException extends IllegalStateException {
        private ExportVerificationException(String message) {
            super(message);
        }
    }

    private static final class Outcome<T> {
        private final T value;
        private final String error;

        private Outcome(T value, String error) {
            this.value = value;
            this.error = error;
        }

        private static <T> Outcome<T> success(T value) { return new Outcome<>(value, null); }
        private static <T> Outcome<T> failure(String error) { return new Outcome<>(null, error); }
    }
}
