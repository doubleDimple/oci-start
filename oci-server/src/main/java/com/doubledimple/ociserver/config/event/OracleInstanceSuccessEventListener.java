package com.doubledimple.ociserver.config.event;

import com.doubledimple.ociserver.service.OpenSuccessService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;

/**
 * @version 1.0.0
 * @ClassName OracleInstanceSuccessEventListener
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-04 16:49
 */
@Component
@Slf4j
public class OracleInstanceSuccessEventListener {

    @Resource
    private OpenSuccessService openSuccessService;


    @Async("eventExecutor")
    @EventListener
    public void handleInstanceCreation(OracleInstanceSuccessEvent event) {
        log.info("监听到实例创建成功，开始执行后续逻辑...");
        openSuccessService.doSuccess(event.getUser(), event.getDetail(), event.getProvider());
    }
}
