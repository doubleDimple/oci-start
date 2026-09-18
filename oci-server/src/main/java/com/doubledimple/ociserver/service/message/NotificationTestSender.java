package com.doubledimple.ociserver.service.message;

import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.DingTalkConfig;
import com.doubledimple.ociserver.pojo.request.FeishuConfig;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/** Explicit tests only: existing background senders keep their best-effort behaviour. */
@Component
public class NotificationTestSender {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final int MAX_RESPONSE_BYTES = 65536;

    public void telegram(TelegramConfig config, String message) {
        try {
            requireText(config.getBotToken());
            requireText(config.getChatId());
            if (!config.getBotToken().matches("[A-Za-z0-9_:-]+")) throw failure();
            Map<String, Object> body = new HashMap<>();
            body.put("chat_id", config.getChatId());
            body.put("text", message);
            JsonNode receipt = post("https://api.telegram.org/bot" + config.getBotToken() + "/sendMessage", body);
            JsonNode accepted = receipt.get("ok");
            if (accepted == null || !accepted.isBoolean() || !accepted.booleanValue()) throw failure();
        } catch (Exception e) {
            throw failure();
        }
    }

    public void dingTalk(DingTalkConfig config, String message) {
        try {
            requireText(config.getWebhook());
            requireText(config.getSecret());
            long timestamp = System.currentTimeMillis();
            String signature = sign(config.getSecret(), (timestamp + "\n" + config.getSecret()).getBytes(StandardCharsets.UTF_8));
            String separator = config.getWebhook().contains("?") ? "&" : "?";
            String url = config.getWebhook() + separator + "timestamp=" + timestamp
                    + "&sign=" + URLEncoder.encode(signature, "UTF-8");
            Map<String, Object> body = textBody("msgtype", "text", "content", message);
            requireCode(post(url, body), "errcode", 0);
        } catch (Exception e) {
            throw failure();
        }
    }

    public void bark(BarkConfig config, String message) {
        try {
            requireText(config.getUrl());
            requireText(config.getDeviceKey());
            Map<String, Object> body = new HashMap<>();
            body.put("device_key", config.getDeviceKey());
            body.put("body", message);
            requireCode(post(config.getUrl(), body), "code", 200);
        } catch (Exception e) {
            throw failure();
        }
    }

    public void feishu(FeishuConfig config, String message) {
        try {
            requireText(config.getWebhook());
            Map<String, Object> body = textBody("msg_type", "content", "text", message);
            if (StringUtils.isNotBlank(config.getSecret())) {
                String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
                body.put("timestamp", timestamp);
                body.put("sign", sign(timestamp + "\n" + config.getSecret(), new byte[0]));
            }
            JsonNode receipt = post(config.getWebhook(), body);
            // Accept either known receipt shape, but never a missing/malformed or contradictory code.
            boolean modern = receipt.has("code");
            boolean legacy = receipt.has("StatusCode");
            if (!modern && !legacy) throw failure();
            if (modern) requireCode(receipt, "code", 0);
            if (legacy) requireCode(receipt, "StatusCode", 0);
        } catch (Exception e) {
            throw failure();
        }
    }

    private static Map<String, Object> textBody(String typeKey, String container, String textKey, String message) {
        Map<String, Object> body = new HashMap<>();
        body.put(typeKey, "text");
        Map<String, String> text = new HashMap<>();
        text.put(textKey, message);
        body.put(container, text);
        return body;
    }

    private static String sign(String secret, byte[] data) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return Base64.getEncoder().encodeToString(mac.doFinal(data));
    }

    private static void requireCode(JsonNode receipt, String key, int expected) {
        JsonNode code = receipt.get(key);
        if (code == null || !code.isIntegralNumber() || !code.canConvertToInt() || code.intValue() != expected) {
            throw failure();
        }
    }

    private static void requireText(String text) {
        if (StringUtils.isBlank(text)) throw failure();
    }

    private static JsonNode post(String endpoint, Map<String, Object> body) throws Exception {
        URI uri = new URI(endpoint);
        if ((!"http".equalsIgnoreCase(uri.getScheme()) && !"https".equalsIgnoreCase(uri.getScheme()))
                || uri.getHost() == null || uri.getRawUserInfo() != null || uri.getRawFragment() != null
                || uri.getPort() == 0 || uri.getPort() > 65535) throw failure();
        HttpURLConnection connection = (HttpURLConnection) uri.toURL().openConnection();
        try {
            // No application retry or redirect: a failed receipt may still follow an accepted message.
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(10000);
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setUseCaches(false);
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            connection.setRequestProperty("Accept", "application/json");
            byte[] payload = JSON.writeValueAsBytes(body);
            connection.setFixedLengthStreamingMode(payload.length);
            try (OutputStream output = connection.getOutputStream()) {
                output.write(payload);
            }
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300 || connection.getContentLengthLong() > MAX_RESPONSE_BYTES) throw failure();
            ByteArrayOutputStream response = new ByteArrayOutputStream();
            try (InputStream input = connection.getInputStream()) {
                byte[] buffer = new byte[4096];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (response.size() + count > MAX_RESPONSE_BYTES) throw failure();
                    response.write(buffer, 0, count);
                }
            }
            JsonNode receipt = JSON.readTree(response.toByteArray());
            if (receipt == null || !receipt.isObject()) throw failure();
            return receipt;
        } finally {
            connection.disconnect();
        }
    }

    private static IllegalStateException failure() {
        // Neither the exception chain nor logs may retain a token, webhook, request or response body.
        return new IllegalStateException("通知测试未取得服务商成功回执，请核对接收端后再决定是否重试");
    }
}
