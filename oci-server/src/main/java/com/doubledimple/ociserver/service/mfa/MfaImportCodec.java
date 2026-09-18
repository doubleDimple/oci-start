package com.doubledimple.ociserver.service.mfa;

import com.doubledimple.ociserver.utils.google.GoogleAuthMigrationParser;
import com.doubledimple.ociserver.utils.google.GoogleAuthMigrationParser.MigrationParseException;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.ReaderException;
import com.google.zxing.client.j2se.BufferedImageLuminanceSource;
import com.google.zxing.common.HybridBinarizer;
import org.apache.commons.codec.binary.Base32;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.MemoryCacheImageInputStream;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.CharBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Pure parsing/preflight and local QR generation; this component never reads or writes a database. */
@Component
public class MfaImportCodec {
    public static final int MAX_NAME_LENGTH = 255;
    public static final int MAX_SECRET_LENGTH = 255;
    public static final int MAX_SECRET_INPUT_LENGTH = 1024;
    public static final int MAX_URI_BYTES = GoogleAuthMigrationParser.MAX_URI_BYTES;
    public static final int MAX_ENTRIES = GoogleAuthMigrationParser.MAX_ENTRIES;
    public static final int MAX_IMAGE_BYTES = 5 * 1024 * 1024;
    public static final long MAX_IMAGE_PIXELS = 4_000_000L;
    public static final int MAX_IMAGE_DIMENSION = 8192;

    private final QRCodeService qrCodeService;
    public MfaImportCodec(QRCodeService qrCodeService) { this.qrCodeService = qrCodeService; }

    public static final class Entry {
        private final String keyName;
        private final String issuer;
        private final String secretKey;
        private Entry(String keyName, String issuer, String secretKey) {
            this.keyName = keyName; this.issuer = issuer; this.secretKey = secretKey;
        }
        public String getKeyName() { return keyName; }
        public String getIssuer() { return issuer; }
        public String getSecretKey() { return secretKey; }
    }
    public static final class Preview {
        private final List<Entry> entries;
        private final int batchIndex;
        private final int batchSize;
        private Preview(List<Entry> entries, int batchIndex, int batchSize) {
            this.entries = Collections.unmodifiableList(new ArrayList<>(entries));
            this.batchIndex = batchIndex; this.batchSize = batchSize;
        }
        public List<Entry> getEntries() { return entries; }
        public boolean isPartialBatch() { return batchSize > 1; }
        public int getBatchIndex() { return batchIndex; }
        public int getBatchSize() { return batchSize; }
    }
    public static final class MfaCodecException extends IllegalArgumentException {
        private final String errorKey;
        private MfaCodecException(String errorKey) { super(errorKey); this.errorKey = errorKey; }
        public String getErrorKey() { return errorKey; }
    }

    public Entry normalizeEntry(String keyName, String issuer, String secret) {
        return new Entry(label(keyName, true), label(issuer, false), normalizeSecret(secret));
    }

    /** Old Google imports stored an issuer prefix in keyName as well as the separate issuer column. */
    public Entry normalizeStoredEntry(String keyName, String issuer, String secret) {
        String name = keyName == null ? null : keyName.trim();
        String provider = issuer == null ? "" : issuer.trim();
        if (name != null && !provider.isEmpty() && name.startsWith(provider + ":")) {
            name = name.substring(provider.length() + 1).trim();
        }
        return normalizeEntry(name, provider, secret);
    }

