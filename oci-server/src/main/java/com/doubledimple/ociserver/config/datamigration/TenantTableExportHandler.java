package com.doubledimple.ociserver.config.datamigration;

import com.doubledimple.ocicommon.utils.FileUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.sql.ResultSet;
import java.util.Map;
import java.util.UUID;

/**
 * Tenant 表的特殊处理：
 * 导出时增加 KEY_FILE_CONTENT 字段
 * 导入时根据 KEY_FILE_CONTENT 写出 pem 文件，并设置 KEY_FILE 字段
 */
@Slf4j
@Component
public class TenantTableExportHandler implements TableExportHandler {

    private static final String TABLE_NAME = "TENANT";
    private static final String COL_KEY_FILE = "KEY_FILE";
    private static final String COL_KEY_FILE_CONTENT = "KEY_FILE_CONTENT";

    @Value("${baseFile.filePath}")
    private String baseFile;

    @Override
    public String getTableName() {
        return TABLE_NAME;
    }

    @Override
    public void addExtraColumns(Map<String, String> columnMap) {
        // 增加逻辑列：密钥文件内容，不存在于数据库本身
        columnMap.put(COL_KEY_FILE_CONTENT, "TEXT");
    }

    @Override
    public Object handleExportValue(String columnName, ResultSet rs) throws Exception {
        if (!COL_KEY_FILE_CONTENT.equalsIgnoreCase(columnName)) {
            return null;
        }

        String keyFilePath = rs.getString(COL_KEY_FILE);
        if (keyFilePath == null || keyFilePath.trim().isEmpty()) {
            return null;
        }

        File file = new File(keyFilePath);
        if (!file.exists()) {
            log.warn("导出 Tenant 时找不到密钥文件: {}", keyFilePath);
            return null;
        }

        // JDK8 读取文件内容
        byte[] bytes = Files.readAllBytes(file.toPath());
        return new String(bytes, StandardCharsets.UTF_8);
    }

    @Override
    public void handleImportValue(Map<String, Object> rowData, String ignoredKeyDir) throws Exception {

        Object contentObj = rowData.get(COL_KEY_FILE_CONTENT);
        if (contentObj == null) {
            rowData.remove(COL_KEY_FILE_CONTENT);
            return;
        }

        String content = contentObj.toString().trim();
        if (content.isEmpty()) {
            rowData.remove(COL_KEY_FILE_CONTENT);
            return;
        }

        // 使用你自己的工具类检查目录
        FileUtils.checkFile(baseFile);


        // 生成 key.pem 路径
        String keyFilePath = baseFile + UUID.randomUUID() + "_key.pem";

        // 写入密钥内容
        Files.write(new File(keyFilePath).toPath(), content.getBytes(StandardCharsets.UTF_8));

        // 更新 KEY_FILE 字段
        rowData.put(COL_KEY_FILE, keyFilePath);

        // 删除临时逻辑列
        rowData.remove(COL_KEY_FILE_CONTENT);

        log.debug("导入 Tenant 时，已写入密钥文件: {}", keyFilePath);
    }
}
