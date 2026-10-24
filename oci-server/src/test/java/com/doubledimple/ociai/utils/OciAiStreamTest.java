package com.doubledimple.ociai.utils;

import com.doubledimple.dao.entity.Tenant;
import com.oracle.bmc.generativeaiinference.GenerativeAiInferenceClient;
import com.oracle.bmc.generativeaiinference.requests.ChatRequest;
import com.oracle.bmc.generativeaiinference.responses.ChatResponse;
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.retrier.BmcGenericRetrier;
import com.oracle.bmc.retrier.RetryConfiguration;
import com.oracle.bmc.waiter.MaxAttemptsTerminationStrategy;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/** Pure in-memory SSE/SDK tests; no Spring context, credentials or network. */
class OciAiStreamTest {
    private static final String PART = "data: {\"message\":{\"content\":[{\"type\":\"TEXT\",\"text\":\"hello\"}]}}\n\n";
    private static final String FINISH = "data: {\"finishReason\":\"STOP\"}\n\n";
    private final OciAiChatUtils utils = new OciAiChatUtils();
    private OciAiClientManager previousManager;
    private GenerativeAiInferenceClient client;
    private Tenant tenant;

    @BeforeEach
    void fakeSdkOnly() throws Exception {
        Field field = OciAiChatUtils.class.getDeclaredField("clientManager");
        field.setAccessible(true);
        previousManager = (OciAiClientManager) field.get(null);
        OciAiClientManager manager = mock(OciAiClientManager.class);
        client = mock(GenerativeAiInferenceClient.class);
        tenant = new Tenant();
        when(manager.getClientContext(tenant)).thenReturn(new OciAiClientManager.ClientContext(client, "fixture-compartment"));
        utils.setClientManager(manager);
    }

    @AfterEach
    void restoreManager() { utils.setClientManager(previousManager); }

    @Test
    void finishReasonStopsBeforeReadingPastFinalEventAndClosesStream() {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        List<String> chunks = new ArrayList<>();
        OciAiEventStreamReader.read(stream, chunks::add);
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
        assertEquals(0, stream.readsPastEnd);
    }

