package com.doubledimple.ociserver.service.permissions;

import com.oracle.bmc.model.BmcException;
import lombok.extern.slf4j.Slf4j;

/** Diagnostic metadata only: never log SDK messages, causes, bodies, URLs or uploaded credentials. */
@Slf4j
final class ManagedImportDiagnostics {
    enum Stage { DOMAIN_AUDIT, DOMAIN_RECONCILE, IDENTITY_PROVISION }

    private ManagedImportDiagnostics() { }

    static void failed(Stage stage, Exception exception) {
        BmcException sdk = exception instanceof BmcException ? (BmcException) exception : null;
        log.warn("OCI 专用身份操作失败: stage={}, type={}, causeType={}, status={}, serviceCode={}, requestId={}",
                stage, exception.getClass().getSimpleName(),
                exception.getCause() == null ? "-" : exception.getCause().getClass().getSimpleName(),
                sdk == null ? "-" : sdk.getStatusCode(),
                sdk == null ? "-" : safeServiceCode(sdk.getServiceCode()),
                sdk == null ? "-" : safeRequestId(sdk.getOpcRequestId()));
    }

    private static String safeServiceCode(String value) {
        if (value == null) return "-";
        return value.matches("[A-Za-z][A-Za-z0-9_]{0,63}") ? value : "[redacted]";
    }

    private static String safeRequestId(String value) {
        if (value == null) return "-";
        return value.matches("[A-Za-z0-9][A-Za-z0-9._:/-]{0,255}") ? value : "[redacted]";
    }
}
