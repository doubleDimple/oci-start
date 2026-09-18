package com.doubledimple.ociserver.config.datamigration;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class MigrationImportResult {
    private final int formatVersion;
    private final long importedRows;
    private final long preservedRows;
    private final List<TableResult> tables;

    public MigrationImportResult(int formatVersion, List<TableResult> tables) {
        this.formatVersion = formatVersion;
        this.tables = Collections.unmodifiableList(new ArrayList<>(tables));
        long imported = 0, preserved = 0;
        for (TableResult table : tables) {
            imported += table.getImportedRows();
            preserved += table.getPreservedRows();
        }
        this.importedRows = imported;
        this.preservedRows = preserved;
    }

    public int getFormatVersion() { return formatVersion; }
    public long getImportedRows() { return importedRows; }
    public long getPreservedRows() { return preservedRows; }
    public List<TableResult> getTables() { return tables; }

    public static class TableResult {
        private final String table;
        private final long importedRows;
        private final long preservedRows;

        public TableResult(String table, long importedRows, long preservedRows) {
            this.table = table;
            this.importedRows = importedRows;
            this.preservedRows = preservedRows;
        }
        public String getTable() { return table; }
        public long getImportedRows() { return importedRows; }
        public long getPreservedRows() { return preservedRows; }
    }
}
