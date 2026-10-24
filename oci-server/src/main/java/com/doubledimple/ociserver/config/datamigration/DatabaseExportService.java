package com.doubledimple.ociserver.config.datamigration;

import com.doubledimple.ocicommon.utils.AesFileEncryptor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationContext;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.core.io.support.ResourcePatternResolver;
import org.springframework.core.type.classreading.CachingMetadataReaderFactory;
import org.springframework.core.type.classreading.MetadataReader;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import javax.persistence.Entity;
import javax.persistence.Table;
import javax.servlet.http.HttpServletResponse;
import java.io.BufferedWriter;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.io.Writer;
import java.math.BigDecimal;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.sql.Blob;
import java.sql.Clob;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.SQLFeatureNotSupportedException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;

import static com.doubledimple.ocicommon.utils.ZipUtils.gzip;

/** Versioned, bounded data export. The encrypted envelope and its one-time key remain compatible. */
@Slf4j
@Service
public class DatabaseExportService {
    public static final String FORMAT_MARKER = "-- OCI-START-BACKUP-V2";
    public static final int MAX_SQL_BYTES = 50 * 1024 * 1024;
    public static final int MAX_ENVELOPE_BYTES = 10 * 1024 * 1024;
    public static final int MAX_VALUE_BYTES = 1024 * 1024;
    public static final int MAX_ROWS = 100000;
    private static final Set<String> IGNORE_TABLES = new HashSet<>(Arrays.asList(
            "BOOT_INSTANCE", "OCI_COMPUTER_INFO", "LOGIN_USER", "INSTANCE_TRAFFIC", "INSTALL_APP"));

    private final JdbcTemplate jdbcTemplate;
    private final TableExportHandlerRegistry handlerRegistry;
    private final ApplicationContext applicationContext;

    public DatabaseExportService(JdbcTemplate jdbcTemplate, TableExportHandlerRegistry handlerRegistry,
                                 ApplicationContext applicationContext) {
        this.jdbcTemplate = jdbcTemplate;
        this.handlerRegistry = handlerRegistry;
        this.applicationContext = applicationContext;
    }

