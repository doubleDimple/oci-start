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
import javax.annotation.Resource;
import java.security.SecureRandom;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

/** A persistent randomized global login lock, independent of account export limits and existing IP bans. */
@Service
@Slf4j
public class GlobalLoginGuard {
    static final String STATE_KEY = "auth.login.global-state";
    private static final int FAILURE_LIMIT = 3;
    private static final int MINIMUM_BLOCK_HOURS = 100;
    private static final int MAXIMUM_BLOCK_HOURS = 1024;
    private static final String BLOCKED = "登录凭据已连续验证失败 3 次，本站登录入口已封禁";
    private static final String UNAVAILABLE = "登录安全状态暂时无法验证，请稍后重试";
    private final SystemConfigRepository configs;
    private final TransactionTemplate transaction;
    private final Clock clock;
    private final SecureRandom random;
    private static final SecureRandom RECOVERY_RANDOM = new SecureRandom();
    @PersistenceContext private EntityManager entityManager;
    @Resource private GlobalLoginLockNotifier lockNotifier;

    @Autowired
    public GlobalLoginGuard(SystemConfigRepository configs, PlatformTransactionManager transactionManager) {
        this(configs, transactionManager, Clock.systemDefaultZone());
    }

    GlobalLoginGuard(SystemConfigRepository configs, PlatformTransactionManager transactionManager, Clock clock) {
        this(configs, transactionManager, clock, new SecureRandom());
    }

