package com.doubledimple.ociserver.config.exception;

// 异常代码枚举类
public enum ErrorCode {
    LIMIT_EXCEEDED(400,"LimitExceeded", "无法创建 always free 机器.配额已经超过免费额度"),
    CAPACITY(500,"Out of capacity", "Out of capacity"),
    CAPACITY_HOST(500,"Out of host capacity", "Out of host capacity"),
    NOT_AUTH(401,"NotAuthenticated", "无权限"),
    NET_WORK_ERROR(401,"network error", "网络异常"),
    NOT_AUTH_NOT_FUND(404,"NotAuthorizedOrNotFound", "无权限或者资源不存在"),
    TOO_MANY_REQUESTS(429,"TooManyRequests", "当前用户请求次数过多"),
    NO_AVAILABLE_SHAPE(429,"NoAvailableShapeWasFound", "没有可用的镜像"),

    DEF_ERROR_NO_TENANT_ID(501,"NoTenantId", "没有租户"),

    DISK_SIZE_EXCEEDED(502, "DiskSizeExceeded", "磁盘超出限制"),


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