    public ByteArrayOutputStream exportDatabaseToStream() throws Exception {
        BoundedOutput output = new BoundedOutput(MAX_SQL_BYTES);
        try (Connection connection = jdbcTemplate.getDataSource().getConnection()) {
            boolean autoCommit = connection.getAutoCommit();
            boolean readOnly = connection.isReadOnly();
            int isolation = connection.getTransactionIsolation();
            try {
                DatabaseMetaData metadata = connection.getMetaData();
                if (!metadata.supportsTransactions()
                        || !metadata.supportsTransactionIsolationLevel(Connection.TRANSACTION_SERIALIZABLE)) {
                    throw new IllegalStateException("数据库不支持一致性备份事务");
                }
                connection.setTransactionIsolation(Connection.TRANSACTION_SERIALIZABLE);
                try { connection.setReadOnly(true); } catch (SQLFeatureNotSupportedException ignored) { /* SELECT only. */ }
                connection.setAutoCommit(false);
                Map<String, TableLocation> tables = availableTables(connection, metadata);
                try (Writer writer = new BufferedWriter(new OutputStreamWriter(output, StandardCharsets.UTF_8.newEncoder()
                        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)))) {
                    writer.write(FORMAT_MARKER + "\n");
                    writer.write("-- GENERATED AT: " + new Timestamp(System.currentTimeMillis()) + "\n\n");
                    int rowCount = 0;
                    for (String name : getBusinessTableNames("com.doubledimple.dao.entity")) {
                        if (IGNORE_TABLES.contains(name)) continue;
                        TableLocation table = tables.get(name);
                        if (table == null) throw new IllegalStateException("数据库结构不完整，无法创建备份");
                        rowCount = exportTable(metadata, connection, table, writer, rowCount);
                    }
                }
            } finally {
                // No write is made by export. Release its snapshot before restoring the pooled connection.
                if (!connection.getAutoCommit()) connection.rollback();
                connection.setReadOnly(readOnly);
                connection.setTransactionIsolation(isolation);
                connection.setAutoCommit(autoCommit);
            }
        } catch (Exception failure) {
            // JDBC and file exceptions can contain row contents or private key paths.
            throw new IllegalStateException("备份导出失败，请确认数据结构、密钥文件及备份大小限制");
        }
        return output;
    }

    private Map<String, TableLocation> availableTables(Connection connection, DatabaseMetaData metadata) throws Exception {
        String schema;
        try { schema = connection.getSchema(); } catch (SQLFeatureNotSupportedException ignored) { schema = null; }
        Map<String, TableLocation> result = new LinkedHashMap<>();
        try (ResultSet tables = metadata.getTables(connection.getCatalog(), schema, null, null)) {
            while (tables.next()) {
                String type = tables.getString("TABLE_TYPE");
                if (!"TABLE".equalsIgnoreCase(type) && !"BASE TABLE".equalsIgnoreCase(type)) continue;
                String name = tables.getString("TABLE_NAME");
                if (!validIdentifier(name)) continue;
                String canonical = name.toUpperCase(Locale.ROOT);
                TableLocation table = new TableLocation(tables.getString("TABLE_CAT"), tables.getString("TABLE_SCHEM"), name);
                if (result.put(canonical, table) != null) throw new IllegalStateException("数据库表名称不唯一");
            }
        }
        return result;
    }

    private Set<String> getBusinessTableNames(String basePackage) throws Exception {
        Set<String> names = new TreeSet<>();
        ResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
        CachingMetadataReaderFactory factory = new CachingMetadataReaderFactory(resolver);
        String pattern = ResourcePatternResolver.CLASSPATH_ALL_URL_PREFIX + basePackage.replace('.', '/') + "/**/*.class";
        for (Resource resource : resolver.getResources(pattern)) {
            if (!resource.isReadable()) continue;
            MetadataReader reader = factory.getMetadataReader(resource);
            Class<?> entity = Class.forName(reader.getClassMetadata().getClassName(), false, applicationContext.getClassLoader());
            if (!entity.isAnnotationPresent(Entity.class)) continue;
            Table table = entity.getAnnotation(Table.class);
            String name = table != null && !table.name().isEmpty() ? table.name() : entity.getSimpleName();
            if (!validIdentifier(name)) throw new IllegalStateException("不支持的数据库表名称");
            names.add(name.toUpperCase(Locale.ROOT));
        }
        return names;
    }

    private int exportTable(DatabaseMetaData metadata, Connection connection, TableLocation table,
                            Writer writer, int rowCount) throws Exception {
        String name = table.name.toUpperCase(Locale.ROOT);
        TableExportHandler handler = handlerRegistry.getHandler(name);
        Map<String, String> columns = new LinkedHashMap<>();
        Map<String, Integer> types = new LinkedHashMap<>();
        try (ResultSet definition = metadata.getColumns(table.catalog, table.schema, table.name, null)) {
            while (definition.next()) {
                // JDBC metadata treats underscores as wildcards, including within the schema pattern.
                if (!table.name.equals(definition.getString("TABLE_NAME"))
                        || !Objects.equals(table.schema, definition.getString("TABLE_SCHEM"))
                        || !Objects.equals(table.catalog, definition.getString("TABLE_CAT"))) continue;
                String column = definition.getString("COLUMN_NAME");
                if (!validIdentifier(column)) throw new IllegalStateException("不支持的数据库列名称");
                String canonical = column.toUpperCase(Locale.ROOT);
                if (columns.put(canonical, column) != null) throw new IllegalStateException("数据库列名称不唯一");
                int type = definition.getInt("DATA_TYPE");
                if (!supportedType(type)) throw new IllegalStateException("数据库包含当前迁移格式不支持的字段类型");
                types.put(canonical, type);
            }
        }
        if (columns.isEmpty()) throw new IllegalStateException("数据库结构不完整");
        Map<String, String> allColumns = new LinkedHashMap<>(columns);
        if (handler != null) handler.addExtraColumns(allColumns);
        for (String column : allColumns.keySet()) if (!validIdentifier(column)) throw new IllegalStateException("不支持的扩展列");
        List<String> selects = new ArrayList<>();
        for (String column : columns.values()) selects.add(quote(metadata, column));
        String physicalTable = (table.schema == null || table.schema.isEmpty() ? "" : quote(metadata, table.schema) + ".")
                + quote(metadata, table.name);
        String sql = "SELECT " + String.join(", ", selects) + " FROM " + physicalTable;
        if (columns.containsKey("ID")) sql += " ORDER BY " + quote(metadata, columns.get("ID"));
        writer.write("-- TABLE: " + name + "\n");
        try (Statement statement = connection.createStatement()) {
            statement.setMaxRows(MAX_ROWS - rowCount + 1);
            statement.setFetchSize(200);
            statement.setQueryTimeout(60);
            try (ResultSet rows = statement.executeQuery(sql)) {
                while (rows.next()) {
                    if (++rowCount > MAX_ROWS) throw new IllegalStateException("备份记录数量超出限制");
                    writer.write("INSERT INTO " + name + " (" + String.join(", ", allColumns.keySet()) + ") VALUES (");
                    boolean first = true;
                    for (String column : allColumns.keySet()) {
                        if (!first) writer.write(", ");
                        first = false;
                        Object value;
                        if (columns.containsKey(column)) {
                            String actual = columns.get(column);
                            int type = types.get(column);
                            // java.sql.Time cannot represent fractional seconds; ask JDBC for its full textual value.
                            if (type == Types.TIME) value = rows.getString(actual);
                            else if (type == Types.TIMESTAMP) value = rows.getTimestamp(actual);
                            else if (type == Types.DATE) value = rows.getDate(actual);
                            else value = rows.getObject(actual);
                        } else value = handler == null ? null : handler.handleExportValue(column, rows);
                        writer.write(literal(value));
                    }
                    writer.write(");\n");
                }
            }
        }
        writer.write("\n");
        return rowCount;
    }

    private String literal(Object value) throws Exception {
        if (value == null) return "NULL";
        if (value instanceof Clob) {
            Clob clob = (Clob) value;
            try (Reader reader = clob.getCharacterStream()) { return textLiteral(readText(reader)); }
            finally { clob.free(); }
        }
        if (value instanceof Blob) {
            Blob blob = (Blob) value;
            try (InputStream input = blob.getBinaryStream()) { return binaryLiteral(readBytes(input)); }
            finally { blob.free(); }
        }
        if (value instanceof byte[]) return binaryLiteral((byte[]) value);
        if (value instanceof Boolean) return (Boolean) value ? "TRUE" : "FALSE";
        if (value instanceof Number) {
            if (value instanceof Double && (Double.isNaN((Double) value) || Double.isInfinite((Double) value))
                    || value instanceof Float && (Float.isNaN((Float) value) || Float.isInfinite((Float) value))) {
                throw new IllegalStateException("备份包含非有限数值");
            }
            if (value instanceof BigDecimal) {
                BigDecimal decimal = (BigDecimal) value;
                if (decimal.scale() < -1000 || decimal.scale() > 1000 || decimal.precision() > 1000) {
                    throw new IllegalStateException("备份数值精度超出限制");
                }
            }
            String number = value instanceof BigDecimal ? ((BigDecimal) value).toPlainString() : value.toString();
            if (number.length() > 1024 || !number.matches("[+-]?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")) {
                throw new IllegalStateException("不支持的数据库数值");
            }
            BigDecimal decimal = new BigDecimal(number);
            if (decimal.scale() < -1000 || decimal.scale() > 1000 || decimal.precision() > 1000) {
                throw new IllegalStateException("备份数值精度超出限制");
            }
            return number;
        }
        // Timestamp.toString preserves its nanoseconds; no locale- or second-only date formatter.
        if (value instanceof CharSequence || value instanceof Character || value instanceof java.sql.Timestamp
                || value instanceof java.sql.Date || value instanceof java.sql.Time
                || value instanceof java.time.temporal.TemporalAccessor || value instanceof java.util.UUID) {
            return textLiteral(value.toString());
        }
        throw new IllegalStateException("不支持的数据库字段类型");
    }

    private static String readText(Reader reader) throws Exception {
        StringBuilder result = new StringBuilder();
        char[] buffer = new char[4096];
        int count;
        while ((count = reader.read(buffer)) != -1) {
            if (result.length() + count > MAX_VALUE_BYTES) throw new IllegalStateException("单字段备份超出限制");
            result.append(buffer, 0, count);
        }
        return result.toString();
    }

    private static byte[] readBytes(InputStream input) throws Exception {
        BoundedOutput output = new BoundedOutput(MAX_VALUE_BYTES);
        byte[] buffer = new byte[4096];
        int count;
        while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        return output.toByteArray();
    }

    private static String textLiteral(String value) {
        if (value.length() > MAX_VALUE_BYTES || value.getBytes(StandardCharsets.UTF_8).length > MAX_VALUE_BYTES) {
            throw new IllegalStateException("单字段备份超出限制");
        }
        return "'" + value.replace("'", "''") + "'";
    }

    private static String binaryLiteral(byte[] value) {
        if (value.length > MAX_VALUE_BYTES) throw new IllegalStateException("单字段备份超出限制");
        StringBuilder result = new StringBuilder(value.length * 2 + 3).append("X'");
        for (byte item : value) {
            result.append(Character.forDigit((item >>> 4) & 15, 16));
            result.append(Character.forDigit(item & 15, 16));
        }
        return result.append('\'').toString();
    }

    private static boolean validIdentifier(String value) { return value != null && value.matches("[A-Za-z_][A-Za-z0-9_]*"); }
    private static boolean supportedType(int type) {
        switch (type) {
            case Types.BOOLEAN: case Types.BIT: case Types.TINYINT: case Types.SMALLINT: case Types.INTEGER:
            case Types.BIGINT: case Types.NUMERIC: case Types.DECIMAL: case Types.FLOAT: case Types.REAL:
            case Types.DOUBLE: case Types.DATE: case Types.TIME: case Types.TIMESTAMP: case Types.BINARY:
            case Types.VARBINARY: case Types.LONGVARBINARY: case Types.BLOB: case Types.CHAR: case Types.VARCHAR:
            case Types.LONGVARCHAR: case Types.NCHAR: case Types.NVARCHAR: case Types.LONGNVARCHAR:
            case Types.CLOB: case Types.NCLOB: return true;
            default: return false;
        }
    }
    private static String quote(DatabaseMetaData metadata, String identifier) throws Exception {
        if (!validIdentifier(identifier)) throw new IllegalStateException("不支持的数据库标识符");
        String quote = metadata.getIdentifierQuoteString().trim();
        return quote + identifier + ("[".equals(quote) ? "]" : quote);
    }

    public void exportEncryptedBackup(HttpServletResponse response) throws Exception {
        ByteArrayOutputStream stream = exportDatabaseToStream();
        String sql = new String(stream.toByteArray(), StandardCharsets.UTF_8);
        String masterKey = AesFileEncryptor.generateMasterKey();
        byte[] iv = AesFileEncryptor.generateIv();
        byte[] compressed = gzip(sql);
        // Reject before allocating a base64/envelope that can never fit the upload limit.
        if (compressed.length > MAX_ENVELOPE_BYTES * 3 / 4 - 512) throw new IllegalStateException("加密备份超过 10 MiB 限制");
        String cipher = AesFileEncryptor.encryptBytes(compressed, masterKey, iv);
        String envelope = "-----BEGIN OCI-START MIGRATION-----\nIV:" + Base64.getEncoder().encodeToString(iv)
                + "\nDATA:" + cipher + "\n-----END OCI-START MIGRATION-----\n";
        byte[] bytes = envelope.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_ENVELOPE_BYTES) throw new IllegalStateException("加密备份超过 10 MiB 限制");
        response.setContentType("application/octet-stream");
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Content-Disposition", "attachment; filename=\"oci-start_migration.enc\"");
        response.setHeader("X-MASTER-KEY", masterKey);
        response.setContentLength(bytes.length);
        response.getOutputStream().write(bytes);
        response.getOutputStream().flush();
        log.info("数据库加密备份已导出");
    }

    private static final class TableLocation {
        final String catalog;
        final String schema;
        final String name;
        TableLocation(String catalog, String schema, String name) { this.catalog = catalog; this.schema = schema; this.name = name; }
    }

    private static final class BoundedOutput extends ByteArrayOutputStream {
        private final int limit;
        BoundedOutput(int limit) { this.limit = limit; }
        @Override public synchronized void write(int value) {
            if (count >= limit) throw new IllegalStateException("备份大小超出限制");
            super.write(value);
        }
        @Override public synchronized void write(byte[] value, int offset, int length) {
            if (length > limit - count) throw new IllegalStateException("备份大小超出限制");
            super.write(value, offset, length);
        }
    }
}
