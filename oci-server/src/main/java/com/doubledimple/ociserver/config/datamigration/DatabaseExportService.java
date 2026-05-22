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

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import javax.persistence.Entity;
import javax.persistence.Table;
import javax.servlet.http.HttpServletResponse;
import java.io.ByteArrayOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.text.SimpleDateFormat;
import java.util.*;

import static com.doubledimple.ocicommon.utils.ZipUtils.gzip;

/**
 * 导出整个数据库/指定表为 SQL 文件（无加密版本）
 */
@Slf4j
@Service
public class DatabaseExportService {

    //忽略不需要导入的的表的金台集合
    private static final Set<String> IGNORE_TABLES = new HashSet<>(Arrays.asList("BOOT_INSTANCE","OCI_COMPUTER_INFO","LOGIN_USER","INSTANCE_TRAFFIC","INSTALL_APP"));

    private final JdbcTemplate jdbcTemplate;
    private final TableExportHandlerRegistry handlerRegistry;
    private final ApplicationContext applicationContext;

    public DatabaseExportService(JdbcTemplate jdbcTemplate,
                                 TableExportHandlerRegistry handlerRegistry,
                                 ApplicationContext applicationContext) {
        this.jdbcTemplate = jdbcTemplate;
        this.handlerRegistry = handlerRegistry;
        this.applicationContext = applicationContext;
    }

    /**
     * 导出“业务表”到内存流（只导出 com.doubledimple.dao.entity 下带 @Entity 的表）
     */
    public ByteArrayOutputStream exportDatabaseToStream() throws Exception {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        PrintWriter writer = new PrintWriter(new OutputStreamWriter(baos, StandardCharsets.UTF_8), true);

        try (Connection conn = jdbcTemplate.getDataSource().getConnection()) {

            DatabaseMetaData metaData = conn.getMetaData();

            writer.println("-- OCI-START PLAIN BACKUP (NO ENCRYPTION)");
            writer.println("-- GENERATED AT: " + new Timestamp(System.currentTimeMillis()));
            writer.println();

            Set<String> businessTableNames = getBusinessTableNames("com.doubledimple.dao.entity");

            for (String tableName : businessTableNames) {
                if (IGNORE_TABLES.contains(tableName)) {
                    log.debug("跳过抢机相关表，不导出: {}", tableName);
                    continue;
                }
                exportSingleTable(metaData, conn, tableName, writer);
            }
        }

        writer.flush();
        return baos;
    }


    /**
     * 扫描实体类，获取所有业务表表名（全大写）
     */
    private Set<String> getBusinessTableNames(String basePackage) throws Exception {
        Set<String> tableNames = new LinkedHashSet<>();

        ResourcePatternResolver resourcePatternResolver = new PathMatchingResourcePatternResolver();
        CachingMetadataReaderFactory metadataReaderFactory = new CachingMetadataReaderFactory(resourcePatternResolver);

        String pattern = ResourcePatternResolver.CLASSPATH_ALL_URL_PREFIX +
                basePackage.replace('.', '/') + "/**/*.class";
        Resource[] resources = resourcePatternResolver.getResources(pattern);

        for (Resource resource : resources) {
            if (!resource.isReadable()) {
                continue;
            }
            MetadataReader metadataReader = metadataReaderFactory.getMetadataReader(resource);
            String className = metadataReader.getClassMetadata().getClassName();
            Class<?> clazz = Class.forName(className);

            if (clazz.isAnnotationPresent(Entity.class)) {
                String tableName = getTableNameFromEntity(clazz);
                if (tableName != null && !tableName.trim().isEmpty()) {
                    tableNames.add(tableName.toUpperCase());
                }
            }
        }

        log.info("业务表列表: {}", tableNames);
        return tableNames;
    }

    /**
     * 与你 EntitySchemaChecker 里的 getTableName 逻辑保持一致
     */
    private String getTableNameFromEntity(Class<?> entityClass) {
        Table tableAnn = entityClass.getAnnotation(Table.class);
        if (tableAnn != null && tableAnn.name() != null && !tableAnn.name().isEmpty()) {
            return tableAnn.name();
        }
        // 如果没写 @Table(name="...")，那就用类名
        return entityClass.getSimpleName();
    }