    @Test
    void previousDoneOrEofLoopWouldReadPastTheSameFinishReason() {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        assertThrows(AssertionError.class, () -> {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.startsWith("data:") && "[DONE]".equals(line.substring(5).trim())) break;
                }
            }
        });
        assertTrue(stream.closed);
        assertEquals(1, stream.readsPastEnd);
    }

    @Test
    void joinsMultilineSseEventsAndKeepsEveryTextPartIncludingTerminalText() {
        String events = ": keepalive\r\nid: 1\r\nevent: message\r\n"
                + "data: {\"message\": {\r\n"
                + "data: \"content\":[{\"type\":\"TEXT\",\"text\":\"你好\"},{\"text\":\" 🌍\"}]}}\r\n\r\n"
                + "data: {\"message\":{\"content\":[{\"text\":\"!\"}]},\"finishReason\":\"stop\"}\n\n";
        TrackingStream stream = new TrackingStream(events, true);
        List<String> chunks = new ArrayList<>();
        OciAiEventStreamReader.read(stream, chunks::add);
        assertEquals(Arrays.asList("你好", " 🌍", "!"), chunks);
        assertTrue(stream.closed);
    }

    @Test
    void acceptsDoneWithoutWaitingForEof() {
        TrackingStream stream = new TrackingStream(PART + "data: [DONE]\n\n", true);
        OciAiEventStreamReader.read(stream, part -> assertEquals("hello", part));
        assertTrue(stream.closed);
        assertEquals(0, stream.readsPastEnd);
    }

    @Test
    void acceptsFinalCompletedEventWithoutTrailingBlankLine() {
        TrackingStream stream = new TrackingStream(PART + "data: {\"finishReason\":\"LENGTH\"}", false);
        List<String> chunks = new ArrayList<>();
        OciAiEventStreamReader.read(stream, chunks::add);
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "event: error\ndata: {\"message\":\"fixture failure\"}\n\n",
            "data: {\"error\":{\"code\":\"fixture\"}}\n\n",
            "data: {\"errorMessage\":\"fixture failure\"}\n\n",
            "data: {\"code\":\"InternalServerError\",\"message\":\"fixture failure\"}\n\n"
    })
    void errorEventsFailAndPreserveEarlierText(String error) {
        TrackingStream stream = new TrackingStream(PART + error, true);
        List<String> chunks = new ArrayList<>();
        assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(stream, chunks::add));
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "not-json", "null", "[]", "{}", "{\"message\":[]}",
            "{\"message\":{\"content\":{}}}", "{\"message\":{\"content\":[{\"text\":123}]}}",
            "{\"finishReason\":null}", "{\"finishReason\":\"\"}"
    })
    void malformedEventsFailInsteadOfDisappearing(String data) {
        TrackingStream stream = new TrackingStream("data: " + data + "\n\n", true);
        assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(stream, part -> fail("Unexpected text")));
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(strings = {"ERROR", "ERROR_TOXIC", "ERROR_LIMIT", "USER_CANCEL", "CONTENT_FILTER", "UNKNOWN_REASON"})
    void failureFinishReasonCannotBecomeSuccessfulChatEnd(String reason) {
        TrackingStream stream = new TrackingStream(PART + "data: {\"finishReason\":\"" + reason + "\"}\n\n", true);
        List<String> chunks = new ArrayList<>();
        assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(stream, chunks::add));
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
    }

    @Test
    void unexpectedEofFailsEvenAfterSomeText() {
        TrackingStream stream = new TrackingStream(PART, false);
        List<String> chunks = new ArrayList<>();
        IllegalStateException error = assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(stream, chunks::add));
        assertTrue(error.getMessage().contains("完成标记之前中断"));
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(strings = {"data: [DONE]\n\n", FINISH,
            "data: {\"message\":{\"content\":[{\"text\":\" \\n\\t\"}]}}\n\ndata: [DONE]\n\n"})
    void completionWithoutReplyFails(String events) {
        TrackingStream stream = new TrackingStream(events, true);
        IllegalStateException error = assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(stream, part -> {}));
        assertTrue(error.getMessage().contains("未返回回复内容"));
        assertTrue(stream.closed);
    }

    @Test
    void nullStreamFails() {
        assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(null, part -> fail("Unexpected text")));
    }

    @Test
    void readFailurePropagatesAndCloses() {
        AtomicBoolean closed = new AtomicBoolean();
        IOException io = new IOException("fixture read failure");
        InputStream stream = new InputStream() {
            @Override public int read() throws IOException { throw io; }
            @Override public void close() { closed.set(true); }
        };
        IllegalStateException error = assertThrows(IllegalStateException.class, () -> OciAiEventStreamReader.read(stream, part -> {}));
        assertSame(io, error.getCause());
        assertTrue(closed.get());
    }

    @Test
    void consumerFailureIsNotConvertedIntoAssistantText() {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        IllegalStateException writeFailure = new IllegalStateException("fixture socket write failure");
        assertSame(writeFailure, assertThrows(IllegalStateException.class,
                () -> OciAiEventStreamReader.read(stream, part -> { throw writeFailure; })));
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void strictEntryPointsReadTheSharedCompletionProtocol(boolean history) {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        when(client.chat(any(ChatRequest.class))).thenReturn(ChatResponse.builder().eventStream(stream).build());
        List<String> chunks = new ArrayList<>();
        strict(history, chunks);
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
        verify(client).chat(any(ChatRequest.class));
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void strictEntryPointsPropagateSdkFailureWithoutFakeReply(boolean history) {
        IllegalStateException sdk = new IllegalStateException("fixture SDK client is closed");
        when(client.chat(any(ChatRequest.class))).thenThrow(sdk);
        List<String> chunks = new ArrayList<>();
        assertSame(sdk, assertThrows(IllegalStateException.class, () -> strict(history, chunks)));
        assertTrue(chunks.isEmpty());
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void strictEntryPointsRejectMissingSdkEventStream(boolean history) {
        when(client.chat(any(ChatRequest.class))).thenReturn(ChatResponse.builder().build());
        List<String> chunks = new ArrayList<>();
        assertThrows(IllegalStateException.class, () -> strict(history, chunks));
        assertTrue(chunks.isEmpty());
    }

    @ParameterizedTest
    @ValueSource(strings = {"single", "history", "sse"})
    void legacyEntryPointsRetainTheirFailureCallbackContract(String method) {
        when(client.chat(any(ChatRequest.class))).thenThrow(new IllegalStateException("fixture SDK failure"));
        List<String> chunks = new ArrayList<>();
        assertDoesNotThrow(() -> legacy(method, chunks));
        assertEquals(1, chunks.size());
        assertTrue(chunks.get(0).startsWith(" [AI服务异常: "));
    }

    @Test
    void legacySseEntryPointAlsoStopsOnFinishReason() {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        when(client.chat(any(ChatRequest.class))).thenReturn(ChatResponse.builder().eventStream(stream).build());
        List<String> chunks = new ArrayList<>();
        legacy("sse", chunks);
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void strictRequestsDisableSdkRetriesAndReturnTheFirst429(boolean history) {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        when(client.chat(any(ChatRequest.class))).thenReturn(ChatResponse.builder().eventStream(stream).build());
        strict(history, new ArrayList<>());

        ArgumentCaptor<ChatRequest> captured = ArgumentCaptor.forClass(ChatRequest.class);
        verify(client).chat(captured.capture());
        ChatRequest request = captured.getValue();
        RetryConfiguration retry = request.getRetryConfiguration();
        assertSame(RetryConfiguration.NO_RETRY_CONFIGURATION, retry);
        assertTrue(retry.getTerminationStrategy() instanceof MaxAttemptsTerminationStrategy);
        assertEquals(1, ((MaxAttemptsTerminationStrategy) retry.getTerminationStrategy()).getMaxAttempts());

        // Exercise the real SDK retrier with the actual request configuration.
        // The supplier is entirely local. MaxAttempts(1), checked above, stops
        // before the SDK evaluates a backoff delay or invokes it a second time.
        BmcException throttled = new BmcException(429, "TooManyRequests",
                "fixture tenant is throttled", "fixture-request-id");
        assertTrue(retry.getRetryCondition().shouldBeRetried(throttled),
                "The fixture must exercise a status that the SDK normally retries");
        AtomicInteger calls = new AtomicInteger();
        BmcGenericRetrier retrier = new BmcGenericRetrier(retry);
        BmcException result = assertThrows(BmcException.class, () -> retrier.execute(request, ignored -> {
            calls.incrementAndGet();
            throw throttled;
        }));
        assertSame(throttled, result);
        assertEquals(1, calls.get());
        assertTrue(stream.closed);
    }

    @ParameterizedTest
    @ValueSource(strings = {"single", "history", "sse"})
    void legacyRequestsLeaveSdkRetryConfigurationUnspecified(String method) {
        TrackingStream stream = new TrackingStream(PART + FINISH, true);
        when(client.chat(any(ChatRequest.class))).thenReturn(ChatResponse.builder().eventStream(stream).build());
        List<String> chunks = new ArrayList<>();
        legacy(method, chunks);

        ArgumentCaptor<ChatRequest> captured = ArgumentCaptor.forClass(ChatRequest.class);
        verify(client).chat(captured.capture());
        assertNull(captured.getValue().getRetryConfiguration(),
                "Legacy callers must retain their existing SDK/client retry policy");
        assertEquals(Collections.singletonList("hello"), chunks);
        assertTrue(stream.closed);
    }

    private void strict(boolean history, List<String> chunks) {
        if (history) utils.chatWithHistoryStreamOrThrow(tenant, history(), "fixture-model", chunks::add, null);
        else utils.chatWithStreamOrThrow(tenant, "fixture question", "fixture-model", chunks::add);
    }

    private void legacy(String method, List<String> chunks) {
        if ("history".equals(method)) utils.chatWithHistoryStream(tenant, history(), "fixture-model", chunks::add, null);
        else if ("sse".equals(method)) utils.chatWithStreamSse(tenant, "fixture question", "fixture-model", chunks::add);
        else utils.chatWithStream(tenant, "fixture question", "fixture-model", chunks::add);
    }

    private List<Map<String, String>> history() {
        Map<String, String> user = new HashMap<>();
        user.put("role", "user");
        user.put("content", "fixture question");
        return Collections.singletonList(user);
    }

    /** The old loop would hang here against a persistent response connection.
     * Throwing after the terminal bytes makes that regression fail immediately. */
    private static final class TrackingStream extends ByteArrayInputStream {
        private final boolean rejectEofRead;
        private boolean closed;
        private int readsPastEnd;

        private TrackingStream(String events, boolean rejectEofRead) {
            super(events.getBytes(StandardCharsets.UTF_8));
            this.rejectEofRead = rejectEofRead;
        }
        private void beforeRead() {
            if (pos >= count && rejectEofRead) {
                readsPastEnd++;
                throw new AssertionError("Reader requested more bytes after OCI's terminal event");
            }
        }
        @Override public synchronized int read() { beforeRead(); return super.read(); }
        @Override public synchronized int read(byte[] buffer, int offset, int length) {
            beforeRead();
            return super.read(buffer, offset, length);
        }
        @Override public void close() { closed = true; }
    }
}
