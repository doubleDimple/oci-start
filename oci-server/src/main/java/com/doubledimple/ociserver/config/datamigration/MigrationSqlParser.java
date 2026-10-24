package com.doubledimple.ociserver.config.datamigration;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Parses the exporter's literal INSERT grammar. No uploaded SQL is ever executed. */
final class MigrationSqlParser {
    static final int MAX_ROWS = 100000;
    static final int MAX_VALUE_BYTES = 1024 * 1024;
    static final String V2_MARKER = "-- OCI-START-BACKUP-V2";
    private final String source;
    private int cursor;

    MigrationSqlParser(String source) { this.source = source; }

    Parsed parse() {
        int version = source.startsWith(V2_MARKER + "\n") || source.startsWith(V2_MARKER + "\r\n")
                || source.equals(V2_MARKER) ? 2 : 1;
        List<Row> rows = new ArrayList<>();
        skipSpace();
        while (cursor < source.length()) {
            word("INSERT");
            word("INTO");
            String table = identifier();
            expect('(');
            List<String> columns = new ArrayList<>();
            do {
                String column = identifier();
                if (columns.contains(column) || columns.size() >= 512) throw invalid();
                columns.add(column);
            } while (consume(','));
            expect(')');
            word("VALUES");
            expect('(');
            Map<String, Object> values = new LinkedHashMap<>();
            for (int i = 0; i < columns.size(); i++) {
                if (i > 0) expect(',');
                values.put(columns.get(i), value());
            }
            expect(')');
            expect(';');
            rows.add(new Row(table, values));
            if (rows.size() > MAX_ROWS) throw rejected("limitExceeded");
            skipSpace();
        }
        if (rows.isEmpty()) throw invalid();
        return new Parsed(version, rows);
    }

    private Object value() {
        skipSpace();
        if (cursor >= source.length()) throw invalid();
        if (source.charAt(cursor) == '\'') return string();
        if ((source.charAt(cursor) == 'X' || source.charAt(cursor) == 'x')
                && cursor + 1 < source.length() && source.charAt(cursor + 1) == '\'') {
            cursor++;
            String hex = string();
            if (hex.length() % 2 != 0 || !hex.matches("[0-9a-fA-F]*")) throw invalid();
            byte[] bytes = new byte[hex.length() / 2];
            for (int i = 0; i < bytes.length; i++) {
                bytes[i] = (byte) ((Character.digit(hex.charAt(i * 2), 16) << 4) | Character.digit(hex.charAt(i * 2 + 1), 16));
            }
            return bytes;
        }
        int start = cursor;
        while (cursor < source.length() && !Character.isWhitespace(source.charAt(cursor))
                && source.charAt(cursor) != ',' && source.charAt(cursor) != ')') cursor++;
        String token = source.substring(start, cursor);
        if ("NULL".equalsIgnoreCase(token)) return null;
        if ("TRUE".equalsIgnoreCase(token)) return Boolean.TRUE;
        if ("FALSE".equalsIgnoreCase(token)) return Boolean.FALSE;
        if (token.length() > 1024 || !token.matches("[+-]?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")) throw invalid();
        try {
            BigDecimal number = new BigDecimal(token);
            if (number.scale() < -1000 || number.scale() > 1000 || number.precision() > 1000) throw invalid();
            return number;
        } catch (NumberFormatException e) {
            throw invalid();
        }
    }

    private String string() {
        if (source.charAt(cursor++) != '\'') throw invalid();
        StringBuilder value = new StringBuilder();
        while (cursor < source.length()) {
            char ch = source.charAt(cursor++);
            if (ch == '\'') {
                if (cursor < source.length() && source.charAt(cursor) == '\'') {
                    cursor++;
                    value.append('\'');
                } else {
                    return value.toString();
                }
            } else {
                value.append(ch);
            }
            if (value.length() > MAX_VALUE_BYTES * 2) throw rejected("limitExceeded");
        }
        throw invalid();
    }

    private String identifier() {
        skipSpace();
        if (cursor >= source.length()) throw invalid();
        int start = cursor;
        char quote = source.charAt(cursor);
        String name;
        if (quote == '"' || quote == '`') {
            cursor++;
            start = cursor;
            while (cursor < source.length() && source.charAt(cursor) != quote) cursor++;
            if (cursor >= source.length()) throw invalid();
            name = source.substring(start, cursor++);
        } else {
            while (cursor < source.length() && (Character.isLetterOrDigit(source.charAt(cursor)) || source.charAt(cursor) == '_')) cursor++;
            name = source.substring(start, cursor);
        }
        if (name.length() > 128 || !name.matches("[A-Za-z_][A-Za-z0-9_]*")) throw invalid();
        return name.toUpperCase(Locale.ROOT);
    }

    private void word(String word) {
        skipSpace();
        if (!source.regionMatches(true, cursor, word, 0, word.length())) throw invalid();
        cursor += word.length();
        if (cursor < source.length() && (Character.isLetterOrDigit(source.charAt(cursor)) || source.charAt(cursor) == '_')) throw invalid();
    }

    private boolean consume(char ch) {
        skipSpace();
        if (cursor < source.length() && source.charAt(cursor) == ch) { cursor++; return true; }
        return false;
    }

    private void expect(char ch) { if (!consume(ch)) throw invalid(); }

    private void skipSpace() {
        while (cursor < source.length()) {
            if (Character.isWhitespace(source.charAt(cursor))) {
                cursor++;
            } else if (source.charAt(cursor) == '-' && cursor + 1 < source.length() && source.charAt(cursor + 1) == '-') {
                cursor += 2;
                while (cursor < source.length() && source.charAt(cursor) != '\n' && source.charAt(cursor) != '\r') cursor++;
            } else return;
        }
    }

    private static MigrationImportException invalid() { return rejected("invalidSql"); }
    private static MigrationImportException rejected(String code) { return new MigrationImportException("migration." + code, "rejected"); }

    static final class Parsed {
        final int version;
        final List<Row> rows;
        Parsed(int version, List<Row> rows) { this.version = version; this.rows = rows; }
    }

    static final class Row {
        final String table;
        final Map<String, Object> values;
        boolean preserved;
        Row(String table, Map<String, Object> values) { this.table = table; this.values = values; }
    }
}
