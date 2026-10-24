package com.doubledimple.ociserver.service.login;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import javax.persistence.EntityManager;
import javax.persistence.LockModeType;
import javax.persistence.PersistenceContext;
import java.time.Clock;
import java.time.LocalDate;
import java.util.function.Consumer;

/** A database-wide daily login lock, independent of account export limits and existing IP bans. */
@Service
@Slf4j
public class GlobalLoginGuard {
    static final String STATE_KEY = "auth.login.global-state";
    private static final int FAILURE_LIMIT = 3;
    private static final String BLOCKED = "登录凭据已连续验证失败 3 次，本站登录入口已封禁";
    private static final String UNAVAILABLE = "登录安全状态暂时无法验证，请稍后重试";
    private final SystemConfigRepository configs;
    private final TransactionTemplate transaction;
    private final Clock clock;
    @PersistenceContext private EntityManager entityManager;

    @Autowired
    public GlobalLoginGuard(SystemConfigRepository configs, PlatformTransactionManager transactionManager) {
        this(configs, transactionManager, Clock.systemDefaultZone());
    }

    GlobalLoginGuard(SystemConfigRepository configs, PlatformTransactionManager transactionManager, Clock clock) {
        this.configs = configs;
        this.clock = clock;
        this.transaction = new TransactionTemplate(transactionManager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public LoginStatus status() {
        return update(state -> { });
    }

    public void assertAllowed() {
        requireAllowed(status());
    }

    /** Commit every failure, including the third, before reporting that the login entrance is blocked. */
    public void recordCredentialFailure() {
        LoginStatus result = update(state -> {
            if (!state.blocked) {
                state.failures = Math.min(FAILURE_LIMIT, state.failures + 1);
                state.blocked = state.failures >= FAILURE_LIMIT;
            }
        });
        requireAllowed(result);
    }

    /** Session creation and the final allowed check share the lock with concurrent failed logins. */
    public void completeLogin(Runnable createSession, Runnable undoSession) {
        boolean[] attempted = {false};
        try {
            LoginStatus result = update(state -> {
                if (state.blocked) return;
                attempted[0] = true;
                createSession.run();
                state.failures = 0;
            });
            requireAllowed(result);
        } catch (RuntimeException failure) {
            if (attempted[0]) {
                try { undoSession.run(); }
                catch (RuntimeException cleanupFailure) {
                    log.warn("撤回未完成登录失败，异常类型：{}", cleanupFailure.getClass().getSimpleName());
                }
            }
            throw failure;
        }
    }

    private LoginStatus update(Consumer<State> operation) {
        try {
            initialize();
            LoginStatus result = transaction.execute(status -> {
                SystemConfig row = configs.findByKeyForUpdate(STATE_KEY)
                        .orElseThrow(() -> new IllegalStateException("Missing login guard state"));
                // An OSIV persistence context may have loaded the row before another request committed.
                entityManager.refresh(row, LockModeType.PESSIMISTIC_WRITE);
                State state = read(row);
                operation.accept(state);
                row.setValue(state.day + "|" + state.failures);
                row.setEnabled(state.blocked);
                configs.save(row);
                return new LoginStatus(state.blocked, state.blocked
                        ? state.day.plusDays(1).atStartOfDay(clock.getZone()).toOffsetDateTime().toString() : null);
            });
            if (result == null) throw new IllegalStateException("Missing login guard result");
            return result;
        } catch (LoginGuardException | IpBannedException failure) {
            throw failure;
        } catch (RuntimeException failure) {
            log.warn("登录安全状态操作未完成，异常类型：{}", failure.getClass().getSimpleName());
            throw new LoginGuardException(UNAVAILABLE, false, null);
        }
    }

    private void initialize() {
        try {
            transaction.execute(status -> {
                if (!configs.existsByKey(STATE_KEY)) {
                    SystemConfig row = new SystemConfig();
                    row.setKey(STATE_KEY);
                    row.setValue(LocalDate.now(clock) + "|0");
                    row.setEnabled(false);
                    configs.saveAndFlush(row);
                }
                return null;
            });
        } catch (DataIntegrityViolationException concurrentInsert) {
            // The unique key elects one initializer. A duplicate insert rolls back in its own transaction.
            Boolean exists = transaction.execute(status -> configs.existsByKey(STATE_KEY));
            if (!Boolean.TRUE.equals(exists)) throw concurrentInsert;
        }
    }

    private State read(SystemConfig row) {
        String[] fields = row.getValue() == null ? new String[0] : row.getValue().split("\\|", -1);
        if (fields.length != 2) throw new IllegalStateException("Invalid login guard state");
        LocalDate day = LocalDate.parse(fields[0]);
        int failures = Integer.parseInt(fields[1]);
        if (failures < 0 || failures > FAILURE_LIMIT || row.isEnabled() != (failures == FAILURE_LIMIT)) {
            throw new IllegalStateException("Invalid login guard state");
        }
        LocalDate today = LocalDate.now(clock);
        // A clock moving backwards must not shorten an already active daily block.
        return today.isAfter(day) ? new State(today, 0, false) : new State(day, failures, row.isEnabled());
    }

    private static void requireAllowed(LoginStatus status) {
        if (status.isBlocked()) throw new LoginGuardException(BLOCKED, true, status.getBlockedUntil());
    }

    public static final class LoginStatus {
        private final boolean blocked;
        private final String blockedUntil;
        private LoginStatus(boolean blocked, String blockedUntil) { this.blocked = blocked; this.blockedUntil = blockedUntil; }
        public boolean isBlocked() { return blocked; }
        public String getBlockedUntil() { return blockedUntil; }
        public String getMessage() { return blocked ? BLOCKED : null; }
    }

    public static final class LoginGuardException extends RuntimeException {
        private final boolean blocked;
        private final String blockedUntil;
        private LoginGuardException(String message, boolean blocked, String blockedUntil) {
            super(message); this.blocked = blocked; this.blockedUntil = blockedUntil;
        }
        public boolean isBlocked() { return blocked; }
        public String getBlockedUntil() { return blockedUntil; }
    }

    private static final class State {
        private final LocalDate day;
        private int failures;
        private boolean blocked;
        private State(LocalDate day, int failures, boolean blocked) {
            this.day = day; this.failures = failures; this.blocked = blocked;
        }
    }
}
