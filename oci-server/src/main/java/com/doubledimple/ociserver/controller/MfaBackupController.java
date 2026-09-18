package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.service.mfa.MfaBackupService;
import com.doubledimple.ociserver.service.mfa.MfaImportCodec;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Authenticated, explicit OTP backup reads and writes. Existing native/FTL routes remain separate. */
@RestController
@RequestMapping(value = "/api/mfa", produces = "application/json")
public class MfaBackupController {
    private static final Set<String> ERRORS = new HashSet<>(Arrays.asList("invalidInput", "invalidSecret", "invalidUri",
            "unsupportedParameters", "invalidImage", "imageTooLarge", "qrNotFound", "qrGenerationFailed", "tooManyEntries",
            "notFound", "conflict", "limitExceeded", "requestFailed", "unauthorized", "forbidden"));
    private final MfaBackupService service;
    private final MfaImportCodec codec;

    public MfaBackupController(MfaBackupService service, MfaImportCodec codec) { this.service = service; this.codec = codec; }

    @ModelAttribute
    public void protect(HttpServletRequest request, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Pragma", "no-cache");
        SystemSettingsApiController.guardSecurityWrite(request);
    }

    @GetMapping("/entries")
    public Map<String, Object> entries() { return success(service.listEntries()); }

    @PostMapping("/codes")
    public Map<String, Object> codes(@RequestBody Map<String, Object> body) {
        return service.codes(ids(body, MfaBackupService.MAX_BATCH));
    }

    @GetMapping("/entries/{id}/material")
    public Map<String, Object> material(@PathVariable String id) { return success(service.material(id(id))); }

    @PostMapping("/preview")
    public Map<String, Object> preview(@RequestParam String mode,
            @RequestParam(required = false) String keyName, @RequestParam(required = false) String issuer,
            @RequestParam(required = false) String secretKey, @RequestParam(required = false) MultipartFile qrCode,
            @RequestParam(required = false) String qrUrl) {
        MfaImportCodec.Preview preview = codec.preview(mode, keyName, issuer, secretKey, qrCode, qrUrl);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("entries", preview.getEntries());
        result.put("partialBatch", preview.isPartialBatch());
        result.put("batchIndex", preview.getBatchIndex());
        result.put("batchSize", preview.getBatchSize());
        return success(result);
    }

    @PostMapping("/import")
    public Map<String, Object> importEntries(@RequestBody Map<String, Object> body) {
        Object raw = body == null ? null : body.get("entries");
        if (!(raw instanceof List)) throw invalid();
        List<?> values = (List<?>) raw;
        if (values.isEmpty() || values.size() > MfaBackupService.MAX_BATCH) throw invalid();
        List<MfaImportCodec.Entry> entries = new ArrayList<>();
        for (Object value : values) {
            if (!(value instanceof Map)) throw invalid();
            Map<?, ?> fields = (Map<?, ?>) value;
            entries.add(codec.normalizeEntry(string(fields.get("keyName")), string(fields.get("issuer")), string(fields.get("secretKey"))));
        }
        return success(service.importEntries(entries));
    }

    @PostMapping("/entries/{id}/delete")
    public Map<String, Object> delete(@PathVariable String id, @RequestBody Map<String, Object> body) {
        Long requested = id(id);
        service.delete(requested, string(body == null ? null : body.get("revision")));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", requested.toString());
        return success(result);
    }

    @PostMapping("/export")
    public Map<String, Object> export(@RequestBody Map<String, Object> body) {
        return success(service.exportEntries(ids(body, MfaBackupService.MAX_ENTRIES)));
    }

    @ExceptionHandler(MfaBackupService.MfaFailure.class)
    public ResponseEntity<Map<String, Object>> failed(MfaBackupService.MfaFailure failure) {
        return error(failure.getErrorKey(), failure.isWriteAttempted());
    }

    @ExceptionHandler(MfaImportCodec.MfaCodecException.class)
    public ResponseEntity<Map<String, Object>> invalidCodec(MfaImportCodec.MfaCodecException failure) {
        String key = failure.getErrorKey();
        if (key != null && key.startsWith("mfa.")) key = key.substring(4);
        return error(key, false);
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<Map<String, Object>> invalidBinding(Exception ignored) { return error("invalidInput", false); }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<Map<String, Object>> invalidUpload(Exception ignored) { return error("imageTooLarge", false); }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> unexpected(Exception failure, HttpServletRequest request) {
        if (failure instanceof ResponseStatusException) {
            int status = ((ResponseStatusException) failure).getStatus().value();
            if (status == 403) return error("forbidden", false);
            if (status == 401) return error("unauthorized", false);
        }
        String path = request.getServletPath();
        boolean write = "POST".equals(request.getMethod()) && (path.endsWith("/import") || path.endsWith("/delete"));
        return error("requestFailed", write);
    }

    private static List<Long> ids(Map<String, Object> body, int limit) {
        Object raw = body == null ? null : body.get("ids");
        if (!(raw instanceof List)) throw invalid();
        List<?> values = (List<?>) raw;
        if (values.isEmpty() || values.size() > limit) throw invalid();
        List<Long> result = new ArrayList<>();
        Set<Long> seen = new HashSet<>();
        for (Object value : values) {
            if (!(value instanceof String)) throw invalid();
            Long id = id((String) value);
            if (!seen.add(id)) throw invalid();
            result.add(id);
        }
        return result;
    }

    private static Long id(String value) {
        if (value == null || !value.matches("[1-9][0-9]{0,18}")) throw invalid();
        try { return Long.valueOf(value); }
        catch (NumberFormatException failure) { throw invalid(); }
    }
    private static String string(Object value) {
        if (value == null) return null;
        if (!(value instanceof String)) throw invalid();
        return (String) value;
    }
    private static MfaBackupService.MfaFailure invalid() { return new MfaBackupService.MfaFailure("invalidInput", false); }
    private static Map<String, Object> success(Object data) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("success", true); result.put("data", data);
        return result;
    }
    private static ResponseEntity<Map<String, Object>> error(String candidate, boolean attempted) {
        String key = ERRORS.contains(candidate) ? candidate : "requestFailed";
        int status = "notFound".equals(key) ? 404 : "conflict".equals(key) ? 409
                : "unauthorized".equals(key) ? 401 : "forbidden".equals(key) ? 403 : "requestFailed".equals(key) ? 500 : 400;
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("success", false); body.put("errorKey", key); body.put("writeAttempted", attempted);
        return ResponseEntity.status(status).header("Cache-Control", "no-store").body(body);
    }
}
