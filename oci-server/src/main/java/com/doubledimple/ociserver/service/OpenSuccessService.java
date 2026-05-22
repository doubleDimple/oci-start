package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;

public interface OpenSuccessService {

    void doSuccess(User user, OracleInstanceDetail instanceData, SimpleAuthenticationDetailsProvider provider);

    /**
     * 确保实例状态已更新为成功
     *
     * @param user 用户信息
     * @param instanceData 实例详情
     * @return 是否需要执行更新操作
     */
    boolean ensureStatusUpdated(User user, OracleInstanceDetail instanceData);
}
