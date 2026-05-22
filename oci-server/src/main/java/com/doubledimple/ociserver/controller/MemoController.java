package com.doubledimple.ociserver.controller;

import com.doubledimple.dao.entity.Memo;
import com.doubledimple.ociserver.service.MemoService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import java.util.List;

/**
 * @author doubleDimple
 * @date 2024:11:24日 12:43
 */
@RestController
@RequestMapping("/api/memos")
public class MemoController  extends BaseController{

    @Resource
    private MemoService memoService;

    @GetMapping
    public ResponseEntity<List<Memo>> getAllMemos() {
        return ResponseEntity.ok(memoService.getAllMemos());
    }

    @GetMapping("/{id}")
    public ResponseEntity<Memo> getMemoById(@PathVariable Long id) {
        return ResponseEntity.ok(memoService.getMemoById(id));
    }

    @PostMapping
    public ResponseEntity<Memo> createMemo(@RequestBody Memo memo) {
        return ResponseEntity.ok(memoService.createMemo(memo));
    }

    @PutMapping("/{id}")
    public ResponseEntity<Memo> updateMemo(@PathVariable Long id, @RequestBody Memo memo) {
        return ResponseEntity.ok(memoService.updateMemo(id, memo));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteMemo(@PathVariable Long id) {
        memoService.deleteMemo(id);
        return ResponseEntity.ok().build();
    }
}
