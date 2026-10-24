package com.doubledimple.ociserver.service.permissions;

public class OciPermissionDeniedException extends RuntimeException {
    public OciPermissionDeniedException(String message) { super(message); }
}
