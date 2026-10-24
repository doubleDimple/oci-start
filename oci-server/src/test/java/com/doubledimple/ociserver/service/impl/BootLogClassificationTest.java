package com.doubledimple.ociserver.service.impl;

import org.apache.commons.io.input.Tailer;
import org.apache.commons.io.input.TailerListener;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

class BootLogClassificationTest {
    @TempDir Path directory;
    private String previousDirectory;
    private LogServiceImpl service;
    private Path logFile;

    private static final String CAPACITY = line("c.d.o.s.oracle.OracleCloudService", "[TaskId=353] 无容量，跳过创建");
    private static final String RETRY = line("com.doubledimple.ociserver.service.oracle.OracleCloudService",
            "[TaskId=353] 未完成开机，将在60秒后重试");
    private static final String SCHEDULED = line("c.d.o.c.task.CreateInstanceTaskV2",
            "抢机失败 - TaskId: 1792840135189a6e214ab-1111-2222-3333-44b1c9aacdef");
    private static final String MANUAL = line("c.d.o.c.task.StartBootInstanceTask", "[TaskId=9223372036854775807] 手动开机失败");
    private static final String CURRENT_BUILDER = line("c.d.ociserver.config.OciLogBuilder", "旧版开机进度");
    private static final String OLD_BUILDER = line("c.d.ociserver.config.OciErrorBuilder", "旧版开机异常");
    private static final String COLORED = "2026-10-24 19:16:12 [oci-api-1] [NONE] \u001b[33mWARN \u001b[0;39m"
            + " c.d.o.s.oracle.OracleCloudService - [TaskId=353] 无容量";
    private static final List<String> INCLUDED = Arrays.asList(
            CURRENT_BUILDER, OLD_BUILDER, CAPACITY, RETRY, SCHEDULED, MANUAL, COLORED);
    private static final List<String> EXCLUDED = Arrays.asList(
            line("c.d.o.s.oracle.OracleCloudService", "普通 OCI 资源查询"),
            line("c.d.o.s.otherCloud.OtherBootService", "[TaskId=353] 其他云开机"),
            line("c.d.o.s.impl.TenantServiceImpl", "[TaskId=353] OracleCloudService - 文本提及类名"),
            line("c.d.o.s.impl.TenantServiceImpl", "OciLogBuilder - 正文中的类名不是日志来源"),
            line("c.d.o.c.task.CreateInstanceTaskV2", "当前没有到期任务"));

    @BeforeEach
    void setup() throws Exception {
        previousDirectory = System.getProperty("user.dir");
        System.setProperty("user.dir", directory.toString());
        logFile = directory.resolve("logs/application.log");
        Files.createDirectories(logFile.getParent());
        Files.write(logFile, new byte[0]);
        service = new LogServiceImpl();
    }

    @AfterEach
    void restoreDirectory() {
        if (previousDirectory == null) System.clearProperty("user.dir");
        else System.setProperty("user.dir", previousDirectory);
    }

    @Test
    void historyRecoversAlreadyWrittenCapacityAndSchedulerLogsWithoutUnrelatedCloudLogs() throws Exception {
        List<String> all = new ArrayList<>(INCLUDED);
        all.addAll(EXCLUDED);
        Files.write(logFile, all, StandardCharsets.UTF_8);

        assertEquals(INCLUDED, service.getLatestLogLines(100, true));
        assertEquals(all, service.getLatestLogLines(100, false));
    }

    @Test
    void acceptedHistoryRetainsItsExceptionContinuationLines() throws Exception {
        String frame = "\tat example.BootAttempt.execute(BootAttempt.java:42)";
        Files.write(logFile, Arrays.asList(CAPACITY, frame, EXCLUDED.get(0)), StandardCharsets.UTF_8);

        assertEquals(Arrays.asList(CAPACITY, frame), service.getLatestLogLines(100, true));
    }

    @Test
    void liveTailerUsesTheSameClassificationAsHistoryWithoutStartingAThreadOrNetwork() throws Exception {
        assertEquals(INCLUDED, liveOutput(true));
    }

    @Test
    void systemLogStreamContinuesToIncludeUnrelatedEntries() throws Exception {
        List<String> all = new ArrayList<>(INCLUDED);
        all.addAll(EXCLUDED);
        assertEquals(all, liveOutput(false));
    }

    private List<String> liveOutput(boolean bootOnly) throws Exception {
        AtomicReference<Runnable> worker = new AtomicReference<>();
        ReflectionTestUtils.setField(service, "sseLogExecutor", (Executor) worker::set);
        SseEmitter emitter = service.streamLogs(bootOnly);
        assertNotNull(worker.get());
        // Exercise the real listener attached to the queued Tailer, without polling a live filesystem.
        Tailer tailer = null;
        for (Field field : worker.get().getClass().getDeclaredFields()) {
            if (Tailer.class.isAssignableFrom(field.getType())) {
                field.setAccessible(true);
                tailer = (Tailer) field.get(worker.get());
            }
        }
        assertNotNull(tailer);
        TailerListener listener = (TailerListener) ReflectionTestUtils.getField(tailer, "listener");
        assertNotNull(listener);
        INCLUDED.forEach(listener::handle);
        EXCLUDED.forEach(listener::handle);
        List<String> sentLines = new ArrayList<>();
        Set<?> pending = (Set<?>) ReflectionTestUtils.getField(emitter, "earlySendAttempts");
        assertNotNull(pending);
        for (Object entry : pending) {
            Object data = ReflectionTestUtils.invokeMethod(entry, "getData");
            if (data instanceof String && ((String) data).startsWith("2026-")) {
                sentLines.add((String) data);
            }
        }
        tailer.stop();
        emitter.complete();
        return sentLines;
    }

    private static String line(String logger, String message) {
        return "2026-10-24 19:15:07 [oci-api-1] [NONE] INFO " + logger + " - " + message;
    }
}
