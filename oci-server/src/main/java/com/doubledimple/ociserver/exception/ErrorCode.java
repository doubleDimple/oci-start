package com.doubledimple.ociserver.exception;

// 异常代码枚举类
public enum ErrorCode {
    LIMIT_EXCEEDED(400,"LimitExceeded", "无法创建 always free 机器.配额已经超过免费额度"),
    CAPACITY(500,"Out of capacity", "Out of capacity"),
    CAPACITY_HOST(500,"Out of host capacity", "Out of host capacity"),

    ;

    private final int code;

    private final String errorType;
    private final String message;

    ErrorCode(int code,String errorType, String message) {
        this.code = code;
        this.errorType = errorType;
        this.message = message;
    }

    public int getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }

    public String getErrorType(){
        return errorType;
    }
}
