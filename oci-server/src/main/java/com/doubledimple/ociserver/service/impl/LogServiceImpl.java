package com.doubledimple.ociserver.service.impl;

import com.doubledimple.ociserver.service.LogService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.io.input.ReversedLinesFileReader;
import org.apache.commons.io.input.Tailer;
import org.apache.commons.io.input.TailerListenerAdapter;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;

/**
 * @author doubleDimple
 * @date 2024:10:25日 21:54
 */
@Service
@Slf4j
public class LogServiceImpl implements LogService {

    @Autowired
    @Qualifier("sseLogExecutor")
    private Executor sseLogExecutor;

    private static final String LOG_RELATIVE_PATH = "logs/application.log"; // 日志相对路径

    @Override
    public List<String> getLatestLogLines(int lineCount, boolean isBootLog) {
        String logFilePath = System.getProperty("user.dir") + File.separator + LOG_RELATIVE_PATH;
        File file = new File(logFilePath);
        List<String> logLines = new ArrayList<>();

        if (!file.exists()) {
            log.warn("日志文件不存在: {}", logFilePath);
            return logLines;
        }

        try (ReversedLinesFileReader reader = new ReversedLinesFileReader(file, StandardCharsets.UTF_8)) {
            String line;
            List<String> currentLogBlock = new ArrayList<>();
            while ((line = reader.readLine()) != null && logLines.size() < lineCount) {
                currentLogBlock.add(0, line);
                if (line.matches("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}.*")) {
                    if (!isBootLog || currentLogBlock.get(0).contains("OciLogBuilder")) {
                        logLines.addAll(0, currentLogBlock);
                    }
                    currentLogBlock.clear();
                }
            }
        } catch (Exception e) {
            log.error("读取日志文件失败", e);
        }
        return logLines;
    }

    @Override
    public SseEmitter streamLogs(boolean isBootLog) {
        SseEmitter emitter = new SseEmitter(0L);
        String logFilePath = System.getProperty("user.dir") + File.separator + LOG_RELATIVE_PATH;
        File file = new File(logFilePath);

        if (!file.exists()) {
            emitter.complete();
            return emitter;
        }

        // 立即发一条 SSE 注释事件(": ok\n"),强制 servlet 容器 flush 响应头，
        // 让浏览器 EventSource.onopen 立即触发，避免状态长期卡在 "connecting..."
        // SSE 注释不会派发到 onmessage，不影响业务日志展示
        try {
            emitter.send(SseEmitter.event().comment("ok"));
        } catch (Exception e) {
            log.debug("SSE 初始 flush 失败: {}", e.getMessage());
        }

        final Tailer[] tailerRef = new Tailer[1];

        TailerListenerAdapter listener = new TailerListenerAdapter() {
            @Override
            public void handle(String line) {
                try {
                    if (!isBootLog || line.contains("OciLogBuilder") || line.contains("OciErrorBuilder")) {
                        emitter.send(line);
                    }
                } catch (Exception e) {
                    if (tailerRef[0] != null) {
                        tailerRef[0].stop();
                    }
                }
            }

            @Override
            public void handle(Exception ex) {
                log.debug("日志监听已停止: {}", ex.getMessage());
            }
        };

        tailerRef[0] = new Tailer(file, listener, 1000, true);
        CompletableFuture.runAsync(tailerRef[0],sseLogExecutor);

        Runnable cleanup = () -> {
            if (tailerRef[0] != null) {
                tailerRef[0].stop();
            }
        };
        emitter.onCompletion(cleanup);
        emitter.onTimeout(cleanup);
        emitter.onError(e -> cleanup.run());

        return emitter;
    }
}