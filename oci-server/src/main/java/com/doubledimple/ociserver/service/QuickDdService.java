package com.doubledimple.ociserver.service;

import com.doubledimple.ociserver.pojo.request.DDRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

public interface QuickDdService {

    public ApiResponse quickDd(DDRequest request);

    SseEmitter quickDdSse(DDRequest request);
}
