package com.doubledimple.ociserver.config.exception;

/**
 * @author doubleDimple
 * @date 2024:12:01日 09:10
 */
public class RateLimitException extends RuntimeException {
    public RateLimitException(String message) {
        super(message);
    }
}
