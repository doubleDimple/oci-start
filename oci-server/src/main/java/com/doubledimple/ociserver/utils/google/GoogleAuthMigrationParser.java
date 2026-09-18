package com.doubledimple.ociserver.utils.google;

import org.apache.commons.codec.binary.Base32;

import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Bounded local Google Authenticator migration parsing. Never logs or stringifies secret material. */
public final class GoogleAuthMigrationParser {
    public static final int MAX_URI_BYTES = 65536;
    public static final int MAX_ENTRIES = 100;
    private static final int MAX_SECRET_BYTES = 159;

    private GoogleAuthMigrationParser() { }

    /** Keep the old bean accessors; digits is the actual digit count, while type uses the protobuf enum. */
    public static class OtpParameters {
        private String secret;
        private String name;
        private String issuer;
        private int algorithm = 1;
        private int digits = 6;
        private int type = 2;

        public String getSecret() { return secret; }
        public void setSecret(String secret) { this.secret = secret; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getIssuer() { return issuer; }
        public void setIssuer(String issuer) { this.issuer = issuer; }
        public int getAlgorithm() { return algorithm; }
        public void setAlgorithm(int algorithm) { this.algorithm = algorithm; }
        public int getDigits() { return digits; }
        public void setDigits(int digits) { this.digits = digits; }
        public int getType() { return type; }
        public void setType(int type) { this.type = type; }
        public String getSecretInBase32() {
            if (secret == null) return null;
            try {
                byte[] bytes = Base64.getDecoder().decode(secret);
                if (bytes.length == 0 || bytes.length > MAX_SECRET_BYTES) throw invalid();
                return new Base32().encodeToString(bytes).replace("=", "");
            } catch (IllegalArgumentException e) { throw invalid(); }
        }
    }

    public static final class MigrationData {
        private final List<OtpParameters> entries;
        private final int batchIndex;
        private final int batchSize;
        private MigrationData(List<OtpParameters> entries, int batchIndex, int batchSize) {
            this.entries = Collections.unmodifiableList(new ArrayList<>(entries));
            this.batchIndex = batchIndex;
            this.batchSize = batchSize;
        }
        public List<OtpParameters> getEntries() { return entries; }
        public int getBatchIndex() { return batchIndex; }
        public int getBatchSize() { return batchSize; }
        public boolean isPartialBatch() { return batchSize > 1; }
    }

    public static final class MigrationParseException extends IllegalArgumentException {
        private final String errorKey;
        private MigrationParseException(String errorKey) { super(errorKey); this.errorKey = errorKey; }
        public String getErrorKey() { return errorKey; }
    }

    /** Compatibility entry point; each call contains only the accounts present in this one QR code. */
    public static List<OtpParameters> parseUri(String migrationUri) {
        return parseMigration(migrationUri).getEntries();
    }

    public static MigrationData parseMigration(String migrationUri) {
        try {
            URI uri = checkedUri(migrationUri);
            if (!"otpauth-migration".equalsIgnoreCase(uri.getScheme())
                    || !"offline".equalsIgnoreCase(uri.getRawAuthority())
                    || (uri.getRawPath() != null && !uri.getRawPath().isEmpty() && !"/".equals(uri.getRawPath()))) throw invalid();
            Map<String, String> query = parseQuery(uri.getRawQuery());
            if (query.size() != 1 || !query.containsKey("data")) throw invalid();
            byte[] bytes = Base64.getDecoder().decode(query.get("data"));
            if (bytes.length == 0 || bytes.length > MAX_URI_BYTES) throw invalid();
            Reader input = new Reader(bytes, 0, bytes.length);
            List<OtpParameters> entries = new ArrayList<>();
            boolean[] seen = new boolean[6];
            int batchSize = 1;
            int batchIndex = 0;
            while (input.hasRemaining()) {
                int tag = input.tag();
                int field = tag >>> 3;
                if (field == 1) {
                    requireWire(tag, 2);
                    if (entries.size() >= MAX_ENTRIES) throw new MigrationParseException("mfa.tooManyEntries");
                    entries.add(account(input.message()));
                } else if (field >= 2 && field <= 5) {
                    requireWire(tag, 0);
                    if (seen[field]) throw invalid();
                    seen[field] = true;
                    long value = input.varint();
                    // batch_id is an int32 token and may be encoded as a signed, ten-byte varint.
                    if (field != 5 && (value < 0 || value > Integer.MAX_VALUE)) throw invalid();
                    if (field == 3) batchSize = (int) value;
                    else if (field == 4) batchIndex = (int) value;
                } else input.skip(tag);
            }
            if (entries.isEmpty() || batchSize < 1 || batchSize > 1000 || batchIndex < 0 || batchIndex >= batchSize) throw invalid();
            return new MigrationData(entries, batchIndex, batchSize);
        } catch (MigrationParseException e) { throw e; }
        catch (Exception e) { throw invalid(); }
    }

