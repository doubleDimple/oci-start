package com.doubledimple.ociserver.config.datamigration;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Post-commit repair for the project's H2 2.x IDENTITY columns.
 * Import requires a maintenance window without other writers. The import service serializes imports in this JVM;
 * reading a sequence and applying DDL cannot provide an atomic fence against unrelated application/SQL writers.
 */
final class MigrationIdentityRepair {
    private MigrationIdentityRepair() { }

    static void repair(JdbcTemplate jdbc, List<MigrationSqlParser.Row> rows,
                       Map<String, MigrationSchema.TableInfo> schema) {
        Map<String, Set<String>> identities = new LinkedHashMap<>();
        for (MigrationSqlParser.Row row : rows) {
            if (row.preserved) continue;
            MigrationSchema.TableInfo table = schema.get(row.table);
            for (String name : row.values.keySet()) {
                MigrationSchema.ColumnInfo column = table.columns.get(name);
                if (column != null && column.generated && row.values.get(name) != null) {
                    identities.computeIfAbsent(row.table, key -> new LinkedHashSet<>()).add(name);
                }
            }
        }
        if (identities.isEmpty()) return;
        Boolean needsRepair = jdbc.execute((ConnectionCallback<Boolean>) connection ->
                "H2".equals(connection.getMetaData().getDatabaseProductName())
                        && connection.getMetaData().getDatabaseMajorVersion() >= 2);
        // MySQL advances its AUTO_INCREMENT when explicit higher values are inserted. H2 1.4 did so in Column.
        if (!Boolean.TRUE.equals(needsRepair)) return;
        for (Map.Entry<String, Set<String>> entry : identities.entrySet()) {
            MigrationSchema.TableInfo table = schema.get(entry.getKey());
            for (String name : entry.getValue()) {
                MigrationSchema.ColumnInfo column = table.columns.get(name);
                Identity state = readIdentity(jdbc, table, column);
                BigDecimal maximum = jdbc.queryForObject("SELECT MAX(" + table.columnSql(name) + ") FROM "
                        + table.sqlName(), BigDecimal.class);
                if (maximum == null) throw unknown();
                long largest = maximum.longValueExact();
                if (state.base > largest) continue;
                long next = Math.addExact(largest, state.increment);
                if (next > state.maximum) throw unknown();
                // Both identifiers originate in exact JDBC metadata; the only literal is a checked integral value.
                jdbc.execute("ALTER TABLE " + table.sqlName() + " ALTER COLUMN " + table.columnSql(name)
                        + " RESTART WITH " + Long.toString(next));
                Identity restored = readIdentity(jdbc, table, column);
                if (restored.base < next || restored.base <= largest) throw unknown();
            }
        }
    }

    private static Identity readIdentity(JdbcTemplate jdbc, MigrationSchema.TableInfo table,
                                         MigrationSchema.ColumnInfo column) {
        if (table.schemaName == null || table.schemaName.isEmpty()) throw unknown();
        List<Identity> values = jdbc.query("SELECT IDENTITY_BASE, IDENTITY_INCREMENT, IDENTITY_MAXIMUM "
                        + "FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? "
                        + "AND COLUMN_NAME = ? AND IS_IDENTITY = 'YES'",
                (result, index) -> {
                    BigDecimal base = result.getBigDecimal(1);
                    BigDecimal increment = result.getBigDecimal(2);
                    BigDecimal maximum = result.getBigDecimal(3);
                    if (base == null || increment == null || maximum == null) throw unknown();
                    Identity identity = new Identity(base.longValueExact(), increment.longValueExact(), maximum.longValueExact());
                    if (identity.increment <= 0 || identity.base > identity.maximum) throw unknown();
                    return identity;
                }, table.schemaName, table.physicalName, column.physicalName);
        if (values.size() != 1) throw unknown();
        return values.get(0);
    }

    private static MigrationImportException unknown() {
        return new MigrationImportException("migration.importFailed", "unknown");
    }
    private static final class Identity {
        final long base;
        final long increment;
        final long maximum;
        Identity(long base, long increment, long maximum) {
            this.base = base; this.increment = increment; this.maximum = maximum;
        }
    }
}
