package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.Memo;

import java.util.List;

public interface MemoService {
    List<Memo> getAllMemos();
    Memo getMemoById(Long id);
    Memo createMemo(Memo memo);
    Memo updateMemo(Long id, Memo memo);
    void deleteMemo(Long id);
    Memo updateMemo(Long id, Memo memo, String expectedRevision);
    void deleteMemo(Long id, String expectedRevision);
    String getRevision(Memo memo);

    /** Fixed, content-free failures raised before a mutation is applied. */
    class MemoFailure extends RuntimeException {
        private final String errorKey;

        public MemoFailure(String errorKey) {
            super(errorKey);
            this.errorKey = errorKey;
        }

        public String getErrorKey() { return errorKey; }
    }
}
