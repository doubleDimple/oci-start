package com.doubledimple.ocicommon.param;

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
public class ApiResponse {
    private boolean success;
    private String message;
    private Object data;
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
