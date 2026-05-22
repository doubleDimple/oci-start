package com.doubledimple.ocicommon.param;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @version 1.0.0
 * @ClassName ScriptResult
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-01-04 12:24
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class ScriptResult {
    private boolean success;      // 脚本是否成功执行
    private int exitCode;         // 退出码
    private String output;        // 标准输出内容
    private String error;         // 错误输出内容
}
