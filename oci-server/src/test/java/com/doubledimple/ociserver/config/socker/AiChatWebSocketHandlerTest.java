package com.doubledimple.ociserver.config.socker;

import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ociai.utils.OciAiChatUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.oracle.bmc.model.BmcException;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Exercises the real handler without Spring, HTTP, OCI clients or network sockets. */
class AiChatWebSocketHandlerTest {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final long WAIT_SECONDS = 5;

    @Test
    void closingOneSocketDoesNotDisposeSharedTenantClientOrInterruptAnotherStream() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket first = f.connect("first");
            RecordingSocket second = f.connect("second");
            CountDownLatch entered = new CountDownLatch(1);
            CountDownLatch resume = f.releaseOnClose();
            doAnswer(call -> {
                entered.countDown();
                await(resume, "release second socket's stream");
                Consumer<String> consumer = call.getArgument(3);
                consumer.accept("still connected");
                return null;
            }).when(f.ai).chatWithStreamOrThrow(any(Tenant.class), anyString(), anyString(), any());

            f.chat(second, "question", true);
            await(entered, "second stream starts before first socket closes");
            first.session.close(CloseStatus.NORMAL);
            f.handler.afterConnectionClosed(first.session, CloseStatus.NORMAL);
            assertEquals(1, f.handler.getActiveSessionCount());
            verify(f.ai, never()).cleanupClient(any(Tenant.class));
            assertTrue(f.scheduler.periodicFutures.get(0).isCancelled());
            assertFalse(f.scheduler.periodicFutures.get(1).isCancelled());
            resume.countDown();
            f.drain();

