package com.doubledimple.ociserver.config.datamigration;

import com.doubledimple.ocicommon.utils.AesFileEncryptor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.SqlParameterValue;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.zip.GZIPInputStream;

/** Strict append-only import. SQL identifiers and values are reconstructed from validated metadata. */
@Service
public class DatabaseImportService {
    public static final int MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
    public static final int MAX_SQL_BYTES = 50 * 1024 * 1024;
    private static final String BEGIN = "-----BEGIN OCI-START MIGRATION-----";
    private static final String END = "-----END OCI-START MIGRATION-----";

    private final JdbcTemplate jdbcTemplate;
    private final TableExportHandlerRegistry handlerRegistry;
    private final TransactionTemplate transaction;
    private final TransactionTemplate outsideTransaction;

    public DatabaseImportService(JdbcTemplate jdbcTemplate, TableExportHandlerRegistry handlerRegistry,
                                 PlatformTransactionManager transactionManager) {
        this.jdbcTemplate = jdbcTemplate;
        this.handlerRegistry = handlerRegistry;
        this.transaction = new TransactionTemplate(transactionManager);
        // The public receipt must describe this import's actual completion, not an enclosing caller's future commit.
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.outsideTransaction = new TransactionTemplate(transactionManager);
        this.outsideTransaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_NOT_SUPPORTED);
    }

    public MigrationImportResult importEncryptedStrict(String content, String masterKey) {
        String envelope = normalizeText(content, MAX_UPLOAD_BYTES);
        if (!envelope.startsWith(BEGIN)) throw rejected("invalidFile");
        return importSql(decrypt(envelope, masterKey));
    }

    public MigrationImportResult importAutoWithResult(String content, String masterKey) {
        String input = normalizeText(content, MAX_UPLOAD_BYTES);
        return input.startsWith(BEGIN) ? importEncryptedStrict(input, masterKey) : importSql(input);
    }

    // Keep the old Java/HTTP entry points; all paths now share validation and transaction handling.
    public void importAuto(String content, String masterKey) throws Exception { importAutoWithResult(content, masterKey); }
    public void importFromSqlText(String sqlText) throws Exception { importSql(sqlText); }
    public void importFromFile(String sqlFilePath, String ignoredKeyBaseDir) throws Exception {
        try (InputStream input = Files.newInputStream(Paths.get(sqlFilePath))) {
            importAutoWithResult(decodeUtf8(readBounded(input, MAX_UPLOAD_BYTES)), null);
        }
    }

    private synchronized MigrationImportResult importSql(String sqlText) {
        String sql = normalizeText(sqlText, MAX_SQL_BYTES);
        MigrationSqlParser.Parsed parsed = new MigrationSqlParser(sql).parse();
        AtomicInteger completed = new AtomicInteger(-1);
        AtomicBoolean attempted = new AtomicBoolean(false);
        Map<String, MigrationSchema.TableInfo> validatedSchema = new LinkedHashMap<>();
        try {
            MigrationImportResult result = transaction.execute(status -> {
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override public void afterCompletion(int completionStatus) { completed.set(completionStatus); }
                });
                Map<String, MigrationSchema.TableInfo> schema = readSchema();
                prepare(parsed, schema);
                validatedSchema.putAll(schema);
                Map<String, long[]> counts = new LinkedHashMap<>();
                for (MigrationSqlParser.Row row : parsed.rows) {
                    long[] count = counts.computeIfAbsent(row.table, key -> new long[2]);
                    if (row.preserved) { count[1]++; continue; }
                    attempted.set(true);
                    TableExportHandler handler = handlerRegistry.getHandler(row.table);
                    if (handler != null) {
                        try {
                            handler.handleImportValue(row.values, null);
                        } catch (Exception e) {
                            throw new MigrationImportException("migration.importFailed", "unknown");
                        }
                    }
                    insert(row, schema.get(row.table));
                    count[0]++;
                }
                List<MigrationImportResult.TableResult> tables = new ArrayList<>();
                for (Map.Entry<String, long[]> count : counts.entrySet()) {
                    tables.add(new MigrationImportResult.TableResult(count.getKey(), count.getValue()[0], count.getValue()[1]));
                }
                return new MigrationImportResult(parsed.version, tables);
            });
            if (result == null || completed.get() != TransactionSynchronization.STATUS_COMMITTED) {
                throw new MigrationImportException("migration.importFailed", "unknown");
            }
            // H2 identity DDL implicitly commits. Run it only after this data transaction's confirmed commit.
            // Any failure below must remain unknown: the appended rows and restored keys may already be committed.
            try {
                outsideTransaction.execute(status -> {
                    MigrationIdentityRepair.repair(jdbcTemplate, parsed.rows, validatedSchema);
                    return null;
                });
            } catch (Exception failure) {
                throw new MigrationImportException("migration.importFailed", "unknown");
            }
            return result;
        } catch (Exception cause) {
            String code = cause instanceof MigrationImportException ? ((MigrationImportException) cause).getCode()
                    : cause instanceof DuplicateKeyException ? "migration.duplicateData"
                    : cause instanceof DataIntegrityViolationException ? "migration.schemaMismatch" : "migration.importFailed";
            String outcome = !attempted.get() && cause instanceof MigrationImportException
                    && "rejected".equals(((MigrationImportException) cause).getOutcome()) ? "rejected"
                    : completed.get() == TransactionSynchronization.STATUS_ROLLED_BACK ? "rolledBack" : "unknown";
            // Discard the exception/cause: JDBC messages can contain SQL parameters, PEMs and passwords.
            throw new MigrationImportException(code, outcome);
        }
    }

    private Map<String, MigrationSchema.TableInfo> readSchema() {
        Map<String, MigrationSchema.TableInfo> schema = jdbcTemplate.execute(
                (ConnectionCallback<Map<String, MigrationSchema.TableInfo>>) connection -> {
                    try { return MigrationSchema.read(connection); }
                    catch (MigrationImportException e) { throw e; }
                    catch (Exception e) { throw rejected("schemaMismatch"); }
                });
        if (schema == null) throw rejected("schemaMismatch");
        return schema;
    }

    private void prepare(MigrationSqlParser.Parsed parsed, Map<String, MigrationSchema.TableInfo> schema) {
        Map<String, Set<String>> seenKeys = new HashMap<>();
        for (MigrationSqlParser.Row row : parsed.rows) {
            MigrationSchema.TableInfo table = schema.get(row.table);
            if (table == null) throw rejected("schemaMismatch");
            boolean systemConfig = "SYSTEM_CONFIG".equals(row.table);
            if (systemConfig) row.values.remove("ID");
            else if (!row.values.keySet().containsAll(table.primaryKeys)) throw rejected("unsupportedFormat");

            for (Map.Entry<String, Object> entry : row.values.entrySet()) {
                if ("TENANT".equals(row.table) && "KEY_FILE_CONTENT".equals(entry.getKey())) {
                    if (entry.getValue() != null && !(entry.getValue() instanceof String)) throw rejected("invalidSql");
                    checkValueSize(entry.getValue());
                    continue;
                }
                MigrationSchema.ColumnInfo column = table.columns.get(entry.getKey());
                if (column == null) throw rejected("schemaMismatch");
                entry.setValue(convert(entry.getValue(), column));
            }
            for (Map.Entry<String, MigrationSchema.ColumnInfo> column : table.columns.entrySet()) {
                if (!row.values.containsKey(column.getKey()) && !column.getValue().nullable
                        && !column.getValue().generated && !column.getValue().hasDefault) throw rejected("schemaMismatch");
            }
            if ("TENANT".equals(row.table)) {
                TableExportHandler handler = handlerRegistry.getHandler(row.table);
                if (!(handler instanceof TenantTableExportHandler)) throw rejected("schemaMismatch");
                try { ((TenantTableExportHandler) handler).validateImportValue(row.values); }
                catch (Exception e) { throw rejected("invalidFile"); }
            }

            Set<String> keyColumns = systemConfig ? Collections.singleton("CONFIG_KEY") : table.primaryKeys;
            StringBuilder key = new StringBuilder();
            List<Object> parameters = new ArrayList<>();
            List<String> conditions = new ArrayList<>();
            for (String column : keyColumns) {
                Object value = row.values.get(column);
                if (value == null || (systemConfig && (!(value instanceof String) || ((String) value).isEmpty()))) throw rejected("invalidSql");
                String part = value instanceof byte[] ? Base64.getEncoder().encodeToString((byte[]) value) : value.toString();
                key.append(part.length()).append(':').append(part);
                conditions.add(table.columnSql(column) + " = ?");
                parameters.add(parameter(table.columns.get(column), value));
            }
            if (!seenKeys.computeIfAbsent(row.table, name -> new HashSet<>()).add(key.toString())) throw rejected("duplicateData");
            Long existing = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM " + table.sqlName()
                    + " WHERE " + String.join(" AND ", conditions), Long.class, parameters.toArray());
            if (existing == null) throw rejected("schemaMismatch");
            if (existing > 0) {
                if (!systemConfig) throw rejected("duplicateData");
                // The old append import preserved existing configuration keys. Report that exception explicitly.
                row.preserved = true;
            }
        }
    }

    private void insert(MigrationSqlParser.Row row, MigrationSchema.TableInfo table) {
        if (row.values.isEmpty()) throw new MigrationImportException("migration.importFailed", "unknown");
        List<String> columns = new ArrayList<>();
        List<Object> parameters = new ArrayList<>();
        for (Map.Entry<String, Object> entry : row.values.entrySet()) {
            MigrationSchema.ColumnInfo column = table.columns.get(entry.getKey());
            if (column == null) throw new MigrationImportException("migration.schemaMismatch", "unknown");
            columns.add(table.columnSql(entry.getKey()));
            parameters.add(parameter(column, entry.getValue()));
        }
        int count = jdbcTemplate.update("INSERT INTO " + table.sqlName() + " (" + String.join(", ", columns)
                + ") VALUES (" + String.join(", ", Collections.nCopies(columns.size(), "?")) + ")", parameters.toArray());
        if (count != 1) throw new MigrationImportException("migration.importFailed", "unknown");
    }

    private static Object convert(Object value, MigrationSchema.ColumnInfo column) {
        if (value == null) {
            if (!column.nullable) throw rejected("invalidSql");
            return null;
        }
        checkValueSize(value);
        try {
            switch (column.type) {
                case Types.BOOLEAN: case Types.BIT:
                    if (value instanceof Boolean) return value;
                    if ("true".equalsIgnoreCase(value.toString()) || "1".equals(value.toString())) return true;
                    if ("false".equalsIgnoreCase(value.toString()) || "0".equals(value.toString())) return false;
                    throw rejected("invalidSql");
                case Types.TINYINT: return decimal(value).byteValueExact();
                case Types.SMALLINT: return decimal(value).shortValueExact();
                case Types.INTEGER: return decimal(value).intValueExact();
                case Types.BIGINT: return decimal(value).longValueExact();
                case Types.NUMERIC: case Types.DECIMAL: return decimal(value);
                case Types.FLOAT: case Types.REAL: case Types.DOUBLE:
                    double number = decimal(value).doubleValue();
                    if (Double.isNaN(number) || Double.isInfinite(number)) throw rejected("invalidSql");
                    return number;
                case Types.DATE: return java.sql.Date.valueOf(string(value));
                case Types.TIME:
                    String time = string(value);
                    java.time.LocalTime.parse(time);
                    return time;
                case Types.TIMESTAMP: return java.sql.Timestamp.valueOf(string(value));
                case Types.BINARY: case Types.VARBINARY: case Types.LONGVARBINARY: case Types.BLOB:
                    if (!(value instanceof byte[])) throw rejected("invalidSql");
                    return value;
                case Types.CHAR: case Types.VARCHAR: case Types.LONGVARCHAR: case Types.NCHAR:
                case Types.NVARCHAR: case Types.LONGNVARCHAR: case Types.CLOB: case Types.NCLOB:
                    return string(value);
                default: throw rejected("schemaMismatch");
            }
        } catch (MigrationImportException e) { throw e; }
        catch (Exception e) { throw rejected("invalidSql"); }
    }

    private static BigDecimal decimal(Object value) {
        if (!(value instanceof BigDecimal)) throw rejected("invalidSql");
        return (BigDecimal) value;
    }
    private static SqlParameterValue parameter(MigrationSchema.ColumnInfo column, Object value) {
        // java.sql.Time loses fractional seconds. Bind validated text, letting the actual TIME column convert it.
        return new SqlParameterValue(column.type == Types.TIME && value instanceof String ? Types.VARCHAR : column.type, value);
    }
    private static String string(Object value) {
        if (!(value instanceof String)) throw rejected("invalidSql");
        return (String) value;
    }
    private static void checkValueSize(Object value) {
        int size = value instanceof String ? ((String) value).getBytes(StandardCharsets.UTF_8).length
                : value instanceof byte[] ? ((byte[]) value).length : 0;
        if (size > MigrationSqlParser.MAX_VALUE_BYTES) throw rejected("limitExceeded");
    }

    private static String decrypt(String envelope, String masterKey) {
        String[] lines = envelope.split("\\r?\\n", -1);
        if (lines.length != 4 || !BEGIN.equals(lines[0]) || !lines[1].startsWith("IV:")
                || !lines[2].startsWith("DATA:") || !END.equals(lines[3])) throw rejected("invalidFile");
        try {
            byte[] key = Base64.getDecoder().decode(masterKey == null ? "" : masterKey.trim());
            if (key.length != 32) throw rejected("invalidKey");
        } catch (IllegalArgumentException e) { throw rejected("invalidKey"); }
        byte[] iv;
        String data = lines[2].substring(5);
        try {
            iv = Base64.getDecoder().decode(lines[1].substring(3));
            byte[] encrypted = Base64.getDecoder().decode(data);
            if (iv.length != 16 || encrypted.length == 0 || encrypted.length % 16 != 0) throw rejected("invalidFile");
        } catch (IllegalArgumentException e) { throw rejected("invalidFile"); }
        byte[] compressed;
        try { compressed = AesFileEncryptor.decryptBytes(data, masterKey.trim(), iv); }
        catch (Exception e) { throw rejected("invalidKey"); }
        try (GZIPInputStream input = new GZIPInputStream(new ByteArrayInputStream(compressed))) {
            return decodeUtf8(readBounded(input, MAX_SQL_BYTES));
        } catch (MigrationImportException e) { throw e; }
        catch (Exception e) { throw rejected("invalidFile"); }
    }

    private static String normalizeText(String content, int maxBytes) {
        if (content == null) throw rejected("invalidFile");
        if (content.getBytes(StandardCharsets.UTF_8).length > maxBytes) throw rejected("limitExceeded");
        if (content.startsWith("\uFEFF")) content = content.substring(1);
        content = content.trim();
        if (content.isEmpty()) throw rejected("invalidFile");
        return content;
    }

    private static byte[] readBounded(InputStream input, int maxBytes) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if ((long) output.size() + count > maxBytes) throw rejected("limitExceeded");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static String decodeUtf8(byte[] bytes) {
        try {
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        } catch (Exception e) { throw rejected("invalidFile"); }
    }

    private static MigrationImportException rejected(String code) {
        return new MigrationImportException("migration." + code, "rejected");
    }
}
