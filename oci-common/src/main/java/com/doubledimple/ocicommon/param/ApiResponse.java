package com.doubledimple.ocicommon.param;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Builder;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName ApiResponse
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-25 12:45
 */
@Data
@Builder
@Schema(description = "API响应结果")
public class ApiResponse {
    @Schema(description = "是否成功")
    private boolean success;
    @Schema(description = "错误信息")
    private String message;
    @Schema(description = "数据")
    private Object data;
    @Schema(description = "返回码")
    private int code;

    public static final String SUCCESS = "success";

    public static ApiResponse success(String message) {
        return ApiResponse.builder()
                .success(true)
                .message(message)
                .code(200)
                .build();
    }

    public static ApiResponse success(String message,Object data) {
        return ApiResponse.builder()
                .success(true)
                .data(data)
                .message(message)
                .code(200)
                .build();
    }

    public static ApiResponse success() {
        return ApiResponse.builder()
                .success(true)
                .message("success")
                .code(200)
                .build();
    }

    public static ApiResponse success(Object data) {
        return ApiResponse.builder()
                .success(true)
                .data(data)
                .message("success")
                .code(200)
                .build();
    }

    public static ApiResponse error(String message) {
        return ApiResponse.builder()
                .success(false)
                .message(message)
                .code(500)
                .build();
    }
}