    /**
     * 原来的单表导出逻辑基本不变，只是调用方从“全库所有表”变成“业务表集合”
     */
    private void exportSingleTable(DatabaseMetaData metaData,
                                   Connection conn,
                                   String tableName,
                                   PrintWriter writer) throws Exception {

        TableExportHandler handler = handlerRegistry.getHandler(tableName);

        // 1. 拿数据库里真实存在的列
        ResultSet columns = metaData.getColumns(null, null, tableName, null);
        Map<String, String> dbColumnMap = new LinkedHashMap<>();
        while (columns.next()) {
            String colName = columns.getString("COLUMN_NAME");
            String typeName = columns.getString("TYPE_NAME");

            if (!"TENANT".equalsIgnoreCase(tableName) && "ID".equals(colName)) {
                continue;
            }
            dbColumnMap.put(colName.toUpperCase(), typeName);
        }

        if (dbColumnMap.isEmpty()) {
            log.warn("表 [{}] 在数据库中未找到列定义，可能不存在，跳过导出", tableName);
            return;
        }

        // 2. 真实列 + 逻辑列
        Map<String, String> allColumnMap = new LinkedHashMap<>(dbColumnMap);
        if (handler != null) {
            handler.addExtraColumns(allColumnMap);
        }

        List<String> dbColumns = new ArrayList<>(dbColumnMap.keySet());
        List<String> allColumns = new ArrayList<>(allColumnMap.keySet());

        writer.println("-- ----------------------------");
        writer.println("-- TABLE: " + tableName);
        writer.println("-- ----------------------------");

        String selectSql = "SELECT " + String.join(", ", dbColumns) + " FROM " + tableName;

        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(selectSql)) {

            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

            while (rs.next()) {
                StringBuilder sb = new StringBuilder();
                sb.append("INSERT INTO ").append(tableName)
                        .append(" (").append(String.join(", ", allColumns)).append(") VALUES (");

                for (int i = 0; i < allColumns.size(); i++) {
                    String col = allColumns.get(i);

                    Object value;
                    if (dbColumns.contains(col)) {
                        value = rs.getObject(col);
                    } else if (handler != null) {
                        value = handler.handleExportValue(col, rs);
                    } else {
                        value = null;
                    }

                    String out;
                    if (value == null) {
                        out = "NULL";
                    } else if (value instanceof Number) {
                        out = value.toString();
                    } else if (value instanceof Timestamp) {
                        out = "'" + sdf.format((Timestamp) value) + "'";
                    } else if (value instanceof java.util.Date) {
                        out = "'" + sdf.format((java.util.Date) value) + "'";
                    } else {
                        out = "'" + escape(value.toString()) + "'";
                    }

                    sb.append(out);
                    if (i < allColumns.size() - 1) {
                        sb.append(", ");
                    }
                }

                sb.append(");");
                writer.println(sb.toString());
            }

            writer.println();
        }
    }

    private String escape(String s) {
        if (s == null) return "";
        return s.replace("'", "''");
    }


    /**
     * 新版：导出 “整文件加密” 的 .enc 备份
     * 不修改原来的任何逻辑
     */
    public void exportEncryptedBackup(HttpServletResponse response) throws Exception {
        // 1. 获取旧导出逻辑生成的明文 SQL
        ByteArrayOutputStream baos = exportDatabaseToStream();
        String plainSql = new String(baos.toByteArray(), StandardCharsets.UTF_8);

        // 2. 生成动态 master-key & IV（一次性）
        String masterKey = AesFileEncryptor.generateMasterKey();
        byte[] iv = AesFileEncryptor.generateIv();
        String ivBase64 = Base64.getEncoder().encodeToString(iv);

        // 3. AES256 加密整个 SQL 文件
        //String cipherBase64 = AesFileEncryptor.encrypt(plainSql, masterKey, iv);
        byte[] compressed = gzip(plainSql);
        String cipherBase64 = AesFileEncryptor.encryptBytes(compressed, masterKey, iv);


        // 4. 封装成可识别的迁移加密文件格式
        StringBuilder sb = new StringBuilder();
        sb.append("-----BEGIN OCI-START MIGRATION-----\n");
        sb.append("IV:").append(ivBase64).append("\n");
        sb.append("DATA:").append(cipherBase64).append("\n");
        sb.append("-----END OCI-START MIGRATION-----\n");

        // 5. 设置下载响应头
        response.setContentType("application/octet-stream");
        response.setHeader("Content-Disposition", "attachment; filename=\"oci-start_migration.enc\"");

        // 6. 返回 masterKey 给前端（只显示一次）
        response.setHeader("X-MASTER-KEY", masterKey);

        // 7. 输出文件内容
        PrintWriter writer = new PrintWriter(
                new OutputStreamWriter(response.getOutputStream(), StandardCharsets.UTF_8)
        );
        writer.write(sb.toString());
        writer.flush();

        log.info("数据库成功导出加密备份");
    }


}