    GlobalLoginGuard(SystemConfigRepository configs, PlatformTransactionManager transactionManager,
                     Clock clock, SecureRandom random) {
        this.configs = configs;
        this.clock = clock;
        this.random = random;
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
                if (state.blocked) {
                    state.newLockEvent = randomLockEvent(clock.instant());
                    state.blockedUntil = state.newLockEvent.getBlockedUntil();
                }
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

    TelegramLoginRecoveryService.RecoveryResult recover(long chatId, long fromId, String botToken,
                                                        String enteredCode, BooleanSupplier accountAndTenantMatch) {
        TelegramLoginRecoveryService.RecoveryResult[] result = {TelegramLoginRecoveryService.RecoveryResult.REJECTED};
        update(state -> {
            Recovery recovery = state.recovery;
            if (!state.blocked || recovery == null) return;
            TelegramBinding binding = telegramBinding();
            if (binding == null || chatId <= 0 || chatId != fromId || chatId != binding.chatId
                    || chatId != recovery.chatId || botToken == null
                    || !equalHash(hash(botToken), binding.botHash) || !equalHash(binding.botHash, recovery.botHash)) return;
            Instant now = clock.instant();
            if (recovery.windowStart != null && !now.isBefore(recovery.windowStart.plus(15, ChronoUnit.MINUTES))) {
                recovery.windowStart = null;
                recovery.failures = 0;
            }
            if (recovery.failures >= 5) {
                result[0] = TelegramLoginRecoveryService.RecoveryResult.RATE_LIMITED;
                return;
            }
            String code = enteredCode == null ? "" : enteredCode.trim();
            if (code.matches("LGR-[A-Za-z0-9_-]{43}") && equalHash(hash(recovery.lockId + "\n" + code), recovery.codeHash)
                    && accountAndTenantMatch.getAsBoolean()) {
                state.failures = 0;
                state.blocked = false;
                state.blockedUntil = null;
                state.recovery = null;
                result[0] = TelegramLoginRecoveryService.RecoveryResult.SUCCESS;
            } else {
                recovery.failures++;
                if (recovery.failures >= 5) {
                    recovery.windowStart = now;
                    result[0] = TelegramLoginRecoveryService.RecoveryResult.RATE_LIMITED;
                }
            }
        });
        return result[0];
    }

    private LoginStatus update(Consumer<State> operation) {
        try {
            initialize();
            // Optional configuration reads occur before the lock transaction: their failure must not roll it back.
            TelegramBinding recoveryBinding = optionalTelegramBinding();
            CommitResult result = transaction.execute(status -> {
                SystemConfig row = configs.findByKeyForUpdate(STATE_KEY)
                        .orElseThrow(() -> new IllegalStateException("Missing login guard state"));
                // An OSIV persistence context may have loaded the row before another request committed.
                entityManager.refresh(row, LockModeType.PESSIMISTIC_WRITE);
                State state = read(row);
                operation.accept(state);
                if (state.newLockEvent != null) state.recovery = issueRecovery(state.newLockEvent, recoveryBinding);
                row.setValue(encode(state));
                row.setEnabled(state.blocked);
                configs.save(row);
                return new CommitResult(new LoginStatus(state.blocked,
                        state.blockedUntil == null ? null : state.blockedUntil.toString()), state.newLockEvent);
            });
            if (result == null) throw new IllegalStateException("Missing login guard result");
            // Only a committed transition emits an event; reading an existing lock never emits one.
            if (result.event != null) {
                try { lockNotifier.notifyBlocked(result.event); }
                catch (RuntimeException failure) {
                    log.warn("全站登录封禁通知提交失败，异常类型：{}", failure.getClass().getSimpleName());
                }
            }
            return result.status;
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
                    row.setValue("v2|0|");
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
        Instant now = clock.instant();
        if (fields.length == 9 && "v3".equals(fields[0])) {
            int failures = Integer.parseInt(fields[1]);
            Instant until = Instant.parse(fields[2]);
            validateState(row, failures);
            if (!row.isEnabled()) throw new IllegalStateException("Invalid recovery state");
            Recovery recovery = new Recovery();
            recovery.lockId = UUID.fromString(fields[3]).toString();
            recovery.codeHash = fields[4];
            recovery.chatId = Long.parseLong(fields[5]);
            recovery.botHash = fields[6];
            recovery.windowStart = fields[7].isEmpty() ? null : Instant.parse(fields[7]);
            recovery.failures = Integer.parseInt(fields[8]);
            if (!recovery.codeHash.matches("[0-9a-f]{64}") || !recovery.botHash.matches("[0-9a-f]{64}")
                    || recovery.chatId <= 0 || recovery.failures < 0 || recovery.failures > 5
                    || (recovery.windowStart == null) != (recovery.failures < 5)) {
                throw new IllegalStateException("Invalid recovery state");
            }
            if (!now.isBefore(until)) return new State(0, null);
            State state = new State(failures, until);
            state.recovery = recovery;
            return state;
        }
        if (fields.length == 3 && "v2".equals(fields[0])) {
            int failures = Integer.parseInt(fields[1]);
            Instant blockedUntil = fields[2].isEmpty() ? null : Instant.parse(fields[2]);
            validateState(row, failures);
            if ((blockedUntil != null) != row.isEnabled()) {
                throw new IllegalStateException("Invalid login guard state");
            }
            if (blockedUntil != null && !now.isBefore(blockedUntil)) return new State(0, null);
            return new State(failures, blockedUntil);
        }

        // Migrate the old calendar-day format only under the same persistent row lock.
        if (fields.length != 2) throw new IllegalStateException("Invalid login guard state");
        LocalDate day = LocalDate.parse(fields[0]);
        int failures = Integer.parseInt(fields[1]);
        validateState(row, failures);
        if (!row.isEnabled()) return new State(failures, null);
        Instant oldDeadline = day.plusDays(1).atStartOfDay(clock.getZone()).toInstant();
        if (!now.isBefore(oldDeadline)) return new State(0, null);
        LockEvent event = randomLockEvent(now);
        State migrated = new State(failures, event.getBlockedUntil());
        migrated.newLockEvent = event;
        return migrated;
    }

    private String encode(State state) {
        if (state.recovery == null) return "v2|" + state.failures + "|" + (state.blockedUntil == null ? "" : state.blockedUntil);
        Recovery r = state.recovery;
        return "v3|" + state.failures + "|" + state.blockedUntil + "|" + r.lockId + "|" + r.codeHash
                + "|" + r.chatId + "|" + r.botHash + "|" + (r.windowStart == null ? "" : r.windowStart) + "|" + r.failures;
    }

    private Recovery issueRecovery(LockEvent event, TelegramBinding binding) {
        try {
            if (binding == null) return null;
            byte[] bytes = new byte[32];
            RECOVERY_RANDOM.nextBytes(bytes);
            String code = "LGR-" + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
            Recovery recovery = new Recovery();
            recovery.lockId = UUID.randomUUID().toString();
            recovery.codeHash = hash(recovery.lockId + "\n" + code);
            recovery.chatId = binding.chatId;
            recovery.botHash = binding.botHash;
            event.recoveryCode = code;
            event.recoveryChatId = binding.chatId;
            event.recoveryBotTokenHash = binding.botHash;
            return recovery;
        } catch (RuntimeException failure) {
            // Unavailable Telegram recovery must never prevent the security lock itself from committing.
            log.warn("Telegram 登录恢复码未生成，异常类型：{}", failure.getClass().getSimpleName());
            return null;
        }
    }

    private TelegramBinding optionalTelegramBinding() {
        try { return telegramBinding(); }
        catch (RuntimeException failure) {
            log.warn("Telegram 恢复配置不可用，异常类型：{}", failure.getClass().getSimpleName());
            return null;
        }
    }

    private TelegramBinding telegramBinding() {
        boolean enabled = configs.findByKey("telegram.enabled").map(SystemConfig::isEnabled).orElse(false);
        if (!enabled) return null;
        String chat = configs.findByKey("telegram.chat.id").map(SystemConfig::getValue).orElse("");
        String token = configs.findByKey("telegram.bot.token").map(SystemConfig::getValue).orElse("");
        if (chat == null || !chat.trim().matches("[1-9][0-9]{0,18}") || token == null || token.trim().isEmpty()) return null;
        long chatId = Long.parseLong(chat.trim());
        return chatId > 0 ? new TelegramBinding(chatId, hash(token)) : null;
    }

    static String hash(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte b : digest) hex.append(String.format("%02x", b & 255));
            return hex.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("Recovery digest unavailable");
        }
    }

