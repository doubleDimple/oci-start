package com.doubledimple.ociserver.config.datamigration;

import com.doubledimple.ocicommon.utils.AesFileEncryptor;
import com.doubledimple.ocicommon.utils.ZipUtils;
import lombok.extern.slf4j.Slf4j;
import net.sf.jsqlparser.parser.CCJSqlParserUtil;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.LocalDate;
import java.util.*;
import java.util.zip.GZIPInputStream;

/**
 * 从 SQL 文件导入数据（无加密版本）
 */
@Slf4j
@Service
public class DatabaseImportService {

    private final JdbcTemplate jdbcTemplate;
    private final TableExportHandlerRegistry handlerRegistry;

    public DatabaseImportService(JdbcTemplate jdbcTemplate,
                                 TableExportHandlerRegistry handlerRegistry) {
        this.jdbcTemplate = jdbcTemplate;
        this.handlerRegistry = handlerRegistry;
    }

    /**
     * 从 SQL 文件导入数据
     *
     * @param sqlFilePath 导出得到的 SQL 文件路径
     * @param keyBaseDir  恢复密钥文件等需要写入的目录（给 Tenant handler 用）
     */
    public void importFromFile(String sqlFilePath, String keyBaseDir) throws Exception {

        List<String> lines = new ArrayList<>();
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(Files.newInputStream(Paths.get(sqlFilePath)), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                lines.add(line.trim());
            }
        }

        for (String line : lines) {
            if (line.isEmpty() || line.startsWith("--")) {
                continue;
            }
            if (!line.toUpperCase(Locale.ROOT).startsWith("INSERT INTO ")) {
                continue;
            }

            processInsertLine(line, keyBaseDir);
        }

