package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Memo;
import com.doubledimple.ociserver.service.MemoService;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.server.ResponseStatusException;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * @author doubleDimple
 * @date 2024:11:24日 12:43
 */
@RestController
@RequestMapping("/api/memos")
public class MemoController  extends BaseController{

    @Resource
    private MemoService memoService;

    @ModelAttribute
    public void protectMemoAccess(HttpServletRequest request, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        SystemSettingsApiController.guardSecurityWrite(request);
    }

    @GetMapping
    public ResponseEntity<List<Memo>> getAllMemos() {
        return ResponseEntity.ok(memoService.getAllMemos());
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> getMemoById(@PathVariable Long id, @RequestParam(defaultValue = "false") boolean guarded) {
        Memo memo = memoService.getMemoById(id);
        if (!guarded) return ResponseEntity.ok(memo);
        Map<String, Object> result = new HashMap<>();
        result.put("memo", memo);
        result.put("revision", memoService.getRevision(memo));
        return ResponseEntity.ok(result);
    }

    @PostMapping
    public ResponseEntity<Memo> createMemo(@RequestBody Memo memo) {
        return ResponseEntity.ok(memoService.createMemo(memo));
    }

    @PutMapping("/{id}")
    public ResponseEntity<Memo> updateMemo(@PathVariable Long id, @RequestBody Memo memo,
                                          @RequestHeader(value = "If-Match", required = false) String revision) {
        return ResponseEntity.ok(memoService.updateMemo(id, memo, revision));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteMemo(@PathVariable Long id,
                                          @RequestHeader(value = "If-Match", required = false) String revision) {
        memoService.deleteMemo(id, revision);
        return ResponseEntity.ok().build();
    }

    @ExceptionHandler(MemoService.MemoFailure.class)
    public ResponseEntity<Map<String, String>> memoFailure(MemoService.MemoFailure failure) {
        String key = failure.getErrorKey();
        int status = "notFound".equals(key) ? 404 : "conflict".equals(key) ? 409 : 400;
        return ResponseEntity.status(status).body(errorBody(key));
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<Map<String, String>> invalidRequest(Exception ignored) {
        return ResponseEntity.badRequest().body(errorBody("invalidInput"));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> requestFailure(Exception cause) {
        // Do not include titles, contents, database values or nested exception text in public errors/logs.
        int status = cause instanceof ResponseStatusException ? ((ResponseStatusException) cause).getStatus().value() : 500;
        return ResponseEntity.status(status).body(errorBody("requestFailed"));
    }

    private static Map<String, String> errorBody(String key) {
        Map<String, String> body = new HashMap<>();
        body.put("errorKey", key);
        return body;
    }
}