    private static boolean equalHash(String one, String two) {
        return MessageDigest.isEqual(one.getBytes(StandardCharsets.US_ASCII), two.getBytes(StandardCharsets.US_ASCII));
    }

    private static void validateState(SystemConfig row, int failures) {
        if (failures < 0 || failures > FAILURE_LIMIT || row.isEnabled() != (failures == FAILURE_LIMIT)) {
            throw new IllegalStateException("Invalid login guard state");
        }
    }

    private LockEvent randomLockEvent(Instant start) {
        int hours = MINIMUM_BLOCK_HOURS + random.nextInt(MAXIMUM_BLOCK_HOURS - MINIMUM_BLOCK_HOURS + 1);
        return new LockEvent(hours, start.plus(hours, ChronoUnit.HOURS), clock.getZone());
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

    /** Private-notification payload; never serialize it into a public authentication response. */
    public static final class LockEvent {
        private final int hours;
        private final Instant blockedUntil;
        private final ZoneId zone;
        private String recoveryCode;
        private long recoveryChatId;
        private String recoveryBotTokenHash;
        private LockEvent(int hours, Instant blockedUntil, ZoneId zone) {
            this.hours = hours; this.blockedUntil = blockedUntil; this.zone = zone;
        }
        public int getHours() { return hours; }
        public Instant getBlockedUntil() { return blockedUntil; }
        public ZoneId getZone() { return zone; }
        String getRecoveryCode() { return recoveryCode; }
        long getRecoveryChatId() { return recoveryChatId; }
        String getRecoveryBotTokenHash() { return recoveryBotTokenHash; }
    }

    private static final class CommitResult {
        private final LoginStatus status;
        private final LockEvent event;
        private CommitResult(LoginStatus status, LockEvent event) { this.status = status; this.event = event; }
    }

    private static final class State {
        private int failures;
        private boolean blocked;
        private Instant blockedUntil;
        private LockEvent newLockEvent;
        private Recovery recovery;
        private State(int failures, Instant blockedUntil) {
            this.failures = failures;
            this.blocked = blockedUntil != null;
            this.blockedUntil = blockedUntil;
        }
    }

    private static final class Recovery {
        private String lockId;
        private String codeHash;
        private long chatId;
        private String botHash;
        private Instant windowStart;
        private int failures;
    }

    private static final class TelegramBinding {
        private final long chatId;
        private final String botHash;
        private TelegramBinding(long chatId, String botHash) { this.chatId = chatId; this.botHash = botHash; }
    }
}
