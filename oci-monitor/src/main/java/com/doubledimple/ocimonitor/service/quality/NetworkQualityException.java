package com.doubledimple.ocimonitor.service.quality;

/** Only fixed, non-sensitive descriptions are allowed here. */
public final class NetworkQualityException extends RuntimeException {
    private final int status;
    private final String errorKey;
    public NetworkQualityException(int status, String errorKey, String message) {
        super(message);
        this.status = status;
        this.errorKey = errorKey;
    }
    public int getStatus() { return status; }
    public String getErrorKey() { return errorKey; }
}