    public String normalizeSecret(String input) {
        if (input == null || input.length() > MAX_SECRET_INPUT_LENGTH) throw error("invalidSecret");
        StringBuilder grouped = new StringBuilder();
        for (int i = 0; i < input.length(); i++) {
            char value = input.charAt(i);
            if (value == ' ' || value == '\t' || value == '\r' || value == '\n') continue;
            if (value >= 'a' && value <= 'z') value = (char) (value - 'a' + 'A');
            if ((value < 'A' || value > 'Z') && (value < '2' || value > '7') && value != '=') throw error("invalidSecret");
            grouped.append(value);
        }
        String compact = grouped.toString();
        int padding = compact.indexOf('=');
        String canonical = padding < 0 ? compact : compact.substring(0, padding);
        if (canonical.isEmpty() || canonical.length() > MAX_SECRET_LENGTH) throw error("invalidSecret");
        if (padding >= 0) {
            for (int i = padding; i < compact.length(); i++) if (compact.charAt(i) != '=') throw error("invalidSecret");
            int expected = (8 - canonical.length() % 8) % 8;
            if (expected == 0 || compact.length() - padding != expected) throw error("invalidSecret");
        }
        int remainder = canonical.length() % 8;
        if (remainder == 1 || remainder == 3 || remainder == 6) throw error("invalidSecret");
        Base32 base32 = new Base32();
        byte[] decoded = base32.decode(canonical);
        // Round-trip catches unused nonzero bits that permissive Base32 decoders would silently ignore.
        if (decoded.length == 0 || !base32.encodeToString(decoded).replace("=", "").equals(canonical)) throw error("invalidSecret");
        return canonical;
    }

    public Preview preview(String mode, String keyName, String issuer, String secret,
                           MultipartFile image, String qrUrl) {
        if ("manual".equals(mode)) {
            if (present(qrUrl) || image != null && !image.isEmpty()) throw error("invalidInput");
            return new Preview(Collections.singletonList(normalizeEntry(keyName, issuer, secret)), 0, 1);
        }
        if (present(secret) || present(keyName) || present(issuer)) throw error("invalidInput");
        if ("uri".equals(mode)) {
            if (image != null && !image.isEmpty()) throw error("invalidInput");
            return parseUri(qrUrl);
        }
        if ("image".equals(mode)) {
            if (present(qrUrl)) throw error("invalidInput");
            return parseUri(readQr(image));
        }
        throw error("invalidInput");
    }

    public String toOtpUri(String keyName, String issuer, String secret) {
        Entry entry = normalizeEntry(keyName, issuer, secret);
        String name = encode(entry.getKeyName());
        if (!entry.getIssuer().isEmpty()) name = encode(entry.getIssuer()) + ":" + name;
        return "otpauth://totp/" + name + "?secret=" + entry.getSecretKey()
                + (entry.getIssuer().isEmpty() ? "" : "&issuer=" + encode(entry.getIssuer()))
                + "&algorithm=SHA1&digits=6&period=30";
    }

    public String generateQrCode(Entry entry) {
        if (entry == null) throw error("invalidInput");
        try { return qrCodeService.generateQRCodeImage(toOtpUri(entry.getKeyName(), entry.getIssuer(), entry.getSecretKey())); }
        catch (MfaCodecException e) { throw e; }
        catch (Exception e) { throw error("qrGenerationFailed"); }
    }

    private Preview parseUri(String value) {
        try {
            URI uri = GoogleAuthMigrationParser.checkedUri(value);
            if ("otpauth-migration".equalsIgnoreCase(uri.getScheme())) {
                GoogleAuthMigrationParser.MigrationData data = GoogleAuthMigrationParser.parseMigration(value);
                List<Entry> entries = new ArrayList<>();
                for (GoogleAuthMigrationParser.OtpParameters account : data.getEntries()) {
                    entries.add(fromLabel(account.getName(), account.getIssuer(), account.getSecretInBase32()));
                }
                return new Preview(entries, data.getBatchIndex(), data.getBatchSize());
            }
            if (!"otpauth".equalsIgnoreCase(uri.getScheme())) throw error("invalidUri");
            if (!"totp".equalsIgnoreCase(uri.getRawAuthority())) throw error("unsupportedParameters");
            Map<String, String> query = GoogleAuthMigrationParser.parseQuery(uri.getRawQuery());
            for (String key : query.keySet()) {
                if (!Arrays.asList("secret", "issuer", "algorithm", "digits", "period").contains(key)) throw error("unsupportedParameters");
            }
            if (query.containsKey("algorithm") && !"SHA1".equalsIgnoreCase(query.get("algorithm"))
                    || query.containsKey("digits") && !"6".equals(query.get("digits"))
                    || query.containsKey("period") && !"30".equals(query.get("period"))) throw error("unsupportedParameters");
            String path = uri.getRawPath();
            if (path == null || !path.startsWith("/") || path.length() <= 1) throw error("invalidUri");
            Entry entry = fromLabel(GoogleAuthMigrationParser.decodeComponent(path.substring(1)), query.get("issuer"), query.get("secret"));
            return new Preview(Collections.singletonList(entry), 0, 1);
        } catch (MfaCodecException e) { throw e; }
        catch (MigrationParseException e) { throw new MfaCodecException(e.getErrorKey()); }
        catch (Exception e) { throw error("invalidUri"); }
    }

