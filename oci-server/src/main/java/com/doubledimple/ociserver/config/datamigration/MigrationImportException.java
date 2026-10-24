package com.doubledimple.ociserver.config.datamigration;

/** Public migration errors never retain SQL, credentials, file contents or a nested exception. */
public class MigrationImportException extends RuntimeException {
    private final String code;
    private final String outcome;

    public MigrationImportException(String code, String outcome) {
        super(code);
        this.code = code;
        this.outcome = outcome;
    }

    public String getCode() { return code; }
    public String getOutcome() { return outcome; }
}
