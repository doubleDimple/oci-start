package com.doubledimple.ociserver.config.datamigration;

import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.util.Map;

@Slf4j
@Component
public class LoginUserTableExportHandler implements TableExportHandler {

    private static final String TABLE_NAME = "LOGIN_USER";

    @Resource
    private JdbcTemplate jdbcTemplate;

    @Override
    public String getTableName() {
        return TABLE_NAME;
    }

    @Override
    public void addExtraColumns(Map<String, String> columnMap) {
        // LoginUser 没有需要额外导出的逻辑列
    }

    @Override
    public Object handleExportValue(String columnName, java.sql.ResultSet rs) {
        // LoginUser 不需要导出特殊字段
        return null;
    }

    /**
     * 导入 LoginUser 数据时：
     * - 如果数据库中已经存在相同 username，则跳过该记录
     */
    @Override
    public void handleImportValue(Map<String, Object> rowData, String baseDir) {
        Object usernameObj = rowData.get("USERNAME");
        if (usernameObj == null) {
            return;
        }

        String username = usernameObj.toString();

        // 查询数据库中是否已有该用户
        Integer count =
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM login_user WHERE username = ?",
                        Integer.class,
                        username
                );

        if (count != null && count > 0) {
            // 删除所有要插入的列，让外层 insert 语句不执行
            rowData.clear();
            log.warn("LoginUser 导入时跳过已有用户：{}", username);
        }
    }
}
