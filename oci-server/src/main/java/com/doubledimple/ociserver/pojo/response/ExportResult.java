package com.doubledimple.ociserver.pojo.response;

import lombok.AllArgsConstructor;
import lombok.Data;

/**
 * 导出结果对象
 */
@Data
@AllArgsConstructor
public class ExportResult {

    /**
     * 导出的 SQL 文件路径
     */
    private String filePath;

    /**
     * 一次性 master-key（hex），只显示一次给用户
     */
    private String masterKeyHex;
}
