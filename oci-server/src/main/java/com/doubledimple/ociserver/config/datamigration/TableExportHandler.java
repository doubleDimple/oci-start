package com.doubledimple.ociserver.config.datamigration;

import java.sql.ResultSet;
import java.util.Map;

/**
 * 针对某张表的导出/导入扩展处理
 */
public interface TableExportHandler {

    /**
     * 表名（建议用大写），如 TENANT
     */
    String getTableName();

    /**
     * 导出时可以为此表追加“逻辑列”，例如 KEY_FILE_CONTENT
     * key: 列名（大写）
     * value: 类型描述（仅用于可读性，可以随便写，比如 TEXT）
     */
    void addExtraColumns(Map<String, String> columnMap);

    /**
     * 导出时，为逻辑列或特殊列提供值
     * @param columnName 当前列名（大写）
     * @param rs 当前行的 ResultSet
     * @return 列值（明文），如果返回 null 表示不处理/为空
     */
    Object handleExportValue(String columnName, ResultSet rs) throws Exception;

    /**
     * 导入时，对当前行数据做特殊处理（比如写密钥文件，修改字段值等）
     * @param rowData   列名 -> 值（都是已经解析好的明文）
     * @param baseDir   需要写文件的基础目录，例如 "/opt/keys"
     */
    void handleImportValue(Map<String, Object> rowData, String baseDir) throws Exception;
}
