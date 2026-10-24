package com.doubledimple.ociserver.service.mfa;

import com.doubledimple.dao.entity.OTPKey;
import com.doubledimple.dao.repository.OTPKeyRepository;
import org.apache.commons.codec.binary.Base32;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** Independent OTP account backups. This does not change system-login MFA enrollment or verification. */
@Service
public class MfaBackupService {
    public static final int MAX_ENTRIES = 5000;
    public static final int MAX_BATCH = 100;
    private final OTPKeyRepository repository;
    private final MfaImportCodec codec;
    private final TransactionTemplate transaction;

    public MfaBackupService(OTPKeyRepository repository, MfaImportCodec codec, PlatformTransactionManager manager) {
        this.repository = repository;
        this.codec = codec;
        this.transaction = new TransactionTemplate(manager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public List<Map<String, Object>> listEntries() {
        List<Map<String, Object>> result = new ArrayList<>();
        for (OTPKey key : readAll()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", id(key));
            item.put("keyName", text(key.getKeyName()));
            item.put("issuer", text(key.getIssuer()));
            item.put("createTime", key.getCreateTime() == null ? null : DateTimeFormatter.ISO_LOCAL_DATE_TIME.format(key.getCreateTime()));
            item.put("revision", revision(key));
            result.add(item);
        }
        return result;
    }

    public Map<String, Object> codes(List<Long> ids) {
        Map<Long, OTPKey> keys = byId(repository.findAllById(ids));
        long serverTime = System.currentTimeMillis();
        long step = serverTime / 30000L;
        List<Map<String, Object>> items = new ArrayList<>();
        for (Long requested : ids) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", requested.toString());
            OTPKey key = keys.get(requested);
            item.put("code", null);
            if (key == null) item.put("errorKey", "notFound");
            else {
                try {
                    String secret = codec.normalizeSecret(key.getSecretKey());
                    item.put("code", codeAt(secret, step));
                } catch (MfaImportCodec.MfaCodecException invalid) {
                    item.put("errorKey", "invalidSecret");
                } catch (Exception failure) {
                    item.put("errorKey", "requestFailed");
                }
            }
            items.add(item);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("success", true);
        result.put("serverTime", serverTime);
        result.put("expiresAt", (step + 1) * 30000L);
        result.put("items", items);
        return result;
    }

    public Map<String, Object> material(Long requested) {
        OTPKey key = repository.findById(requested).orElseThrow(() -> rejected("notFound"));
        MfaImportCodec.Entry entry = codec.normalizeStoredEntry(key.getKeyName(), key.getIssuer(), key.getSecretKey());
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", id(key));
        result.put("keyName", text(key.getKeyName()));
        result.put("issuer", text(key.getIssuer()));
        result.put("revision", revision(key));
        result.put("secretKey", entry.getSecretKey());
        result.put("qrCode", codec.generateQrCode(entry));
        return result;
    }

    public List<Map<String, Object>> exportEntries(List<Long> ids) {
        Map<Long, OTPKey> keys = byId(repository.findAllById(ids));
        List<Map<String, Object>> result = new ArrayList<>();
        for (Long requested : ids) {
            OTPKey key = keys.get(requested);
            if (key == null) throw rejected("notFound");
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", id(key));
            item.put("keyName", text(key.getKeyName()));
            item.put("issuer", text(key.getIssuer()));
            // Export is an explicit backup read: preserve the stored secret, including a legacy value needing repair.
            item.put("secretKey", text(key.getSecretKey()));
            result.add(item);
        }
        return result;
    }

    /** Serializes new imports in this process; existing/native writers remain protected by the unique account name. */
    public synchronized Map<String, Object> importEntries(List<MfaImportCodec.Entry> input) {
        if (input == null || input.isEmpty() || input.size() > MAX_BATCH) throw rejected("invalidInput");
        List<MfaImportCodec.Entry> normalized = new ArrayList<>();
        for (MfaImportCodec.Entry entry : input) {
            if (entry == null) throw rejected("invalidInput");
            normalized.add(codec.normalizeEntry(entry.getKeyName(), entry.getIssuer(), entry.getSecretKey()));
        }
        AtomicBoolean attempted = new AtomicBoolean(false);
        try {
            Map<String, Object> result = transaction.execute(status -> {
                List<OTPKey> existing = readAll();
                Map<String, OTPKey> names = new HashMap<>();
                Map<String, OTPKey> secrets = new HashMap<>();
                for (OTPKey key : existing) {
                    names.put(text(key.getKeyName()), key);
                    try { secrets.putIfAbsent(codec.normalizeSecret(key.getSecretKey()), key); }
                    catch (MfaImportCodec.MfaCodecException ignored) { /* Invalid legacy records do not match a valid imported secret. */ }
                }
                List<OTPKey> chosen = new ArrayList<>();
                List<OTPKey> added = new ArrayList<>();
                Map<String, String> requestedNames = new HashMap<>();
                int preserved = 0;
                for (MfaImportCodec.Entry entry : normalized) {
                    String previous = requestedNames.putIfAbsent(entry.getKeyName(), entry.getSecretKey());
                    if (previous != null && !previous.equals(entry.getSecretKey())) throw rejected("conflict");
                    OTPKey sameName = names.get(entry.getKeyName());
                    if (sameName != null && !sameSecret(sameName, entry.getSecretKey())) throw rejected("conflict");
                    OTPKey sameSecret = secrets.get(entry.getSecretKey());
                    if (sameSecret != null) {
                        chosen.add(sameSecret);
                        preserved++;
                        continue;
                    }
                    OTPKey key = new OTPKey(entry.getKeyName(), entry.getSecretKey());
                    key.setIssuer(entry.getIssuer());
                    // Generate all QR data during validation, before the first database mutation.
                    key.setQrCode(codec.generateQrCode(entry));
                    names.put(entry.getKeyName(), key);
                    secrets.put(entry.getSecretKey(), key);
                    added.add(key);
                    chosen.add(key);
                }
                if (existing.size() + added.size() > MAX_ENTRIES) throw rejected("limitExceeded");
                if (!added.isEmpty()) {
                    attempted.set(true);
                    repository.saveAll(added);
                    repository.flush();
                }
                List<String> ids = new ArrayList<>();
                for (OTPKey key : chosen) ids.add(id(key));
                Map<String, Object> receipt = new LinkedHashMap<>();
                receipt.put("importedCount", added.size());
                receipt.put("preservedCount", preserved);
                receipt.put("totalCount", normalized.size());
                receipt.put("ids", ids);
                return receipt;
            });
            if (result == null) throw new MfaFailure("requestFailed", attempted.get());
            return result;
        } catch (Exception failure) {
            if (!attempted.get() && failure instanceof MfaFailure) throw (MfaFailure) failure;
            if (!attempted.get() && failure instanceof MfaImportCodec.MfaCodecException) throw (MfaImportCodec.MfaCodecException) failure;
            throw new MfaFailure("requestFailed", attempted.get());
        }
    }

    public synchronized void delete(Long requested, String expectedRevision) {
        if (expectedRevision == null || !expectedRevision.matches("[a-f0-9]{64}")) throw rejected("invalidInput");
        AtomicBoolean attempted = new AtomicBoolean(false);
        try {
            transaction.execute(status -> {
                OTPKey key = repository.lockById(requested).orElseThrow(() -> rejected("notFound"));
                if (!MessageDigest.isEqual(expectedRevision.getBytes(StandardCharsets.US_ASCII),
                        revision(key).getBytes(StandardCharsets.US_ASCII))) throw rejected("conflict");
                attempted.set(true);
                repository.delete(key);
                repository.flush();
                return null;
            });
        } catch (Exception failure) {
            if (!attempted.get() && failure instanceof MfaFailure) throw (MfaFailure) failure;
            throw new MfaFailure("requestFailed", attempted.get());
        }
    }

    private List<OTPKey> readAll() {
        Page<OTPKey> page = repository.findAll(PageRequest.of(0, MAX_ENTRIES + 1, Sort.by("id").ascending()));
        if (page.getTotalElements() > MAX_ENTRIES || page.getContent().size() > MAX_ENTRIES) throw rejected("limitExceeded");
        if (page.getContent().size() != page.getTotalElements()) throw rejected("requestFailed");
        return page.getContent();
    }

    private boolean sameSecret(OTPKey key, String secret) {
        try { return codec.normalizeSecret(key.getSecretKey()).equals(secret); }
        catch (MfaImportCodec.MfaCodecException ignored) { return false; }
    }

    private static Map<Long, OTPKey> byId(Iterable<OTPKey> keys) {
        Map<Long, OTPKey> result = new HashMap<>();
        for (OTPKey key : keys) {
            id(key);
            if (result.put(key.getId(), key) != null) throw rejected("requestFailed");
        }
        return result;
    }

    public static String revision(OTPKey key) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            String[] fields = { id(key), key.getKeyName(), key.getIssuer(), key.getSecretKey(),
                    key.getCreateTime() == null ? null : key.getCreateTime().toString(),
                    key.getUpdateTime() == null ? null : key.getUpdateTime().toString() };
            for (String field : fields) {
                byte[] value = field == null ? new byte[0] : field.getBytes(StandardCharsets.UTF_8);
                digest.update(ByteBuffer.allocate(4).putInt(field == null ? -1 : value.length).array());
                digest.update(value);
            }
            StringBuilder result = new StringBuilder(64);
            for (byte part : digest.digest()) result.append(Character.forDigit((part >>> 4) & 15, 16)).append(Character.forDigit(part & 15, 16));
            return result.toString();
        } catch (Exception failure) { throw rejected("requestFailed"); }
    }

