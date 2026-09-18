package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.config.datamigration.DatabaseExportService;
import com.doubledimple.ociserver.config.datamigration.DatabaseImportService;
import com.doubledimple.ociserver.config.datamigration.MigrationImportException;
import com.doubledimple.ociserver.config.datamigration.MigrationImportResult;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

@Controller
@RequestMapping("/migration")
@Slf4j
public class MigrationController extends BaseController {

    private static final long MAX_FILE_BYTES = 10L * 1024 * 1024;

    @Resource
    private DatabaseExportService databaseExportService;
    @Resource
    private DatabaseImportService databaseImportService;

    /** Legacy plain backup endpoint. The Vue page only exposes encrypted backups. */
    @GetMapping("/export")
    public ResponseEntity<byte[]> exportDatabase(HttpServletRequest request) {
        SystemSettingsApiController.guardSecurityWrite(request);
        try {
            ByteArrayOutputStream output = databaseExportService.exportDatabaseToStream();
            if (output.size() > MAX_FILE_BYTES) throw new IllegalStateException("migration.limitExceeded");
            return ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "no-store")
                    .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"oci-start_backup_" + System.currentTimeMillis() + ".sql\"")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM).body(output.toByteArray());
        } catch (Exception exception) {
            // SQL exception messages and causes can contain the data being exported.
            log.warn("数据库备份导出未完成");
            return ResponseEntity.status(500).header(HttpHeaders.CACHE_CONTROL, "no-store")
                    .body("备份导出失败，请检查服务状态与备份大小".getBytes(StandardCharsets.UTF_8));
        }
    }

    @GetMapping("/exportEncrypted")
    public void exportEncrypted(HttpServletRequest request, HttpServletResponse response) {
        response.setHeader(HttpHeaders.CACHE_CONTROL, "no-store");
        SystemSettingsApiController.guardSecurityWrite(request);
        try {
            databaseExportService.exportEncryptedBackup(response);
        } catch (Exception exception) {
            log.warn("加密备份导出未完成");
            if (response.isCommitted()) return;
            response.reset();
            response.setHeader(HttpHeaders.CACHE_CONTROL, "no-store");
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.setContentType("text/plain;charset=UTF-8");
            try {
                response.getOutputStream().write("加密备份导出失败，请检查服务状态与备份大小".getBytes(StandardCharsets.UTF_8));
            } catch (Exception ignored) {
                // A disconnected client cannot receive a failure receipt.
            }
        }
    }

    /** Preserve the old text receipt without leaving uploaded SQL in a temp file. */
    @PostMapping("/import")
    public ResponseEntity<String> importDatabase(@RequestParam("file") MultipartFile file, HttpServletRequest request) {
        SystemSettingsApiController.guardSecurityWrite(request);
        try {
            databaseImportService.importFromSqlText(readBackup(file));
            return legacyReceipt(true);
        } catch (Exception exception) {
            log.warn("旧版 SQL 导入未完成");
            return legacyReceipt(false);
        }
    }

    @PostMapping("/importEncrypted")
    public ResponseEntity<String> importEncrypted(@RequestParam("file") MultipartFile file,
            @RequestParam(value = "masterKey", required = false) String masterKey, HttpServletRequest request) {
        SystemSettingsApiController.guardSecurityWrite(request);
        try {
            databaseImportService.importAutoWithResult(readBackup(file), masterKey);
            return legacyReceipt(true);
        } catch (Exception exception) {
            log.warn("旧版加密备份导入未完成");
            return legacyReceipt(false);
        }
    }

    /** An explicit committed receipt for Vue; never fall back by resubmitting to the legacy endpoint. */
    @PostMapping("/importEncryptedResult")
    public ResponseEntity<Map<String, Object>> importEncryptedResult(@RequestParam("file") MultipartFile file,
            @RequestParam(value = "masterKey", required = false) String masterKey, HttpServletRequest request) {
        SystemSettingsApiController.guardSecurityWrite(request);
        final String content;
        try {
            content = readBackup(file);
        } catch (MigrationImportException exception) {
            return importFailure(exception.getCode(), "rejected");
        } catch (Exception exception) {
            return importFailure("migration.invalidFile", "rejected");
        }
        try {
            MigrationImportResult result = databaseImportService.importEncryptedStrict(content, masterKey);
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("success", true);
            body.put("formatVersion", result.getFormatVersion());
            body.put("importedRows", result.getImportedRows());
            body.put("preservedRows", result.getPreservedRows());
            body.put("tables", result.getTables());
            return ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "no-store").body(body);
        } catch (MigrationImportException exception) {
            log.warn("迁移导入未完成: {} / {}", exception.getCode(), exception.getOutcome());
            return importFailure(exception.getCode(), exception.getOutcome());
        } catch (Exception exception) {
            // Without a transaction completion receipt, rollback must not be assumed.
            log.warn("迁移导入未收到确定的事务结果");
            return importFailure("migration.importFailed", "unknown");
        }
    }

    private String readBackup(MultipartFile file) throws Exception {
        if (file == null || file.isEmpty()) throw new MigrationImportException("migration.invalidFile", "rejected");
        if (file.getSize() > MAX_FILE_BYTES) throw new MigrationImportException("migration.limitExceeded", "rejected");
        byte[] bytes = file.getBytes();
        if (bytes.length == 0 || bytes.length > MAX_FILE_BYTES) throw new MigrationImportException("migration.limitExceeded", "rejected");
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
    }

    private ResponseEntity<String> legacyReceipt(boolean success) {
        return ResponseEntity.status(success ? 200 : 400).header(HttpHeaders.CACHE_CONTROL, "no-store")
                .body(success ? "导入成功" : "导入未完成，请核对备份、数据兼容性及服务器状态；不要直接重复导入");
    }

    private ResponseEntity<Map<String, Object>> importFailure(String code, String outcome) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("success", false);
        body.put("error", code);
        body.put("outcome", outcome);
        return ResponseEntity.status("unknown".equals(outcome) ? 500 : 400)
                .header(HttpHeaders.CACHE_CONTROL, "no-store").body(body);
    }
}