            assertTrue(second.open.get());
            assertEquals("still connected", second.only("chat").get("message"));
            assertEquals("success", second.only("chat_end").get("status"));
            assertEquals(2, f.history(second).size());
            verify(f.ai, never()).cleanupClient(any(Tenant.class));
        }
    }

    @Test
    void requestedSessionCleanupClosesOnlyItsSocketAndDoesNotDisposeTenantClient() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket first = f.connect("first");
            RecordingSocket second = f.connect("second");
            f.receive(first, "close_session", "reason", "user_requested");
            assertEquals("success", first.only("close_session").get("status"));
            f.scheduler.runDelayedClose().get(WAIT_SECONDS, TimeUnit.SECONDS);

            assertFalse(first.open.get());
            assertTrue(second.open.get());
            assertEquals(1, f.handler.getActiveSessionCount());
            assertNull(f.history(first));
            verify(f.ai, never()).cleanupClient(any(Tenant.class));
            f.receive(second, "ping");
            assertEquals("pong", second.only("pong").get("message"));
        }
    }

    @Test
    void handlerDestroyClosesSocketsAndTimersButLeavesGlobalClientOwnershipToManager() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket first = f.connect("first");
            RecordingSocket second = f.connect("second");
            f.handler.destroy();

            assertFalse(first.open.get());
            assertFalse(second.open.get());
            assertEquals(0, f.handler.getActiveSessionCount());
            assertNull(f.history(first));
            assertTrue(f.scheduler.periodicFutures.stream().allMatch(Future::isCancelled));
            verify(f.ai, never()).cleanupClient(any(Tenant.class));
        }
    }

    @Test
    void heartbeatAndPongCannotOverlapAnInFlightChunkWrite() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket socket = f.connect("serialized");
            socket.blockedType = "chat";
            socket.writeEntered = new CountDownLatch(1);
            socket.releaseWrite = f.releaseOnClose();
            f.reply("answer");
            f.chat(socket, "question", true);
            await(socket.writeEntered, "chunk enters native websocket writer");

            AtomicReference<Thread> heartbeatThread = new AtomicReference<>();
            AtomicReference<Thread> pongThread = new AtomicReference<>();
            CountDownLatch contendersStarted = new CountDownLatch(2);
            Future<?> heartbeat = f.scheduler.submit(() -> {
                heartbeatThread.set(Thread.currentThread());
                contendersStarted.countDown();
                f.scheduler.heartbeats.get(0).run();
            });
            Future<?> pong = f.callers.submit(() -> {
                pongThread.set(Thread.currentThread());
                contendersStarted.countDown();
                try { f.receive(socket, "ping"); }
                catch (Exception e) { throw new IllegalStateException(e); }
            });
            await(contendersStarted, "heartbeat and ping both dispatched");
            awaitCondition(() -> heartbeatThread.get().getState() == Thread.State.BLOCKED
                    && pongThread.get().getState() == Thread.State.BLOCKED,
                    "both writers must wait for the socket's write monitor");
            assertEquals(1, socket.maxConcurrentWrites.get());
            assertEquals(0, socket.events("heartbeat").size());
            assertEquals(0, socket.events("pong").size());

            socket.releaseWrite.countDown();
            heartbeat.get(WAIT_SECONDS, TimeUnit.SECONDS);
            pong.get(WAIT_SECONDS, TimeUnit.SECONDS);
            f.drain();
            assertEquals(1, socket.maxConcurrentWrites.get());
            assertEquals(1, socket.events("heartbeat").size());
            assertEquals(1, socket.events("pong").size());
            assertEquals(1, socket.events("chat_end").size());
            assertTrue(socket.open.get());
        }
    }

    @Test
    void ioFailureWritingChunkClosesSocketWithoutSuccessOrHistory() throws Exception {
        assertFailedSend("chat", false);
    }

    @Test
    void runtimeFailureWritingChunkClosesSocketWithoutSuccessOrHistory() throws Exception {
        assertFailedSend("chat", true);
    }

    @Test
    void failureWritingTerminalReceiptDoesNotCommitAlreadyDeliveredReplyToHistory() throws Exception {
        assertFailedSend("chat_end", false);
    }

    private void assertFailedSend(String type, boolean runtimeFailure) throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket socket = f.connect("failed-write");
            socket.failedType = type;
            socket.runtimeFailure = runtimeFailure;
            f.reply("answer");
            f.chat(socket, "question", true);
            f.drain();

            assertFalse(socket.open.get());
            assertEquals(1, socket.closeCount.get());
            assertEquals(CloseStatus.SERVER_ERROR, socket.closeStatus.get());
            assertTrue(socket.events("chat_end").isEmpty());
            assertTrue(f.history(socket).isEmpty());
            assertEquals("chat_end".equals(type) ? 1 : 0, socket.events("chat").size());
            verify(f.ai, never()).cleanupClient(any(Tenant.class));
        }
    }

    @Test
    void strictStreamFailureAfterPartialTextEmitsErrorAndDoesNotCommitEitherMessage() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket socket = f.connect("strict-error");
            doAnswer(call -> {
                Consumer<String> consumer = call.getArgument(3);
                consumer.accept("partial");
                throw new IllegalStateException("fixture upstream stream failed");
            }).when(f.ai).chatWithStreamOrThrow(any(Tenant.class), anyString(), anyString(), any());
            f.chat(socket, "question", true);
            f.drain();

            assertEquals("partial", socket.only("chat").get("message"));
            assertEquals("error", socket.only("error").get("status"));
            assertEquals("AI 回复失败，请检查模型服务后重试", socket.only("error").get("message"));
            assertFalse(((String) socket.only("error").get("message")).contains("429"));
            assertTrue(socket.events("chat_end").isEmpty());
            assertTrue(f.history(socket).isEmpty());
        }
    }

    @Test
    void directOci429EmitsSafeThrottleReceiptWithoutRetrySuccessOrHistory() throws Exception {
        assertThrottledReceipt(false);
    }

    @Test
    void wrappedOci429EmitsSafeThrottleReceiptWithoutRetrySuccessOrHistory() throws Exception {
        assertThrottledReceipt(true);
    }

    private void assertThrottledReceipt(boolean wrapped) throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket socket = f.connect(wrapped ? "wrapped-throttle" : "direct-throttle");
            BmcException throttle = new BmcException(429, "TooManyRequests",
                    "fixture raw upstream tenant=ocid1.tenancy.oc1..private-fixture", "fixture-request-id");
            Throwable failure = wrapped
                    ? new IllegalStateException("fixture outer error", new RuntimeException(throttle)) : throttle;
            doThrow(failure).when(f.ai).chatWithStreamOrThrow(any(Tenant.class), anyString(), anyString(), any());
            f.chat(socket, "question", true);
            f.drain();

            Map<String, Object> error = socket.only("error");
            assertEquals("error", error.get("status"));
            String message = (String) error.get("message");
            assertTrue(message.contains("429"));
            assertTrue(message.contains("服务限额"));
            assertFalse(message.contains("ocid1."));
            assertFalse(message.contains("fixture raw upstream"));
            assertFalse(message.contains("fixture-request-id"));
            assertTrue(socket.events("chat").isEmpty());
            assertTrue(socket.events("chat_end").isEmpty());
            assertTrue(f.history(socket).isEmpty());
            verify(f.ai, times(1)).chatWithStreamOrThrow(any(Tenant.class), eq("question"), eq("fixture-model"), any());
            verify(f.ai, never()).chatWithHistoryStreamOrThrow(any(Tenant.class), anyList(), anyString(), any(), any());
        }
    }

    @Test
    void emptyStreamEmitsErrorInsteadOfSuccessAndDoesNotCommitHistory() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket socket = f.connect("empty");
            // A successful return from the strict API without any chunks is not a reply.
            f.chat(socket, "question", true);
            f.drain();

            assertEquals("error", socket.only("error").get("status"));
            assertTrue(socket.events("chat").isEmpty());
            assertTrue(socket.events("chat_end").isEmpty());
            assertTrue(f.history(socket).isEmpty());
        }
    }

    @Test
    void successfulSecondRoundIncludesCurrentQuestionAndCommitsOnlyAfterTerminalReceipt() throws Exception {
        try (Fixture f = new Fixture()) {
            RecordingSocket socket = f.connect("history");
            f.reply("first answer");
            f.chat(socket, "first question", true);
            f.drain();
            assertEquals(2, f.history(socket).size());
            AtomicReference<List<Map<String, String>>> requestedHistory = new AtomicReference<>();
            CountDownLatch secondStarted = new CountDownLatch(1);
            CountDownLatch resume = f.releaseOnClose();
            doAnswer(call -> {
                List<Map<String, String>> request = call.getArgument(1);
                requestedHistory.set(new ArrayList<>(request));
                secondStarted.countDown();
                await(resume, "release second history reply");
                Consumer<String> consumer = call.getArgument(3);
                consumer.accept("second ");
                consumer.accept("answer");
                return null;
            }).when(f.ai).chatWithHistoryStreamOrThrow(any(Tenant.class), anyList(), anyString(), any(), isNull());

            f.chat(socket, "second question", true);
            await(secondStarted, "history stream begins");
            List<Map<String, String>> request = requestedHistory.get();
            assertEquals(3, request.size());
            assertEquals("first question", request.get(0).get("content"));
            assertEquals("first answer", request.get(1).get("content"));
            assertEquals("user", request.get(2).get("role"));
            assertEquals("second question", request.get(2).get("content"));
            assertEquals(2, f.history(socket).size(), "in-flight question is not committed");
            resume.countDown();
            f.drain();

            assertEquals(2, socket.events("chat_end").size());
            assertTrue(socket.events("error").isEmpty());
            List<Map<String, String>> history = f.history(socket);
            assertEquals(4, history.size());
            assertEquals("second question", history.get(2).get("content"));
            assertEquals("assistant", history.get(3).get("role"));
            assertEquals("second answer", history.get(3).get("content"));
            verify(f.ai, times(1)).chatWithStreamOrThrow(any(Tenant.class), eq("first question"), eq("fixture-model"), any());
        }
    }

    private static void await(CountDownLatch latch, String reason) throws InterruptedException {
        assertTrue(latch.await(WAIT_SECONDS, TimeUnit.SECONDS), reason);
    }

    private static void awaitCondition(BooleanSupplier condition, String reason) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(WAIT_SECONDS);
        while (!condition.getAsBoolean() && System.nanoTime() < deadline) Thread.sleep(5);
        assertTrue(condition.getAsBoolean(), reason);
    }

    private static ThreadFactory threads(String prefix) {
        AtomicInteger index = new AtomicInteger();
        return action -> {
            Thread thread = new Thread(action, prefix + index.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        };
    }

    private static final class Fixture implements AutoCloseable {
        final AiChatWebSocketHandler handler = new AiChatWebSocketHandler();
        final OciAiChatUtils ai = mock(OciAiChatUtils.class);
        final TenantRepository tenants = mock(TenantRepository.class);
        final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS,
                new LinkedBlockingQueue<>(), threads("ai-handler-test-worker-"));
        final ControlledScheduler scheduler = new ControlledScheduler();
        final ExecutorService callers = Executors.newSingleThreadExecutor(threads("ai-handler-test-ping-"));
        final List<CountDownLatch> releases = new CopyOnWriteArrayList<>();

        Fixture() {
            Tenant tenant = new Tenant();
            tenant.setId(7L);
            tenant.setTenantId("ocid1.user.oc1..fixture");
            tenant.setTenancy("ocid1.tenancy.oc1..fixture");
            tenant.setFingerprint("00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00");
            tenant.setKeyFile("/fixture/no-private-key-is-read.pem");
            tenant.setRegion("us-phoenix-1");
            tenant.setCloudType(1);
            when(tenants.findById(7L)).thenReturn(Optional.of(tenant));
            handler.tenantRepository = tenants;
            handler.ociAiChatUtils = ai;
            handler.taskExecutor = worker;
            ReflectionTestUtils.setField(handler, "delayedTaskExecutor", scheduler);
        }

        RecordingSocket connect(String id) throws Exception {
            RecordingSocket socket = new RecordingSocket(id);
            handler.afterConnectionEstablished(socket.session);
            Map<String, Object> tenant = new HashMap<>();
            tenant.put("tenantId", "7");
            tenant.put("modelId", "fixture-model");
            receive(socket, "init", "tenant", tenant);
            assertEquals("success", socket.only("init").get("status"));
            return socket;
        }

        void receive(RecordingSocket socket, String type, Object... fields) throws Exception {
            Map<String, Object> request = new HashMap<>();
            request.put("type", type);
            for (int i = 0; i < fields.length; i += 2) request.put((String) fields[i], fields[i + 1]);
            handler.handleTextMessage(socket.session, new TextMessage(JSON.writeValueAsString(request)));
        }

        void chat(RecordingSocket socket, String text, boolean history) throws Exception {
            receive(socket, "chat", "message", text, "tenantId", "7", "modelId", "fixture-model", "useHistory", history);
        }

        void reply(String text) throws Exception {
            doAnswer(call -> {
                Consumer<String> consumer = call.getArgument(3);
                consumer.accept(text);
                return null;
            }).when(ai).chatWithStreamOrThrow(any(Tenant.class), anyString(), anyString(), any());
        }

        void drain() throws Exception { worker.submit(() -> { }).get(WAIT_SECONDS, TimeUnit.SECONDS); }

        CountDownLatch releaseOnClose() {
            CountDownLatch release = new CountDownLatch(1);
            releases.add(release);
            return release;
        }

        @SuppressWarnings("unchecked")
        List<Map<String, String>> history(RecordingSocket socket) {
            Map<String, List<Map<String, String>>> histories = (Map<String, List<Map<String, String>>>)
                    ReflectionTestUtils.getField(handler, "conversationHistory");
            List<Map<String, String>> value = histories.get(socket.id);
            if (value == null) return null;
            synchronized (value) { return new ArrayList<>(value); }
        }

        @Override
        public void close() throws Exception {
            releases.forEach(CountDownLatch::countDown);
            try { handler.destroy(); }
            finally {
                worker.shutdownNow();
                scheduler.shutdownNow();
                callers.shutdownNow();
                boolean workerStopped = worker.awaitTermination(WAIT_SECONDS, TimeUnit.SECONDS);
                boolean schedulerStopped = scheduler.awaitTermination(WAIT_SECONDS, TimeUnit.SECONDS);
                boolean callersStopped = callers.awaitTermination(WAIT_SECONDS, TimeUnit.SECONDS);
                assertTrue(workerStopped && schedulerStopped && callersStopped, "all fixture threads terminate");
            }
        }
    }

    /** Keeps production scheduler callbacks, but only dispatches them when the test requests it. */
    private static final class ControlledScheduler extends ScheduledThreadPoolExecutor {
        final List<Runnable> heartbeats = new CopyOnWriteArrayList<>();
        final List<ScheduledFuture<?>> periodicFutures = new CopyOnWriteArrayList<>();
        final List<Runnable> delayedCloses = new CopyOnWriteArrayList<>();

        ControlledScheduler() { super(1, threads("ai-handler-test-heartbeat-")); setRemoveOnCancelPolicy(true); }

        @Override
        public ScheduledFuture<?> scheduleAtFixedRate(Runnable command, long initialDelay, long period, TimeUnit unit) {
            heartbeats.add(command);
            ScheduledFuture<?> future = super.scheduleAtFixedRate(command, 1, 1, TimeUnit.DAYS);
            periodicFutures.add(future);
            return future;
        }

        @Override
        public ScheduledFuture<?> schedule(Runnable command, long delay, TimeUnit unit) {
            // submit/execute also use this override with zero delay: retain normal dispatch there.
            if (delay == 0) return super.schedule(command, delay, unit);
            delayedCloses.add(command);
            return super.schedule(command, 1, TimeUnit.DAYS);
        }

        Future<?> runDelayedClose() {
            assertEquals(1, delayedCloses.size());
            return submit(delayedCloses.get(0));
        }
    }

    private static final class RecordingSocket {
        final String id;
        final WebSocketSession session = mock(WebSocketSession.class);
        final AtomicBoolean open = new AtomicBoolean(true);
        final AtomicInteger closeCount = new AtomicInteger();
        final AtomicReference<CloseStatus> closeStatus = new AtomicReference<>();
        final AtomicInteger activeWrites = new AtomicInteger();
        final AtomicInteger maxConcurrentWrites = new AtomicInteger();
        final List<Map<String, Object>> delivered = new CopyOnWriteArrayList<>();
        volatile String failedType;
        volatile boolean runtimeFailure;
        volatile String blockedType;
        volatile CountDownLatch writeEntered;
        volatile CountDownLatch releaseWrite;

        RecordingSocket(String id) throws Exception {
            this.id = id;
            when(session.getId()).thenReturn(id);
            when(session.isOpen()).thenAnswer(call -> open.get());
            doAnswer(call -> { close((CloseStatus) call.getArgument(0)); return null; })
                    .when(session).close(any(CloseStatus.class));
            doAnswer(call -> { close(CloseStatus.NORMAL); return null; }).when(session).close();
            doAnswer(call -> {
                TextMessage message = call.getArgument(0);
                @SuppressWarnings("unchecked")
                Map<String, Object> body = JSON.readValue(message.getPayload(), Map.class);
                int writers = activeWrites.incrementAndGet();
                maxConcurrentWrites.accumulateAndGet(writers, Math::max);
                try {
                    String type = (String) body.get("type");
                    if (type.equals(blockedType)) {
                        writeEntered.countDown();
                        await(releaseWrite, "release blocked native socket write");
                    }
                    if (type.equals(failedType)) {
                        if (runtimeFailure) throw new IllegalStateException("fixture concurrent/native writer failure");
                        throw new IOException("fixture transport write failure");
                    }
                    delivered.add(body);
                    return null;
                } finally { activeWrites.decrementAndGet(); }
            }).when(session).sendMessage(any());
        }

        void close(CloseStatus status) {
            open.set(false);
            closeStatus.set(status);
            closeCount.incrementAndGet();
        }

        List<Map<String, Object>> events(String type) {
            List<Map<String, Object>> result = new ArrayList<>();
            for (Map<String, Object> event : delivered) if (type.equals(event.get("type"))) result.add(event);
            return result;
        }

        Map<String, Object> only(String type) {
            List<Map<String, Object>> matches = events(type);
            assertEquals(1, matches.size(), "expected exactly one " + type + " event; delivered=" + delivered);
            return matches.get(0);
        }
    }
}
