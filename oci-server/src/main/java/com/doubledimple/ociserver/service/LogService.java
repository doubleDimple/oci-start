package com.doubledimple.ociserver.service;

import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.List;

public interface LogService {

    public List<String> getLatestLogLines(int lineCount,boolean isBootLog);

    SseEmitter streamLogs(boolean isBootLog);
}