    private static OtpParameters account(Reader input) {
        OtpParameters entry = new OtpParameters();
        boolean[] seen = new boolean[8];
        while (input.hasRemaining()) {
            int tag = input.tag();
            int field = tag >>> 3;
            // Unknown account fields may change OTP semantics; do not silently discard them.
            if (field < 1 || field > 7) throw unsupported();
            if (seen[field]) throw invalid();
            seen[field] = true;
            if (field <= 3) {
                requireWire(tag, 2);
                byte[] bytes = input.bytes(field == 1 ? MAX_SECRET_BYTES : 1020);
                if (field == 1) {
                    if (bytes.length == 0) throw invalid();
                    entry.setSecret(Base64.getEncoder().encodeToString(bytes));
                } else if (field == 2) entry.setName(utf8(bytes));
                else entry.setIssuer(utf8(bytes));
            } else {
                requireWire(tag, 0);
                long value = input.varint();
                if ((field == 4 && value != 1) || (field == 5 && value != 1)
                        || (field == 6 && value != 2) || (field == 7 && value != 0)) throw unsupported();
            }
        }
        // Protobuf enum zero means unspecified, not a supported default.
        if (!seen[1] || !seen[2]) throw invalid();
        if (!seen[4] || !seen[5] || !seen[6]) throw unsupported();
        if (entry.getName().trim().isEmpty() || entry.getName().length() > 255
                || (entry.getIssuer() != null && entry.getIssuer().length() > 255)) throw invalid();
        rejectControls(entry.getName());
        if (entry.getIssuer() != null) rejectControls(entry.getIssuer());
        return entry;
    }

    /** Percent decoding follows URI semantics: a literal '+' remains '+', including in Google Base64 data. */
    public static Map<String, String> parseQuery(String raw) {
        if (raw == null || raw.isEmpty() || raw.length() > MAX_URI_BYTES) throw invalid();
        Map<String, String> query = new LinkedHashMap<>();
        String[] fields = raw.split("&", -1);
        if (fields.length > 16) throw invalid();
        for (String field : fields) {
            int equal = field.indexOf('=');
            if (equal <= 0) throw invalid();
            String key = decodeComponent(field.substring(0, equal));
            String value = decodeComponent(field.substring(equal + 1));
            if (key.isEmpty() || query.containsKey(key)) throw invalid();
            query.put(key, value);
        }
        return query;
    }

    public static URI checkedUri(String raw) {
        try {
            if (raw == null || raw.length() > MAX_URI_BYTES) throw invalid();
            String value = raw.trim();
            rejectControls(value);
            if (value.isEmpty() || value.indexOf('\\') >= 0 || encoded(value).length > MAX_URI_BYTES) throw invalid();
            URI uri = new URI(value);
            if (!uri.isAbsolute() || uri.isOpaque() || uri.getRawFragment() != null
                    || uri.getRawUserInfo() != null || uri.getPort() != -1) throw invalid();
            return uri;
        } catch (MigrationParseException e) { throw e; }
        catch (Exception e) { throw invalid(); }
    }

    public static String decodeComponent(String raw) {
        try {
            if (raw.length() > MAX_URI_BYTES) throw invalid();
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            for (int index = 0; index < raw.length();) {
                if (raw.charAt(index) == '%') {
                    if (index + 2 >= raw.length()) throw invalid();
                    int high = Character.digit(raw.charAt(index + 1), 16);
                    int low = Character.digit(raw.charAt(index + 2), 16);
                    if (high < 0 || low < 0) throw invalid();
                    bytes.write((high << 4) | low);
                    index += 3;
                } else {
                    int next = raw.indexOf('%', index);
                    if (next < 0) next = raw.length();
                    byte[] run = encoded(raw.substring(index, next));
                    bytes.write(run, 0, run.length);
                    index = next;
                }
                if (bytes.size() > MAX_URI_BYTES) throw invalid();
            }
            String value = utf8(bytes.toByteArray());
            rejectControls(value);
            return value;
        } catch (MigrationParseException e) { throw e; }
        catch (Exception e) { throw invalid(); }
    }

    private static byte[] encoded(String value) throws Exception {
        ByteBuffer bytes = StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(value));
        byte[] result = new byte[bytes.remaining()];
        bytes.get(result);
        return result;
    }
    private static String utf8(byte[] bytes) {
        try {
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        } catch (Exception e) { throw invalid(); }
    }
    private static void rejectControls(String value) {
        for (int i = 0; i < value.length(); i++) if (Character.isISOControl(value.charAt(i))) throw invalid();
    }
    private static void requireWire(int tag, int type) { if ((tag & 7) != type) throw invalid(); }
    private static MigrationParseException invalid() { return new MigrationParseException("mfa.invalidUri"); }
    private static MigrationParseException unsupported() { return new MigrationParseException("mfa.unsupportedParameters"); }

    private static final class Reader {
        private final byte[] data;
        private final int end;
        private int position;
        private Reader(byte[] data, int start, int end) { this.data = data; this.position = start; this.end = end; }
        private boolean hasRemaining() { return position < end; }
        private long varint() {
            long value = 0;
            for (int index = 0; index < 10; index++) {
                if (!hasRemaining()) throw invalid();
                int next = data[position++] & 255;
                if (index == 9 && (next & 254) != 0) throw invalid();
                value |= (long) (next & 127) << (index * 7);
                if ((next & 128) == 0) return value;
            }
            throw invalid();
        }
        private int tag() {
            long value = varint();
            if (value <= 0 || value > 0xffffffffL || (value >>> 3) == 0) throw invalid();
            return (int) value;
        }
        private int length() {
            long length = varint();
            if (length < 0 || length > end - position) throw invalid();
            return (int) length;
        }
        private Reader message() {
            int length = length();
            Reader nested = new Reader(data, position, position + length);
            position += length;
            return nested;
        }
        private byte[] bytes(int limit) {
            int length = length();
            if (length > limit) throw invalid();
            byte[] value = new byte[length];
            System.arraycopy(data, position, value, 0, length);
            position += length;
            return value;
        }
        private void skip(int tag) {
            int wire = tag & 7;
            if (wire == 0) { varint(); return; }
            int length;
            if (wire == 1) length = 8;
            else if (wire == 2) length = length();
            else if (wire == 5) length = 4;
            else throw invalid();
            if (length > end - position) throw invalid();
            position += length;
        }
    }
}
