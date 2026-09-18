package com.doubledimple.ociserver.config.datamigration;

import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.core.type.classreading.CachingMetadataReaderFactory;

import javax.persistence.Entity;
import javax.persistence.Table;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/** Actual columns/keys from the current connection, restricted to the existing exported entity scope. */
final class MigrationSchema {
    private static final Set<String> IGNORED = new HashSet<>(Arrays.asList(
            "BOOT_INSTANCE", "OCI_COMPUTER_INFO", "LOGIN_USER", "INSTANCE_TRAFFIC", "INSTALL_APP"));

    static Map<String, TableInfo> read(Connection connection) throws Exception {
        Set<String> allowed = entityTables();
        DatabaseMetaData metadata = connection.getMetaData();
        String catalog = connection.getCatalog();
        String schema = null;
        try { schema = connection.getSchema(); } catch (SQLException ignored) { /* Some JDBC drivers only expose a catalog. */ }
        String quote = metadata.getIdentifierQuoteString();
        quote = quote == null ? "" : quote.trim();
        Map<String, TableInfo> tables = new LinkedHashMap<>();
        try (ResultSet actual = metadata.getTables(catalog, schema, "%", new String[]{"TABLE", "BASE TABLE"})) {
            while (actual.next()) {
                String physical = actual.getString("TABLE_NAME");
                String name = physical.toUpperCase(Locale.ROOT);
                if (!allowed.contains(name)) continue;
                if (!physical.matches("[A-Za-z_][A-Za-z0-9_]*") || tables.containsKey(name)) throw rejected("schemaMismatch");
                String actualSchema = actual.getString("TABLE_SCHEM");
                String actualCatalog = actual.getString("TABLE_CAT");
                if (actualSchema != null && !actualSchema.isEmpty() && !actualSchema.matches("[A-Za-z_][A-Za-z0-9_]*")) throw rejected("schemaMismatch");
                TableInfo table = new TableInfo(physical, actualSchema, quote);
                try (ResultSet columns = metadata.getColumns(catalog, actualSchema, physical, "%")) {
                    while (columns.next()) {
                        // JDBC treats underscores in tableNamePattern as wildcards. Only this exact physical table belongs here.
                        if (!physical.equals(columns.getString("TABLE_NAME"))
                                || !Objects.equals(actualSchema, columns.getString("TABLE_SCHEM"))
                                || !Objects.equals(actualCatalog, columns.getString("TABLE_CAT"))) continue;
                        String column = columns.getString("COLUMN_NAME");
                        if (!column.matches("[A-Za-z_][A-Za-z0-9_]*")) throw rejected("schemaMismatch");
                        if (table.columns.put(column.toUpperCase(Locale.ROOT), new ColumnInfo(column,
                                columns.getInt("DATA_TYPE"), columns.getInt("NULLABLE") != DatabaseMetaData.columnNoNulls,
                                "YES".equalsIgnoreCase(columns.getString("IS_AUTOINCREMENT")), columns.getString("COLUMN_DEF") != null)) != null) throw rejected("schemaMismatch");
                    }
                }
                try (ResultSet keys = metadata.getPrimaryKeys(catalog, actualSchema, physical)) {
                    while (keys.next()) table.primaryKeys.add(keys.getString("COLUMN_NAME").toUpperCase(Locale.ROOT));
                }
                if (table.columns.isEmpty() || table.primaryKeys.isEmpty() || !table.columns.keySet().containsAll(table.primaryKeys)) throw rejected("schemaMismatch");
                tables.put(name, table);
            }
        }
        return tables;
    }

    private static Set<String> entityTables() throws Exception {
        PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
        CachingMetadataReaderFactory readers = new CachingMetadataReaderFactory(resolver);
        Set<String> names = new HashSet<>();
        for (Resource resource : resolver.getResources("classpath*:com/doubledimple/dao/entity/**/*.class")) {
            if (!resource.isReadable()) throw rejected("schemaMismatch");
            String className = readers.getMetadataReader(resource).getClassMetadata().getClassName();
            Class<?> type = Class.forName(className, false, MigrationSchema.class.getClassLoader());
            if (!type.isAnnotationPresent(Entity.class)) continue;
            Table annotation = type.getAnnotation(Table.class);
            String name = annotation == null || annotation.name().isEmpty() ? type.getSimpleName() : annotation.name();
            names.add(name.toUpperCase(Locale.ROOT));
        }
        names.removeAll(IGNORED);
        return names;
    }

    private static MigrationImportException rejected(String code) { return new MigrationImportException("migration." + code, "rejected"); }

    static final class TableInfo {
        final String physicalName;
        final String schemaName;
        final String quote;
        final Map<String, ColumnInfo> columns = new LinkedHashMap<>();
        final Set<String> primaryKeys = new LinkedHashSet<>();
        TableInfo(String physicalName, String schemaName, String quote) {
            this.physicalName = physicalName; this.schemaName = schemaName; this.quote = quote;
        }
        private String quoted(String value) { return quote + value + ("[".equals(quote) ? "]" : quote); }
        String sqlName() { return (schemaName == null || schemaName.isEmpty() ? "" : quoted(schemaName) + ".") + quoted(physicalName); }
        String columnSql(String name) {
            ColumnInfo column = columns.get(name);
            if (column == null) throw rejected("schemaMismatch");
            return quoted(column.physicalName);
        }
    }

    static final class ColumnInfo {
        final String physicalName;
        final int type;
        final boolean nullable;
        final boolean generated;
        final boolean hasDefault;
        ColumnInfo(String name, int type, boolean nullable, boolean generated, boolean hasDefault) {
            this.physicalName = name; this.type = type; this.nullable = nullable;
            this.generated = generated; this.hasDefault = hasDefault;
        }
    }
}
