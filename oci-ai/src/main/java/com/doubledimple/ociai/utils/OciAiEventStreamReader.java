package com.doubledimple.ociai.utils;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.apache.commons.lang3.StringUtils;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.function.Consumer;

/** Reads OCI Generic chat SSE events and owns the response stream until completion. */
final class OciAiEventStreamReader {
    private OciAiEventStreamReader() {}

    static void read(InputStream stream, Consumer<String> chunks) {
        if (stream == null) {
            throw failure("OCI AI 未返回事件流");
        }
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream,
                StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)))) {
            State state = new State(chunks);
            StringBuilder data = new StringBuilder();
            boolean hasData = false;
            String eventType = "";
            String line;
            boolean firstLine = true;
            while ((line = reader.readLine()) != null) {
                if (firstLine && line.startsWith("\uFEFF")) line = line.substring(1);
                firstLine = false;
                if (line.isEmpty()) {
                    if ((hasData || "error".equalsIgnoreCase(eventType)) && state.event(eventType, data.toString())) return;
                    data.setLength(0);
                    hasData = false;
                    eventType = "";
                    continue;
                }
                if (line.startsWith(":")) continue;
                int colon = line.indexOf(':');
                String field = colon < 0 ? line : line.substring(0, colon);
                String value = colon < 0 ? "" : line.substring(colon + 1);
                if (value.startsWith(" ")) value = value.substring(1);
                if ("data".equals(field)) {
                    if (hasData) data.append('\n');
                    data.append(value);
                    hasData = true;
                } else if ("event".equals(field)) {
                    eventType = value;
                }
                // SSE id/retry and unknown extension fields do not carry chat text.
            }
            // Tolerate a final event without its optional trailing blank line,
            // but EOF alone must never turn an interrupted reply into success.
            if ((hasData || "error".equalsIgnoreCase(eventType)) && state.event(eventType, data.toString())) return;
            throw failure("OCI AI 事件流在完成标记之前中断");
        } catch (IOException e) {
            throw new IllegalStateException("读取 OCI AI 事件流失败", e);
        }
    }

    private static IllegalStateException failure(String message) {
        return new IllegalStateException(message);
    }

    private static final class State {
        private final Consumer<String> chunks;
        private boolean hasReply;

        private State(Consumer<String> chunks) { this.chunks = chunks; }

        private boolean event(String eventType, String data) {
            if ("error".equalsIgnoreCase(eventType)) throw failure("OCI AI 返回错误事件");
            if ("[DONE]".equals(data.trim())) return complete();
            final JSONObject event;
            try {
                Object parsed = JSON.parse(data);
                if (!(parsed instanceof JSONObject)) throw failure("OCI AI 事件格式无效");
                event = (JSONObject) parsed;
            } catch (IllegalStateException e) {
                throw e;
            } catch (RuntimeException e) {
                throw new IllegalStateException("OCI AI 事件 JSON 无效", e);
            }
            if (event.get("error") != null || event.get("errorMessage") != null
                    || "error".equalsIgnoreCase(event.getString("type"))
                    || "error".equalsIgnoreCase(event.getString("status"))
                    || (event.containsKey("code") && event.get("message") instanceof String)) {
                throw failure("OCI AI 返回错误事件");
            }

            boolean terminal = event.containsKey("finishReason");
            Object message = event.get("message");
            if (message != null) {
                if (!(message instanceof JSONObject)) throw failure("OCI AI 消息格式无效");
                Object content = ((JSONObject) message).get("content");
                if (content != null) {
                    if (!(content instanceof JSONArray)) throw failure("OCI AI 消息内容格式无效");
                    for (Object item : (JSONArray) content) {
                        if (!(item instanceof JSONObject)) throw failure("OCI AI 文本分片格式无效");
                        Object text = ((JSONObject) item).get("text");
                        if (text != null && !(text instanceof String)) throw failure("OCI AI 文本分片格式无效");
                        if (text instanceof String && !((String) text).isEmpty()) {
                            String part = (String) text;
                            chunks.accept(part);
                            hasReply |= StringUtils.isNotBlank(part);
                        }
                    }
                }
            } else if (!terminal) {
                throw failure("OCI AI 事件缺少消息或完成标记");
            }
            if (!terminal) return false;

            Object finishValue = event.get("finishReason");
            if (!(finishValue instanceof String) || StringUtils.isBlank((String) finishValue)) {
                throw failure("OCI AI 完成标记无效");
            }
            String reason = ((String) finishValue).trim().toUpperCase(Locale.ROOT);
            // Generic STOP/LENGTH and the equivalent normal completion names.
            // Error, cancellation, filtered and unknown endings must not be
            // silently promoted to a successful chat_end by the caller.
            if (!"STOP".equals(reason) && !"LENGTH".equals(reason)
                    && !"COMPLETE".equals(reason) && !"MAX_TOKENS".equals(reason)) {
                throw failure("OCI AI 回复未正常完成");
            }
            return complete();
        }

        private boolean complete() {
            if (!hasReply) throw failure("OCI AI 未返回回复内容");
            return true;
        }
    }
}
