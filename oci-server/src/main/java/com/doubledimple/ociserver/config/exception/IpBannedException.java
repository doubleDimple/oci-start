package com.doubledimple.ociserver.config.exception;

public class IpBannedException extends RuntimeException {
    public IpBannedException(String message) {
        super(message);
    }
}
