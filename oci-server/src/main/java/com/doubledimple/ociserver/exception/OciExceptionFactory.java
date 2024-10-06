package com.doubledimple.ociserver.exception;

/**
 * @author doubleDimple
 * @date 2024:10:04日 21:57
 */
public class OciExceptionFactory {

    public static OciException createException(ErrorCode errorCode) {
        throw new OciException(errorCode);
    }
}
