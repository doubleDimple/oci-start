package com.doubledimple.ociserver.config.event;

import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.domain.dto.User;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import org.springframework.context.ApplicationEvent;

/**
 * @version 1.0.0
 * @ClassName OracleInstanceSuccessEvent
 * @Description TODO
 * @Author renyx
 * @Date 2026-02-04 16:46
 */
public class OracleInstanceSuccessEvent extends ApplicationEvent {
    private final User user;
    private final OracleInstanceDetail detail;
    private final SimpleAuthenticationDetailsProvider provider;

    public OracleInstanceSuccessEvent(Object source, User user, OracleInstanceDetail detail, SimpleAuthenticationDetailsProvider provider) {
        super(source);
        this.user = user;
        this.detail = detail;
        this.provider = provider;
    }

    public User getUser() {
        return user;
    }

    public OracleInstanceDetail getDetail() {
        return detail;
    }

    public SimpleAuthenticationDetailsProvider getProvider() {
        return provider;
    }
}
