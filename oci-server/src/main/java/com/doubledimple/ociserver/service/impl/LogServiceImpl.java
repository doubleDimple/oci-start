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
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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
    private static final Pattern LOGGER_NAME = Pattern.compile("(?:^|\\s)(?:[\\w$]+\\.)*([\\w$]+)$");
    private static final Pattern TASK_ID = Pattern.compile(
            "(?:^|[^A-Za-z0-9_])taskid\\s*[=:：]\\s*[A-Za-z0-9][A-Za-z0-9_-]*", Pattern.CASE_INSENSITIVE);

    /** Both history and live output include task-tagged OCI execution logs already written to the shared file. */
    private static boolean isBootLogLine(String line) {
        int separator = line.indexOf(" - ");
        if (separator < 0) return false;
        Matcher logger = LOGGER_NAME.matcher(line.substring(0, separator).trim());
        if (!logger.find()) return false;
        String name = logger.group(1);
        if ("OciLogBuilder".equals(name) || "OciErrorBuilder".equals(name)) return true;
        if (!"OracleCloudService".equals(name) && !"CreateInstanceTaskV2".equals(name)
                && !"StartBootInstanceTask".equals(name)) return false;
        // Inspect the message only; another logger mentioning these class names is not a boot event.
        return TASK_ID.matcher(line.substring(separator + 3)).find();
    }

    @Override
    public List<String> getLatestLogLines(int lineCount, boolean isBootLog) {
        String logFilePath = System.getProperty("user.dir") + File.separator + LOG_RELATIVE_PATH;
        File file = new File(logFilePath);
        List<String> logLines = new ArrayList<>();

        if (!file.isFile()) {
            throw new IllegalStateException("无法读取日志文件");
        }

        try (ReversedLinesFileReader reader = new ReversedLinesFileReader(file, StandardCharsets.UTF_8)) {
            String line;
            List<String> currentLogBlock = new ArrayList<>();
            while ((line = reader.readLine()) != null && logLines.size() < lineCount) {
                currentLogBlock.add(0, line);
                if (line.matches("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}.*")) {
                    if (!isBootLog || isBootLogLine(currentLogBlock.get(0))) {
                        logLines.addAll(0, currentLogBlock);
                    }
                    currentLogBlock.clear();
                }
            }
        } catch (Exception e) {
            log.error("读取日志文件失败", e);
            // A partial block list is not a successful read. Both JSON and FTL callers already wrap this failure.
            throw new IllegalStateException("无法读取日志文件");
        }
        return logLines;
    }

    @Override
    public SseEmitter streamLogs(boolean isBootLog) {
        SseEmitter emitter = new SseEmitter(0L);
        AtomicBoolean closed = new AtomicBoolean(false);
        AtomicReference<Tailer> tailerRef = new AtomicReference<>();
        Runnable cleanup = () -> {
            closed.set(true);
            Tailer tailer = tailerRef.getAndSet(null);
            if (tailer != null) tailer.stop();
        };
        Runnable fail = () -> {
            boolean notify = closed.compareAndSet(false, true);
            cleanup.run();
            if (notify) emitter.completeWithError(new IllegalStateException("无法读取实时日志流"));
        };
        // Install lifecycle callbacks before sending or submitting the worker. Each connection owns only its Tailer.
        emitter.onCompletion(cleanup);
        emitter.onTimeout(fail);
        emitter.onError(error -> fail.run());

        TailerListenerAdapter listener = new TailerListenerAdapter() {
            @Override
            public void handle(String line) {
                if (closed.get()) return;
                try {
                    if (!isBootLog || isBootLogLine(line)) {
                        emitter.send(line);
                    }
                } catch (Exception e) {
                    fail.run();
                }
            }

            @Override
            public void handle(Exception ex) {
                fail.run();
            }

            @Override
            public void fileNotFound() {
                // Also covers deletion between the initial existence check and the worker opening the file.
                fail.run();
            }
        };

        try {
            String logFilePath = System.getProperty("user.dir") + File.separator + LOG_RELATIVE_PATH;
            File file = new File(logFilePath);
            if (!file.isFile()) {
                fail.run();
                return emitter;
            }
            // Comment only: no log entry or change to the existing SSE wire format.
            emitter.send(SseEmitter.event().comment("ok"));
            Tailer tailer = new Tailer(file, listener, 1000, true);
            tailerRef.set(tailer);
            // A disconnect may have happened before the Tailer was registered.
            if (closed.get()) {
                cleanup.run();
                return emitter;
            }
            sseLogExecutor.execute(() -> {
                try {
                    if (!closed.get()) tailer.run();
                } finally {
                    // Unexpected worker termination must not leave an apparently connected, inactive stream.
                    if (closed.get()) cleanup.run();
                    else fail.run();
                }
            });
        } catch (Exception e) {
            // Includes initial send, Tailer construction and executor rejection.
            fail.run();
        }

        return emitter;
    }
}