    private Entry fromLabel(String rawName, String rawIssuer, String secret) {
        if (rawName == null) throw error("invalidUri");
        String name = rawName.trim();
        String issuer = rawIssuer == null ? "" : rawIssuer.trim();
        int separator = name.indexOf(':');
        if (separator >= 0) {
            String prefix = name.substring(0, separator).trim();
            if (prefix.isEmpty() || !issuer.isEmpty() && !issuer.equals(prefix)) throw error("invalidUri");
            issuer = prefix;
            name = name.substring(separator + 1).trim();
        }
        return normalizeEntry(name, issuer, secret);
    }

    private String readQr(MultipartFile file) {
        if (file == null || file.isEmpty()) throw error("invalidImage");
        if (file.getSize() > MAX_IMAGE_BYTES) throw error("imageTooLarge");
        byte[] bytes;
        try (InputStream input = file.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > MAX_IMAGE_BYTES) throw error("imageTooLarge");
                output.write(buffer, 0, count);
            }
            bytes = output.toByteArray();
        } catch (MfaCodecException e) { throw e; }
        catch (Exception e) { throw error("invalidImage"); }

        ImageReader reader = null;
        BufferedImage decoded = null;
        try (MemoryCacheImageInputStream input = new MemoryCacheImageInputStream(new ByteArrayInputStream(bytes))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) throw error("invalidImage");
            reader = readers.next();
            String format = reader.getFormatName().toLowerCase(Locale.ROOT);
            if (!"png".equals(format) && !"jpeg".equals(format) && !"jpg".equals(format) && !"gif".equals(format)) throw error("invalidImage");
            reader.setInput(input, true, true);
            // Read only dimensions before allocating a pixel buffer. Animated GIF imports only frame zero.
            dimensions(reader.getWidth(0), reader.getHeight(0));
            decoded = reader.read(0);
            if (decoded == null) throw error("invalidImage");
            dimensions(decoded.getWidth(), decoded.getHeight());
            Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
            hints.put(DecodeHintType.POSSIBLE_FORMATS, Collections.singletonList(BarcodeFormat.QR_CODE));
            hints.put(DecodeHintType.CHARACTER_SET, "UTF-8");
            BinaryBitmap bitmap = new BinaryBitmap(new HybridBinarizer(new BufferedImageLuminanceSource(decoded)));
            return new MultiFormatReader().decode(bitmap, hints).getText();
        } catch (MfaCodecException e) { throw e; }
        catch (ReaderException e) { throw error("qrNotFound"); }
        catch (Exception e) { throw error("invalidImage"); }
        finally {
            if (reader != null) reader.dispose();
            if (decoded != null) decoded.flush();
        }
    }

    private static void dimensions(int width, int height) {
        if (width <= 0 || height <= 0) throw error("invalidImage");
        if (width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION || (long) width * height > MAX_IMAGE_PIXELS) throw error("imageTooLarge");
    }
    private static String label(String raw, boolean required) {
        if (raw != null && raw.length() > MAX_NAME_LENGTH) throw error("invalidInput");
        String value = raw == null ? "" : raw.trim();
        if (required && value.isEmpty() || value.indexOf(':') >= 0) throw error("invalidInput");
        for (int i = 0; i < value.length(); i++) if (Character.isISOControl(value.charAt(i))) throw error("invalidInput");
        try {
            StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(value));
        } catch (Exception e) { throw error("invalidInput"); }
        return value;
    }
    private static String encode(String value) {
        try { return URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20"); }
        catch (Exception e) { throw error("invalidInput"); }
    }
    private static boolean present(String value) { return value != null && !value.trim().isEmpty(); }
    private static MfaCodecException error(String key) { return new MfaCodecException("mfa." + key); }
}