    private static String codeAt(String secret, long step) throws Exception {
        byte[] key = new Base32().decode(secret);
        Mac mac = Mac.getInstance("HmacSHA1");
        mac.init(new SecretKeySpec(key, "HmacSHA1"));
        byte[] hash = mac.doFinal(ByteBuffer.allocate(8).putLong(step).array());
        int offset = hash[hash.length - 1] & 15;
        int binary = (hash[offset] & 127) << 24 | (hash[offset + 1] & 255) << 16
                | (hash[offset + 2] & 255) << 8 | hash[offset + 3] & 255;
        return String.format(Locale.ROOT, "%06d", binary % 1000000);
    }

    private static String id(OTPKey key) {
        if (key == null || key.getId() == null || key.getId() <= 0) throw rejected("requestFailed");
        return key.getId().toString();
    }
    private static String text(String value) { return value == null ? "" : value; }
    private static MfaFailure rejected(String key) { return new MfaFailure(key, false); }
    public static final class MfaFailure extends RuntimeException {
        private final String errorKey;
        private final boolean writeAttempted;
        public MfaFailure(String errorKey, boolean writeAttempted) {
            super(errorKey);
            this.errorKey = errorKey; this.writeAttempted = writeAttempted;
        }
        public String getErrorKey() { return errorKey; }
        public boolean isWriteAttempted() { return writeAttempted; }
    }
}
