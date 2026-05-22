package com.doubledimple.ociserver.config.exception;

/**
 * @author doubleDimple
 * @date 2024:10:04日 21:55
 */
public class OciException extends RuntimeException{

    private static final long serialVersionUID = 1L;
    private final int code;

    public OciException(ErrorCode errorCode) {
        super(errorCode.getMessage());
        this.code = errorCode.getCode();
    }

    public int getCode() {
        return code;
    }
}