        log.info("SQL 文件导入完成: {}", sqlFilePath);
    }

    private void processInsertLine(String line, String keyBaseDir) throws Exception {

        String upper = line.toUpperCase(Locale.ROOT);
        int intoIdx = upper.indexOf("INTO ");
        int valuesIdx = upper.indexOf("VALUES");

        if (intoIdx < 0 || valuesIdx < 0) {
            return;
        }

        int tableNameStart = intoIdx + "INTO ".length();
        int colParenStart = line.indexOf('(', tableNameStart);
        String tableName = line.substring(tableNameStart, colParenStart).trim();

        int colParenEnd = line.indexOf(')', colParenStart);
        String colPart = line.substring(colParenStart + 1, colParenEnd).trim();
        String[] colArr = Arrays.stream(colPart.split(","))
                .map(String::trim)
                .toArray(String[]::new);

        int valParenStart = line.indexOf('(', valuesIdx);
        int valParenEnd = line.lastIndexOf(')');
        String valPart = line.substring(valParenStart + 1, valParenEnd).trim();

        List<String> valTokens = splitValues(valPart);

        if (valTokens.size() != colArr.length) {
            log.warn("列数量与值数量不匹配, 跳过: {}", line);
            return;
        }

        Map<String, Object> rowData = new LinkedHashMap<>();

        for (int i = 0; i < colArr.length; i++) {
            String col = colArr[i].trim();
            String token = valTokens.get(i).trim();

            Object value;
            if ("NULL".equalsIgnoreCase(token)) {
                value = null;
            } else if (token.startsWith("'") && token.endsWith("'")) {
                String inner = token.substring(1, token.length() - 1).replace("''", "'");
                value = inner;
            } else {
                // 简单认为是数字或其他
                value = token;
            }

            rowData.put(col.toUpperCase(), value);
        }

        // 调用 handler 做特殊处理（比如写 key 文件）
        TableExportHandler handler = handlerRegistry.getHandler(tableName);
        if (handler != null) {
            handler.handleImportValue(rowData, keyBaseDir);
        }

        if (rowData.isEmpty()) {
            log.info("跳过 {} 表的一条记录（可能被 handler 忽略）", tableName);
            return;
        }

        if ("TENANT_EMAIL_CONFIG".equalsIgnoreCase(tableName)){
            rowData.put("LAST_RESET_DATE", LocalDate.now());
        }
        if ("OCI_SSH_CONN".equalsIgnoreCase(tableName)) {

            // HOST 为空直接跳过
            Object host = rowData.get("HOST");
            if (host == null || host.toString().trim().isEmpty()) {
                rowData.put("HOST", "127.0.0.1");
            }

            // REMARK 不能为空 → 补默认值
            Object remark = rowData.get("REMARK");
            if (remark == null || remark.toString().trim().isEmpty()) {
                rowData.put("REMARK", ""); // 补空字符串
            }

            // NAME 也可能为空 → 补默认值
            Object name = rowData.get("NAME");
            if (name == null || name.toString().trim().isEmpty()) {
                rowData.put("NAME", "Unknown");
            }

            // USERNAME 为空也给一个默认值
            Object folderId = rowData.get("FOLDER_ID");
            if (folderId == null || folderId.toString().trim().isEmpty()) {
                rowData.put("FOLDER_ID", "-100");
            }
        }


        // 处理后的列集合
        List<String> finalCols = new ArrayList<>(rowData.keySet());
        String colSql = String.join(", ", finalCols);
        String placeholderSql = String.join(", ", Collections.nCopies(finalCols.size(), "?"));

        if (!validateAllColumnsExist(tableName, rowData.keySet())) {
            log.warn("跳过 {} 表的记录：存在未知字段 -> {}", tableName, rowData.keySet());
            return;
        }
        String insertSql = "INSERT INTO " + tableName + " (" + colSql + ") VALUES (" + placeholderSql + ")";

        Object[] params = new Object[finalCols.size()];
        for (int i = 0; i < finalCols.size(); i++) {
            params[i] = rowData.get(finalCols.get(i));
        }

        try {
            jdbcTemplate.update(insertSql, params);
        } catch (DuplicateKeyException ex) {
            log.debug("跳过重复记录 [{}]: {}", tableName, rowData);
        }

    }

    /**
     * 把 values 部分拆成一个个值，支持字符串中包含逗号
     */
    private List<String> splitValues(String valPart) {
        List<String> result = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean inString = false;

        for (int i = 0; i < valPart.length(); i++) {
            char c = valPart.charAt(i);
            if (c == '\'') {
                inString = !inString;
                current.append(c);
            } else if (c == ',' && !inString) {
                result.add(current.toString().trim());
                current.setLength(0);
            } else {
                current.append(c);
            }
        }

        if (current.length() > 0) {
            result.add(current.toString().trim());
        }

        return result;
    }

    /**
     * 自动识别文件格式（明文SQL 或 加密 .enc）
     */
    @Transactional
    public void importAuto(String content, String masterKey) throws Exception {


        // 1) 如果是加密格式
        if (content.startsWith("-----BEGIN OCI-START MIGRATION-----")) {
            if (masterKey == null || masterKey.trim().isEmpty()) {
                throw new IllegalArgumentException("这是加密文件，必须提供 masterKey 才能导入！");
            }

            importEncryptedContent(content, masterKey);
            return;
        }
        importFromSqlText(content);
    }



    /**
     * 加密内容导入：解析 IV、DATA，解密后走明文 SQL 导入逻辑
     */
    /*private void importEncryptedContent(String content, String masterKey) throws Exception {

        BufferedReader br = new BufferedReader(new StringReader(content));
        String line;

        String ivBase64 = null;
        String dataBase64 = null;

        while ((line = br.readLine()) != null) {
            line = line.trim();
            if (line.startsWith("IV:")) {
                ivBase64 = line.substring(3).trim();
            } else if (line.startsWith("DATA:")) {
                dataBase64 = line.substring(5).trim();
            }
        }

        if (ivBase64 == null || dataBase64 == null) {
            throw new IllegalArgumentException("加密文件格式错误，未找到 IV 或 DATA");
        }

        byte[] iv = Base64.getDecoder().decode(ivBase64);

        // 使用 master-key 解密
        String plainSql = AesFileEncryptor.decrypt(
                dataBase64,
                masterKey,
                iv
        );
        importFromSqlText(plainSql);
    }*/

    private void importEncryptedContent(String content, String masterKey) throws Exception {

        BufferedReader br = new BufferedReader(new StringReader(content));
        String line;

        String ivBase64 = null;
        String dataBase64 = null;

        while ((line = br.readLine()) != null) {
            if (line.startsWith("IV:")) {
                ivBase64 = line.substring(3).trim();
            } else if (line.startsWith("DATA:")) {
                dataBase64 = line.substring(5).trim();
            }
        }

        if (ivBase64 == null || dataBase64 == null) {
            throw new IllegalArgumentException("加密文件格式错误，未找到 IV 或 DATA");
        }

        // 1) 解密得到压缩数据
        byte[] iv = Base64.getDecoder().decode(ivBase64);
        byte[] decryptedBytes = AesFileEncryptor.decryptBytes(dataBase64, masterKey, iv);

        // 2) GZIP 解压得到明文 SQL
        String plainSql = ZipUtils.ungzip(decryptedBytes);

        // 3) 执行 SQL 导入逻辑
        importFromSqlText(plainSql);
    }


    public void importFromSqlText(String sqlText) throws Exception {

        Set<Long> tenantIds = new HashSet<>();

        StringBuilder buffer = new StringBuilder();
        BufferedReader br = new BufferedReader(new StringReader(sqlText));
        String line;

        // ========================= 第一遍扫描重复 =========================
        while ((line = br.readLine()) != null) {

            String rawNew = line;
            String trimmed = rawNew.trim();

            // 保留 PEM 私钥行
            if (trimmed.contains("PRIVATE KEY")) {
                buffer.append(rawNew).append("\n");
                continue;
            }

            if (trimmed.isEmpty() || trimmed.startsWith("--")) continue;

            buffer.append(rawNew).append("\n");

            // 判断是否完整一条 SQL
            if (!isCompleteSql(buffer.toString())) {
                continue;
            }

            // 拿到完整 SQL
            String fullSql = buffer.toString().trim();
            buffer.setLength(0); // reset

            if (!fullSql.toUpperCase().startsWith("INSERT INTO TENANT")) {
                continue;
            }

            // 解析列名
            int colStart = fullSql.indexOf('(');
            int colEnd = fullSql.indexOf(')', colStart);
            if (colStart < 0 || colEnd < 0) continue;

            String colPart = fullSql.substring(colStart + 1, colEnd);
            String[] colArr = Arrays.stream(colPart.split(","))
                    .map(String::trim)
                    .toArray(String[]::new);

            int valuesIdx = fullSql.toUpperCase().indexOf("VALUES");
            int valStart = fullSql.indexOf('(', valuesIdx);
            int valEnd = fullSql.lastIndexOf(')');
            if (valStart < 0 || valEnd < 0) continue;

            String valPart = fullSql.substring(valStart + 1, valEnd);
            List<String> valTokens = splitValues(valPart);

            int idIndex = -1;
            for (int i = 0; i < colArr.length; i++) {
                if (colArr[i].equalsIgnoreCase("ID")) {
                    idIndex = i;
                    break;
                }
            }
            if (idIndex < 0) continue;

            String raw = valTokens.get(idIndex).replace("'", "").trim();
            if (raw.matches("\\d+")) {
                tenantIds.add(Long.valueOf(raw));
            }
        }

        // ================== 校验是否重复 ==================
        for (Long tid : tenantIds) {
            Long count = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM TENANT WHERE ID = ?",
                    Long.class,
                    tid
            );
            if (count != null && count > 0) {
                throw new IllegalStateException(
                        "数据已经导入过,不要重复导入"
                );
            }
        }

        // ========================= 第二遍真正导入 =========================
        buffer.setLength(0);
        br = new BufferedReader(new StringReader(sqlText));

        while ((line = br.readLine()) != null) {

            String raw = line;                    // 原始行保留
            String trimmed = raw.trim();          // 用来判断

            // 保留 PEM 私钥所有行
            if (trimmed.contains("PRIVATE KEY")) {
                buffer.append(raw).append("\n");
                continue;
            }

            // 其它过滤逻辑用 trimmed
            if (trimmed.isEmpty() || trimmed.startsWith("--")) continue;

            buffer.append(raw).append("\n");

            // 不是完整 sql → 等下一行
            if (!isCompleteSql(buffer.toString())) continue;

            String fullSql = buffer.toString().trim();
            buffer.setLength(0);

            if (!fullSql.toUpperCase().startsWith("INSERT INTO")) continue;

            processInsertLine(fullSql, null);
        }

        log.info("SQL导入完成");
    }


    private boolean validateAllColumnsExist(String tableName, Set<String> columns) {
        try {
            String sql = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?";
            List<String> existingCols = jdbcTemplate.queryForList(sql, String.class, tableName.toUpperCase());

            for (String col : columns) {
                if (!existingCols.contains(col.toUpperCase())) {
                    log.warn("表 {} 不存在字段: {}", tableName, col);
                    return false; // 直接不导入
                }
            }
            return true;
        } catch (Exception e) {
            log.error("校验列存在失败: {}", e.getMessage());
            return false;
        }
    }


    private boolean isCompleteSql(String sql) {
        try {
            CCJSqlParserUtil.parseStatements(sql);
            return true;
        } catch (net.sf.jsqlparser.JSQLParserException e) {
            return false;
        }
    }


}
