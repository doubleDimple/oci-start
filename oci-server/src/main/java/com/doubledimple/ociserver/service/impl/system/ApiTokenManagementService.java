package com.doubledimple.ociserver.service.impl.system;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfig;
import com.doubledimple.ociserver.pojo.request.ApiTokenConfigRequest;
import com.doubledimple.ociserver.pojo.response.ApiTokenResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** Management for the one global Open API token; never logs or stores request/response exceptions. */
@Service
public class ApiTokenManagementService {
    private final SystemConfigRepository repository;
    private final SystemConfigService configService;
    private final TransactionTemplate transaction;

    public ApiTokenManagementService(SystemConfigRepository repository, SystemConfigService configService,
                                     PlatformTransactionManager manager) {
        this.repository = repository; this.configService = configService;
        this.transaction = new TransactionTemplate(manager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public Map<String, Object> metadata() { return metadata(snapshot(false)); }

    public Map<String, Object> material(String expected) {
        Snapshot snapshot = snapshot(false);
        requireRevision(snapshot, expected);
        ApiTokenConfig config = snapshot.config;
        if (!config.isEnabled() || text(config.getTokenValue()).isEmpty() || config.getExpiresAt() == null
                || !config.getExpiresAt().atZone(ZoneId.systemDefault()).toInstant().isAfter(Instant.now())) throw fail("notFound", false);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("metadata", metadata(snapshot)); result.put("tokenValue", config.getTokenValue());
        return result;
    }

    /** The monitor is held until the inner transaction commits, including the initially empty settings case. */
    public synchronized Map<String, Object> generate(ApiTokenConfigRequest input, String expected) {
        ApiTokenConfigRequest request = normalize(input);
        AtomicBoolean attempted = new AtomicBoolean(false);
        try {
            Map<String, Object> result = transaction.execute(status -> {
                requireRevision(snapshot(true), expected);
                attempted.set(true);
                ApiTokenResponse generated = configService.updateApiTokenConfig(request);
                repository.flush();
                Snapshot saved = snapshot(false);
                if (!text(generated.getTokenValue()).equals(saved.config.getTokenValue()) || !saved.config.isEnabled()) throw fail("requestFailed", true);
                Map<String, Object> receipt = new LinkedHashMap<>();
                receipt.put("metadata", metadata(saved)); receipt.put("tokenValue", generated.getTokenValue());
                return receipt;
            });
            if (result == null) throw fail("requestFailed", attempted.get());
            return result;
        } catch (Exception failure) {
            if (!attempted.get() && failure instanceof TokenFailure) throw (TokenFailure) failure;
            throw fail("requestFailed", attempted.get());
        }
    }

    public synchronized Map<String, Object> revoke(String expected) {
        AtomicBoolean attempted = new AtomicBoolean(false);
        try {
            Map<String, Object> result = transaction.execute(status -> {
                requireRevision(snapshot(true), expected);
                attempted.set(true);
                configService.revokeApiToken();
                repository.flush();
                Snapshot saved = snapshot(false);
                if (saved.config.isEnabled() || !text(saved.config.getTokenValue()).isEmpty()) throw fail("requestFailed", true);
                return metadata(saved);
            });
            if (result == null) throw fail("requestFailed", attempted.get());
            return result;
        } catch (Exception failure) {
            if (!attempted.get() && failure instanceof TokenFailure) throw (TokenFailure) failure;
            throw fail("requestFailed", attempted.get());
        }
    }

    private Snapshot snapshot(boolean lock) {
        List<SystemConfig> rows = lock ? repository.lockApiTokenSettings() : repository.findAllByKeyStartingWith("api.token.");
        return new Snapshot(SystemConfigService.apiTokenConfigFrom(rows), revision(rows));
    }

    private static Map<String, Object> metadata(Snapshot snapshot) {
        ApiTokenConfig config = snapshot.config;
        ZoneId zone = ZoneId.systemDefault();
        Instant now = Instant.now();
        Long expires = config.getExpiresAt() == null ? null : config.getExpiresAt().atZone(zone).toInstant().toEpochMilli();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("enabled", config.isEnabled()); result.put("hasToken", !text(config.getTokenValue()).isEmpty());
        result.put("isExpired", expires == null ? null : expires <= now.toEpochMilli());
        result.put("tokenName", text(config.getTokenName())); result.put("description", text(config.getDescription()));
        result.put("expirationDays", config.getExpirationDays());
        result.put("createdAt", localTime(config.getCreatedAt())); result.put("expiresAt", localTime(config.getExpiresAt()));
        result.put("daysUntilExpiration", config.getExpiresAt() == null ? null
                : Math.max(0L, ChronoUnit.DAYS.between(LocalDateTime.ofInstant(now, zone), config.getExpiresAt())));
        result.put("allowSwaggerAccess", config.isAllowSwaggerAccess()); result.put("revision", snapshot.revision);
        result.put("serverTime", now.toEpochMilli()); result.put("expiresAtEpochMs", expires); result.put("serverTimeZone", zone.getId());
        return result;
    }

    private static ApiTokenConfigRequest normalize(ApiTokenConfigRequest input) {
        if (input == null) throw fail("invalidInput", false);
        String name = text(input.getTokenName()).trim(), description = text(input.getDescription());
        if (name.isEmpty() || name.length() > 255 || description.length() > 1000
                || input.getExpirationDays() < 1 || input.getExpirationDays() > 365) throw fail("invalidInput", false);
        for (int i = 0; i < name.length(); i++) if (Character.isISOControl(name.charAt(i))) throw fail("invalidInput", false);
        if (!StandardCharsets.UTF_8.newEncoder().canEncode(name) || !StandardCharsets.UTF_8.newEncoder().canEncode(description)) throw fail("invalidInput", false);
        ApiTokenConfigRequest normalized = new ApiTokenConfigRequest();
        normalized.setEnabled(true); normalized.setAllowSwaggerAccess(true);
        normalized.setTokenName(name); normalized.setDescription(description); normalized.setExpirationDays(input.getExpirationDays());
        return normalized;
    }

    private static void requireRevision(Snapshot snapshot, String expected) {
        if (expected == null || !expected.matches("[a-f0-9]{64}")) throw fail("invalidInput", false);
        if (!MessageDigest.isEqual(expected.getBytes(StandardCharsets.US_ASCII), snapshot.revision.getBytes(StandardCharsets.US_ASCII))) throw fail("conflict", false);
    }

    private static String revision(List<SystemConfig> rows) {
        try {
            List<SystemConfig> sorted = new ArrayList<>(rows);
            sorted.sort(Comparator.comparing(SystemConfig::getKey));
            MessageDigest hash = MessageDigest.getInstance("SHA-256");
            for (SystemConfig row : sorted) {
                for (String field : new String[]{row.getKey(), row.getValue(), Boolean.toString(row.isEnabled())}) {
                    byte[] bytes = field == null ? new byte[0] : field.getBytes(StandardCharsets.UTF_8);
                    hash.update(ByteBuffer.allocate(4).putInt(field == null ? -1 : bytes.length).array()); hash.update(bytes);
                }
            }
            StringBuilder result = new StringBuilder(64);
            for (byte value : hash.digest()) result.append(Character.forDigit((value >>> 4) & 15, 16)).append(Character.forDigit(value & 15, 16));
            return result.toString();
        } catch (Exception failure) { throw fail("requestFailed", false); }
    }

    private static String text(String value) { return value == null ? "" : value; }
    private static String localTime(LocalDateTime value) { return value == null ? null : DateTimeFormatter.ISO_LOCAL_DATE_TIME.format(value); }
    private static TokenFailure fail(String key, boolean attempted) { return new TokenFailure(key, attempted); }
    private static final class Snapshot {
        final ApiTokenConfig config; final String revision;
        Snapshot(ApiTokenConfig config, String revision) { this.config = config; this.revision = revision; }
    }
    public static final class TokenFailure extends RuntimeException {
        private final String errorKey; private final boolean writeAttempted;
        public TokenFailure(String key, boolean attempted) { super(key); errorKey = key; writeAttempted = attempted; }
        public String getErrorKey() { return errorKey; }
        public boolean isWriteAttempted() { return writeAttempted; }
    }
}
